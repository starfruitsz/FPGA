# 项目状态与交接说明（Agent Handoff）

> 目的：让其他 agent 在不读完全部历史的情况下，快速理解本仓库的目标、结构、当前状态、构建方式和下一步。
> 最后更新：2026-10-30，对应提交：当前分支最新提交（连续发送版本）。

## 0. 一句话概览

在 Anlogic EG4S20BG256（SparkRoad-V 开发板）上实现一个基于 VGA 的示波器：
外接 AD7606（8 通道 16bit 200kSPS，串行模式）采集波形，FPGA 内部完成触发/测量/图层合成，
通过 GM7123（24bit VGA）显示；串口支持在线配置。工程已用 TD 5.6.5 完成综合、布局布线与比特流生成，
**已完成首次上板验证（2026-10-30，VGA 显示与 50 Hz 正弦演示正常）**。

> 上板踩坑记录：`E2323swA` 显示器热漂移会导致「刚上电正常、几分钟后画面跳动」以及
> 「上半正常、下半抖动」；断电重启只暂时恢复，**换屏后彻底解决**（FPGA 输出自始正确）；
> JTAG 线被绑定到通用 WinUSB 时 TD 会报 `PRG-9505`，需装 TD 自带 `anlocyusb` 驱动。详见第 19 章。

## 1. 仓库与分支

| 项 | 值 |
|---|---|
| 仓库 | https://github.com/starfruitsz/FPGA |
| 当前分支 | fix/review-p1-p11（所有新功能/修复都在这里） |
| main | 原始高云工程 + 早期文档，保持不动 |
| 最新提交 | 46bc0f5（EG4 完整构建） |
| 提交数 / 跟踪文件 | 29 / 134 |
| 许可证 | 仓库代码 MIT（LICENSE），第三方参考见 THIRD_PARTY.md |

分支历史要点：

1. 原始高云 GW5A-25A 工程分析 + 注释 + LaTeX（main，PDF 116 页）；
2. 缺陷修复 P1–P12（P9 已回撤）；
3. 示波器 v2：触发状态机、预触发、扩展测量、双页文本、ADC 命令；
4. ADC 硬件抽象层（协议无关）+ AD7606 串行驱动；
5. SparkRoad-V（EG4S20BG256）移植 + 引脚映射 + TD 5.6.5 完整构建。

## 2. 硬件目标

| 项 | 参数 |
|---|---|
| FPGA | Anlogic EG4S20BG256（Eagle 系列；19600 LUT、64x9Kb BRAM、16x32Kb、29 DSP、4 PLL、188 pad） |
| 开发板 | SparkRoad-V（VeriMake） |
| 系统时钟 | 24 MHz，引脚 K14 |
| 显示 | GM7123 视频 DAC，RGB 各 8bit，HS/VS/CLK |
| ADC | 外接 AD7606 模块：8 通道、16bit、200kSPS、±5/±10V、串行/并行可选 |
| 数码管 | 4 位共阳（段低有效、位高有效） |
| 按键 | 5 个（BUTTON_L/R/U/D/C） |
| 串口 | USB2UART，TX=F16，RX=E16，115200 |

> 板载还有 12bit SAR ADC（AD1..AD7 模拟专用脚），本工程未使用；本工程用的是外接 AD7606，
> 接在树莓派排针的数字 IO 上。

## 3. 引脚映射（权威）

来源：FPGA/src/adc/pins/board_pins.csv（改引脚只改这里），
生成脚本 tools/gen_adc_pins.py -> FPGA_TD/eg4/SparkRoad.adc（51 引脚）。

| 信号 | 引脚 | 说明 |
|---|---|---|
| clk | K14 | 24MHz |
| rst_n | G11 | BUTTON_C，低有效 |
| key | H14 | BUTTON_L |
| uart_tx / uart_rx | F16 / E16 | 115200 |
| vga_clk | H2 | 给 GM7123 |
| vga_hs / vga_vs | J3 / J4 | |
| vga_r[0..7] | K6,K3,K5,L4,M1,M2,L3,L5 | 手册顺序 |
| vga_g[0..7] | L1,K2,K1,J1,H3,J6,H1,H5 | |
| vga_b[0..7] | G1,F1,F2,E1,G3,E2,D1,C1 | |
| seg[0..7] | E3,B3,F4,E4,F5,D3,B2,A2 | SEG_A..H |
| sel[0..3] | B1,C3,C2,F3 | DIG_1..4 |
| ad0..ad9 | C9,C8,C5,E8,A14,A4,A12,A10,A6,A7 | 24 脚并口 AD 数据（输入，上拉）|
| adclk | A8 | FPGA 输出，3.15MHz |
| da0..da9 | C7,C11,A11,B16,B15,C15,C16,A5,A9,A13 | 24 脚并口 DA 数据（输出）|
| daclk | A3 | FPGA 输出，3.15MHz |
| ad7606_convst（已停用） | A7 | 排针 3 |
| ad7606_busy | A8 | 排针 5 |
| ad7606_cs_n | A10 | 排针 7 |
| ad7606_sclk | A9 | 排针 8 |
| ad7606_douta | A5 | 排针 10 |
| ad7606_reset | A6 | 排针 11 |
| ad7606_ser | A3 | 或直接接 3.3V |

AD7606 其余：RANGE 悬空=±10V；STBY 接 3.3V；OS0..2 接 GND；模块 5V 供电，共地。

## 4. 顶层与数据流

顶层：FPGA/src/sparkroad_scope_top.v

    uart_rx --+--> scope_cmd --> vga_scope_top.cfg_*（时基/触发/滚动…）
               +--> adc_cmd   --> adc_ad7606_top.csr_*（量程/过采样/SCLK/采样率）

    AD7606 --> adc_ad7606_spi --> adc_norm(补码->偏移二进制->10bit) --> vga_scope_top.CH0
    vga_scope_top(640x480@~57Hz) --> RGB444 --> 每4bit复制为8bit --> VGA 引脚
                                 +--> seg 数码管显示 AD 码值
                                 +--> uart_tx 默认连续发送 16bit 帧（TX_MODE=0；=1 时每 1ms 一帧）

- CH1 暂接常量 512（板上无 DAC）；
- VGA 像素时钟 = 24MHz（PIX_DIV=1），场频约 57.1Hz；
- 串口命令两套解析器并行工作，互不干扰。

## 5. VGA 示波器分层

    src/vga/hal/     vga_timing.v（时序/px py de hs vs pix_ce）
                     vram_sdp.v（双口 BSRAM 1024x10）
                     font_rom.v（8x8 字模）
    src/vga/abs/     grid_layer.v / trace_layer.v / text_layer.v / compositor.v
    src/vga/app/     scope_capture.v（采集+触发状态机）
                     scope_ui.v（按键去抖）
                     scope_app.v（寄存器/会话状态/翻页）
                     scope_meas.v（Vpp/max/min/mean/period/freq/duty）
                     scope_cmd.v（ASCII 命令）
    src/vga/         vga_scope_top.v（集成）、vga_test_top.v / vga_test_app.v（自检图案）

关键设计：

- 无帧缓存：trace_layer 用相邻两列采样值连线，2 块 BSRAM 即可；
- 像素流水线：RAM 同步读 1 拍，颜色在 pix_ce 打入，hs/vs/de 延迟 2 拍（=1 像素）；
- 触发状态机：IDLE->ARMED->FILL->DONE；trig_mode 0=auto 1=normal 2=single；
- 预触发：触发时锁存 rd_base=waddr-pre_trig，显示从该地址读；
- 保持时间：holdoff 个采样点内忽略新触发；
- 双页文本：page 每 2 秒翻转（时域页 / 测量页）。

### 5.1 串口命令（示波器）

| 命令 | 含义 | 范围 |
|---|---|---|
| T<hex> | 时基分频 | 0–FFFF |
| R<hex> | 运行/冻结 | 0/1 |
| A<hex> | 触发使能 | 0/1 |
| L<hex> | 触发电平 | 0–3FF |
| E<hex> | 触发边沿 | 0/1 |
| S<hex> | 滚动开关 | 0/1 |
| M<hex> | 触发模式 | 0/1/2 |
| C<hex> | 触发源 | 0/1 |
| P<hex> | 预触发点数 | 0–3FF |
| H<hex> | 保持时间 | 0–FFFF |

## 6. ADC 硬件抽象层（AD7606）

    src/adc/hal/     adc_defs.vh / adc_backend_if.vh（契约）
                     adc_par.v / adc_stub.v / adc_spi.v（模板）
                     adc_ad7606_spi.v（串行驱动：CONVST/BUSY/CS/SCLK/DOUTA/RESET）
    src/adc/abs/     adc_norm.v（对齐/位宽/补码）、adc_cfg.v（CSR）
    src/adc/app/     adc_cmd.v（ASCII 命令）
    src/adc/         adc_top.v（并行/SPI/stub 工厂）、adc_ad7606_top.v（AD7606 通道）

AD7606 驱动行为：RESET 脉冲 -> 等待采样节拍 -> CONVST 脉冲 -> 等 BUSY 下降 ->
CS 低 + 64 个 SCLK（下降沿输出、上升沿采样）-> DOUTA 上 ch1..ch4 每 16bit 产生一个
r_valid（r_ch=0..3，16bit 补码）-> CS 高。

CSR 地址：

| 地址 | 名称 | 说明 |
|---|---|---|
| 0x00 | ID | version/impl/ch/res |
| 0x04 | CTRL | bit0 使能 |
| 0x08 | RATE | 采样间隔（clk） |
| 0x0C | GAIN | 预留 |
| 0x10 | OFFSET | 预留 |
| 0x14 | STATUS | locked/error |
| 0x18 | CH_EN | 通道使能 |
| 0x1C | FORMAT | align/signed |
| 0x20 | RANGE | 1=±10V 0=±5V |
| 0x24 | OS | 过采样 0..6 |
| 0x28 | SDIV | SCLK 半周期 |

ADC 命令（adc_cmd）：R=量程、O=过采样、S=SCLK 半周期、K=采样间隔、N=使能。
示例：R1（±10V）、O3（8 倍）、K95F（约 10kSPS）。

## 7. 构建工具链（TD 5.6.5）

| 项 | 路径/值 |
|---|---|
| TD 版本 | 5.6.5 SP5（170.155） |
| 安装路径 | C:/Anlogic/TD_5.6.5_SP5_170.155 |
| 器件库 | arch/eagle_s20.db（EG4S20，package EG4S20BG256） |
| License | license/Anlogic.lic（官方公开 NODELOCKED 版，`HOST_ID = ANY`，有效期 2027-09-30，不绑 MAC） |
| 工程 | FPGA_TD/scope_eg4_60.al（35 源文件 + .adc + .sdc） |
| 顶层 | sparkroad_scope_top |
| 比特流 | FPGA_TD/eg4/bit/scope_eg4_60.bit（634,296 字节） |

> TD 6.0.3（D:/FPGA）只有 PH1/PH2 器件库，不能用于 EG4；仅用于 PH1 容器工程的语法回归分析。

### 7.1 一键流程（必须在同一个 Tcl 会话）

FPGA_TD/full_flow60.tcl：

    create_project -family eg4 -device EG4S20BG256 scope_eg4_59 .
    add_files ...（35 个源文件）
    add_files ./eg4/SparkRoad.adc
    add_files ./eg4/SparkRoad.sdc
    top_module sparkroad_scope_top
    launch_runs syn_1
    wait_run syn_1
    launch_runs phy_1
    wait_run phy_1

执行：

    C:/Anlogic/TD_5.6.5_SP5_170.155/bin/td_commands_prompt.exe -nogui < full_flow60.tcl

> 注意：如果分两次会话（先 create/open，再 launch），TD 生成的运行脚本里
> import_device 参数为空，会报 USR-8002 Cannot open file .。
> GUI 打开工程后直接点 Run 不受此影响。

### 7.2 构建结果（已实测）

| 项 | 结果 |
|---|---|
| LUT | 1632 / 19600（8.33%） |
| 寄存器 | 832 / 19600（4.24%） |
| DSP | 6 / 29（20.69%） |
| BRAM | 4 / 64（6.25%） |
| PAD | 51 / 188（27.13%） |
| 时序 | 0 setup / 0 hold；最小周期 21.182ns（约 47MHz，约束 41.667ns） |
| 比特流 | 634,296 字节 |

报告位置：FPGA_TD/scope_eg4_60_Runs/phy_1/scope_eg4_59_phy.area / .timing / .tsm。

> **2026-10-30 重综合（P14，图层坐标对齐修复）**：工程 `scope_eg4_61`，
> LUT 1645/19600、REG 857（+25，与 12+12+1 完全吻合）、DSP 6/29、BRAM 4/64、
> PAD 51/188、setup slack +21.964 ns、0 setup / 0 hold 错误，
> 比特流 `FPGA_TD/scope_eg4_61_Runs/best_result/scope_eg4_61.bit`（634296 B）。
> 流程脚本 `FPGA_TD/full_flow61.tcl`。

### 7.3 日常操作（2026-11-01 实测打通）

| 操作 | 命令 |
|---|---|
| 打开工程（GUI） | `pwsh -File tools/td_open.ps1`（默认 scope_local4.al，可 `-Project xxx.al`） |
| 烧入 SRAM（掉电丢失） | `pwsh -File tools/td_burn.ps1`（自动取最新 `*_Runs/best_result/*.bit`） |
| GUI 里烧入 | TD → Tools → Programmer → 选 Cable → Program（SRAM） |

**约定：固化（写 SPI Flash）由用户手动操作；agent 只做"综合 + 烧入 SRAM"，不碰 Flash。**

下载器：`Anlogic AL-Link Mini`（`USB\VID_336C&PID_1002`），安路驱动 `anlocyusb.inf`
（服务 `ANLOCYUSB`，发布名 `oem128.inf`）。若设备回退到微软 `winusb.inf`，TD 报
`PRG-9505 USB device open error`，用管理员重装：

    pnputil /add-driver "C:\Anlogic\TD_5.6.5_SP5_170.155\driver\al-link\win10\x64\anlocyusb.inf" /install

固化参考（一般由用户做）：`create_flash_file` 生成带 `CC 55 AA 33` 头的镜像，再
`download -bit <bit> -mode program_spi -chip EG4S20BG256 -flashsize 32 -cable 0 -spd 1`。
**必须 `-spd 1`**：`-spd 4` 时 Flash ID 会读成全 1，报 `PRG-9516 unknown flash id`。
本板 Flash 厂商 ID `0xC8`（GigaDevice GD25 系列）。

### 7.4 本机 eg4 工程现状（2026-11-01）

仓库里的 `scope_eg4_60.al / scope_eg4_61.al` 有两处历史问题，直接 `open_project` 后
`launch_runs` 会失败：

1. `<Speed></Speed>` 为空 → `import_device` 参数缺失 → `USR-8002 Cannot open file .`
   （参照 `EG4S20BG256_scope.al` 的 `-5`）。
2. `full_flow60.tcl` 的文件清单少了 5 个后来新增的模块：`ad_da_par.v`、
   `vga/abs/menu_layer.v`、`vga/app/{scope_autoset,func_gen,sw_edge}.v` → black box。
3. `eg4/SparkRoad.adc` 还残留 7 条 AD7606 引脚约束（顶层已移除 AD7606）→
   `USR-8052/8168` 约束错误。

因此本机重建用 `FPGA_TD/make_scope_local24.tcl`（44 个源文件 + `-speed -5` +
`eg4/SparkRoad.adc`），**顶层用 `sparkroad_scope_pll`**（PLL 25.2MHz / 60Hz，
与仓库现行固件一致），生成 `scope_local7.al`：
LUT 5534/19600（28.23%）、slack +12.9ns、比特流
`scope_local24_Runs/best_result/scope_local24.bit`（2026-11-01 已烧入 SRAM 并固化）。

> **2026-11-01 算法级 40~54Hz 带通（新增 `FPGA/src/vga/app/bpf_ctrl.v`）**
> ADRC 的输入改成 `y = Filter(ADC) − Y_REF`，显示通路仍用原始 ADC。
> 中心 47Hz / BW 14Hz（Q=3.357）/ fs=3.15MHz；Chamberlin SVF，状态 Q16(32bit)，
> f=1573(Q24)、q=19521(Q16)，输出乘 q 归一化（中心增益=1）；-3dB 点实测 40.5/54.5Hz。
> 6 拍状态机分时复用 2 个乘法器；`adrc_en` 改由 `bpf_ctrl.dvalid` 驱动。
> ⚠️ 群延迟 2Q/ω0 ≈ 22.7ms，闭环调参要按此留相位裕度。

> **2026-11-01 三项修复**
> 1. **ADRC 参数已回退**：`eso.v` 恢复 `u=(k*(c*z1+z2)+sgn+c*z2-z3)>>>15`，c=150/k=20/b0=5000，
>    B01/B02/B03 不变（曾试 KP/KD/B0 经典形式，不合适已撤）。
> 2. **ADC 直流偏置消除**（新增 `FPGA/src/vga/app/dc_removal.v`）：均值跟踪
>    （时间常数≈1024 采样）后相减，只影响显示通路，AD/DA 模式启用；控制/触发/测量不受影响。
> 3. **eso 输出限幅到 ±512**：原来直接取 `viout>>>15` 的低 10 位，超范围会回卷，
>    导致"控制量打满/符号翻转看不出效果"；现在饱和在 DAC 码范围内。
>    LED[15]/LED[14] 分别指示 SW14/SW15 被读到的状态，便于确认开关是否生效。

> **2026-11-01 ADRC 控制律改为经典形式**（`eso.v` 级 6）：
>   `u0 = KP*(Y_REF - z1) - KD*z2`，`u = (u0 - z3)/B0`，`DAC = clamp(u+512)`
>   参数：**KP=20、KD=0、B0=500、Y_REF=-512（0V 对应中点制 -512）**；
>   观测器带宽 B01/B02/B03 保持 90/2700/27000 不变；`b0` 改为 500。
>   旧实现是 `u = (k*c*z1 + (k+c)*z2 + sgn - z3) >>> 15`（c/k 那条老路子），
>   现已不再参与输出（`k`/`c` 寄存器仍在但输出不用，TD 会优化掉）。

> **2026-11-01 SW15 滤波器换成"一阶稳态卡尔曼"**：原来的 50Hz 状态变量带通
> 谐振时状态摆幅是输入的 Q(5) 倍，20bit 定点会溢出 → 用户实测"一开滤波波形就变形"。
> 现改为常增益卡尔曼（等价一阶 IIR 低通，恒稳定无过冲）：
> `x += K*(z-x)`，K 按 `{adc_mode, tb_idx}` 查表使**等效截止恒为 150Hz**
> （50Hz 处 |H|=0.95），状态 24bit Q8，K 过大/过小时自动旁路。
> 文件仍是 `FPGA/src/vga/app/bpf50.v`（内容已换）。

> **2026-11-01 底部状态行新增 `V=` 电压跨度**：整屏 448 像素覆盖的电压范围，
> ADC 0..1023 映射 0..3.3V -> `V = 448*4096/(gain*1024)*3.3`，默认增益 1792 时正好 3.30V。
> 表由 `zoom_label.v` 里 61 档电压表给出（自动量程时按 vs_auto 折算索引）。

> **2026-11-01 横轴缩放改成"自适应采样率"**（`scope_app.v`）：
> `hscale` 固定 `HSC_MAX(102)` —— 一屏正好用满 1018 个采样点，缩放过程**不再丢弃采样点**；
> 左右键只改 `tb_idx`（采样率），放大 = 采样率提高、覆盖时间变短，缩小反之。
> 底部 `X` 仍按每次 ±0.5 记账。菜单 HSC 项保留为临时"细看"手段（会临时少点，
> 退出时建议按回 102）。

> **2026-11-01 修复滚动"纸带"右侧断线**（`vga_scope_top.v` g_scroll 段）：
> 原来窗口起点写死 `-640`，只有 S=64 时右边沿才压在最新采样上，S>64 时窗口越过
> 写指针 → 右半屏读到上一轮残留值，表现为"波形到屏幕中右部就断掉"。
> 现在窗口宽度 = 实际跨度 `span=(639*S)>>6`，右边缘恒等于最新采样；
> **基准更新必须每帧一次（实测）**：改"每行(hs)更新"会让同一列的采样地址随行号
> 前进，一帧 525 行累计偏移上百像素 —— 波形斜成一条对角线（用户报的"向右倾斜"）。
> 现在 `rd_base_s` 每帧 `frame` 锁一次，整屏用同一套地址，倾斜消失；
> 代价是纸带按帧步进，一屏时间 ≈ 一帧(16.7ms) 时最顺滑。

> **2026-11-01 新增 SW14 / SW15（sw 总线扩到 16 位）**
> - `sparkroad_scope_top/pll` 的 `sw` 端口从 `[8:0]` 扩到 `[15:0]`，
>   `.adc` 补齐 `sw[9..15]`（R9,P9,N9,T14,R14,T15,R15）。
> - **SW14(T15)**：控制量符号，拨上 `u -> -u`（`eso_u_sgn`）。
> - **SW15(R15)**：50Hz 带通显示滤波（`FPGA/src/vga/app/bpf50.v`，SVF/Q=5，
>   系数按 `{adc_mode,tb_idx}` 查表，每采一点推进一步，直接写显示 RAM）。

> **2026-11-01 垂直档位改为连续档 + SW6 控制 ADRC**
> - 垂直缩放从"右移位数 vs(2..7)"改成 **Q12 增益**：`z=(s-512)*vgain/4096`，
>   默认 `vgain=1792`(=7/16)，`vstep` 每步 ±1 = ×1.125，范围 ±30 步 = `Y` ±15.0（约 1200:1）。
>   相关：`trace_layer.v`(vgain)、`vga_scope_top.v`(gain_of 表 + vg_auto)、`scope_app.v`(vstep0/1)。
> - **SW6(N6) = ADRC 闭环使能**：拨上闭环 `y=ad_val-Y_REF`（参数 `Y_REF` 默认 512）；
>   拨下断开：`y` 强制 0、`u` 归零、DA 输出回中值 512。

> **并口 AD/DA 引脚已补齐（2026-11-01）**：`ad0..ad9/adclk/da0..da9/daclk` 共 22 条以前完全没有约束，
> TD 会乱放到无关管脚（曾出现 `adclk=D5`，模块收不到转换时钟 → ADC 恒 0、只剩 DA 有值）。
> 现按用户接线表写入 `eg4/SparkRoad.adc`（由 `FPGA/src/adc/pins/adda_pins.csv` +
> `tools/gen_adda_pins.py` 生成），AD 脚还自动带上了上拉。

> **通道配色（2026-11-01）**：AD/DA 模式下 CH0 = AD 采样、CH1 = DA(ADRC u)，
> 按要求改为 **CH0 黄色 `12'hFF1`、CH1 蓝色 `12'h33F`**（原绿/黄），
> 参数在 `vga_scope_top.v` 的 `COL_CH0 / COL_CH1`。

> **2026-11-01 关键缺陷：约束文件缺 5 个拨码开关 + 全部 AD/DA 引脚**
> `eg4/SparkRoad.adc` 原本只绑了 `sw[0..3]`(T4/R5/T5/T6)，**`sw[4..8]` 完全没约束**
> （TD 自动乱放/悬空）。后果：SW7(P8) 读到高电平 → U/D 变成"移基线"而不是调纵向档；
> SW8(N8) 根本没接 → 拨 SW8 模式不切换，"内部函数发生器"以为选了其实没选。
> 已补：`sw[4]=M6, sw[5]=P6, sw[6]=N6, sw[7]=P8, sw[8]=N8`（来自 doc/SparkRoad-V_pinmap.md）。
>
> **仍未约束**：24 脚并口 AD/DA 的 `ad0..ad9 / adclk / da0..da9 / daclk`（22 个 IO）
> 在 `.adc` 里一条都没有 → AD/DA 模式目前接不到外部模块，需要按实际接线补齐。

底部第 58 字符行新增缩放档标签 `X:+0.5 Y:-1.0 T=46667U`（`FPGA/src/vga/abs/zoom_label.v`）：

| 字段 | 含义 | 范围 |
|---|---|---|
| `X` | 横轴缩放档（带小数）：每按一次放大 +0.5、缩小 -0.5，0.0=不缩放 | ±30.0 |
| `Y` | 纵轴缩放档 = (4-vs)x0.5，取自 SW2 选中通道 | +1.0 … -1.5 |
| `T` | 整屏时间（640 像素覆盖的真实时间），按模式换算采样节拍 | 1.0us … 1.9s |

> `X` 是**按键计数**（`scope_app.hzoom10`，单位 0.1 档），不跟随 S/时基反推；
> 切换 SW8 模式时计数清零、`hscale`/`tb_idx`/`tb_div` 一并复位到 1:1
> （`tb_div=0` 最快档），保证一换模式就能看到完整波形——这是"切到自发生模式没波形"
> 的修复：旧版本会把上一模式的极端缩放/时基带过去，50Hz 被压成一条直线。

> `X` 以"1 采样点/像素 + 最快时基"为 0 点，同时受 `hscale`(1..102, 64=1:1) 和
> `tb_idx`(0..15) 影响；`Y` 取当前选中通道(SW2)的 `vs`(右移位数 2..7，4=1:1)。
> 字符 `+` 是 2026-11-01 新加到 `hal/font_rom.v`（码 41）和 `tools/gen_font.py`。

> 注意 `sparkroad_scope_pll` 里 `DEMO_SINE(1)`：上电自动下发 T0/A1/M1/L512，
> 即**时基被强制到最快档（tb_div=0）**。AD/DA 模式下 ADC 每 8 clk 一个样本，
> 于是最宽只有约 340us/屏 —— 这就是"2000Hz 连半个周期都装不下、低频正弦看着像直流"
> 的根因。2026-11-01 已把左右键改成可跨时基档，整屏时间可在 3.3us ~ 1.9s 间连续调。

## 8. 目录与关键文件

    FPGA/src/          原始高云工程 9 个手写模块 + IP + .cst/.gprj
    FPGA/src/vga/      VGA 示波器（hal/abs/app + 3 个顶层）
    FPGA/src/adc/      ADC HAL（hal/abs/app + 2 个顶层）
    FPGA/src/sparkroad_scope_top.v   SparkRoad-V 总顶层
    FPGA_TD/           TD 工程（5.6.5 的 scope_eg4_60.al、脚本、约束、bit）
    doc/               LaTeX 文档（ch01–ch20 + baseline/）
    sim/               RTL 仿真（Icarus）：14 个 testbench + run_all.ps1 + 波形出图 + PLL 空壳
    tools/             注释/校验/引脚生成/上位机等脚本
    README.md          对外说明
    FIXES.md           修复记录 P1–P13
    ADC_HAL_plan.md    ADC HAL 设计与可配置项
    CODE_READING_GUIDE.md  VS Code 代码阅读路线/文件职责/技巧
    PROJECT_STATE.md   本文（agent 交接）

关键工具：

| 工具 | 用途 |
|---|---|
| tools/gen_adc_pins.py | CSV -> .adc 约束 |
| tools/check_ports.py | 模块/例化端口静态检查 |
| tools/check_vga_comments.py | 校验注释改动未改代码 |
| tools/scope_host.py | PC 上位机（pyserial+matplotlib） |
| tools/install_td56.ps1 | TD 5.6.5 静默安装/检查 |

## 8.1 VS Code 阅读

- 打开：code C:/Users/Administrator/Desktop/task；
- 预配置 .vscode/：*.v→verilog、排除 *_Runs/impl/_remote、5 个一键任务；
- 指南：CODE_READING_GUIDE.md（30 分钟路线 + 文件职责 + 搜索关键词）。

## 9. 文档系统

- doc/main.tex 汇总 19 章 + 附录，PDF 132 页；
- 各章 ch01..ch19，第 17 章修复记录、第 18 章 v2、第 19 章 SparkRoad 移植/上板/引脚/参数教程；
- doc/baseline/ 存放 main 分支的原始源码副本，保证旧章节行号仍有效；
- 编译：cd doc && xelatex main.tex 跑两遍；产物 main.pdf 同步到根目录 FPGA_project_analysis.pdf。

## 10. 验证状态

| 项 | 状态 |
|---|---|
| TD 5.6.5 分析（35 文件） | 通过 |
| 综合/布局布线/比特流 | 通过（见 7.2） |
| 端口静态检查 | 35 模块 / 47 例化 / 0 错误 |
| 引脚约束 | 20 信号 / 51 引脚，无重复 |
| 仿真 | 已建立（Icarus Verilog 14，14 用例全过，含整机 `sparkroad_scope_top`，见 `sim/` 与第 20 章） |
| 上板 | ✅ 已完成（2026-10-30）：JTAG 下载通过、VGA 640×480@60Hz 正常、内部 50Hz 正弦稳定显示；详见第 19 章「首次上板实录」 |

## 11. 已知限制与风险

1. 板上无 DAC，CH1 固定 512；AD7606 只读 DOUTA 的 ch1–ch4（ch5–8 需 DOUTB）；
2. 24MHz 像素时钟下场频约 57.1Hz，个别显示器可能不接受；可用 PLL 出 25.175MHz；
3. 频率/周期基于采样节拍统计，分辨率有限；RMS/ETS 未实现；
4. SDC 只约束了 24MHz 时钟，未做 IO 时序约束；
5. License 为 node-locked（MAC 40-A5-EF-5E-1D-40），换机需重新申请；
6. TD 6.0.3 无 EG4 器件库；Tcl 流程有“同会话”限制（见 7.1）；
7. 串口 ASCII 命令与二进制帧共用 rx，二进制帧可能被 ASCII 解析器忽略（不会误写 CSR，但不要混发）。

## 12. 下一步（按顺序）

0. **上板请用新比特流** `FPGA_TD/scope_eg4_61_Runs/best_result/scope_eg4_61.bit`
   （旧 `scope_eg4_60.bit` 对应修复前的 RTL，已作废）；
1. 上板：TD Programmer 加载新比特流，先看 VGA；
2. 数码管/串口/AD7606 逐项验证（详见第 19 章 19.10）；
3. 记录实测现象，把“首次上板实录”补进第 19 章；
4. 视需要加 PLL（25.175MHz）、DOUTB（ch5–8）、RMS/ETS；
5. 可选：PC 上位机联调（tools/scope_host.py）。

## 13. 常见任务

### 改引脚
1. 编辑 FPGA/src/adc/pins/board_pins.csv；
2. 跑 python tools/gen_adc_pins.py；
3. 重新跑综合流程（见 7.1）。

### 改参数
- 编译期：adc_ad7606_top 的 RES/SDIV_DEF/OS_DEF/RANGE_DEF、vga_scope_top 的 CLK_HZ/PIX_DIV/FEAT_*；
- 运行期：串口命令或 CSR（见 6）。

### 新增 ADC 型号
1. 在 src/adc/hal/ 新建驱动，实现 raw stream（r_data/r_ch/r_valid）；
2. adc_top.v 的 generate 加分支；
3. 顶层加引脚、CSV 加行、重生成约束。

### 重跑综合
    cd C:/Users/Administrator/Desktop/task/FPGA_TD
    C:/Anlogic/TD_5.6.5_SP5_170.155/bin/td_commands_prompt.exe -nogui < full_flow60.tcl

## 14. 约定

- 源码注释为中文，只加 // 行注释；改注释不得改动代码 token；
- 模块命名：HAL 器件无关、ABS 图形/归一化、APP 业务；
- 提交信息用 feat/fix/docs(scope): 前缀；
- 新功能只加在 fix/review-p1-p11 分支，main 保持原样以便回退；
- 算法类代码（滤波/开方/除法/周期估计/自动量程等）优先从开源社区（如 GitHub）获取现成实现，并注明仓库与 license；GitHub 上找不到、或用户明确强调/给出实现时，才手搓。

## 15. 快速命令

    # 校验端口
    python tools/check_ports.py

    # 生成约束
    python tools/gen_adc_pins.py

    # 编译文档
    cd doc
    xelatex main.tex
    xelatex main.tex

    # 打开工程（GUI）
    C:/Anlogic/TD_5.6.5_SP5_170.155/bin/td.exe FPGA_TD/scope_eg4_60.al

---

## 待完成清单（与产品手册附录 C 同步）

### 已完成
- [x] 4 键操作（短按 / 长按）
- [x] 双页菜单 UI（P0 示波器 / P1 信号源）
- [x] 垂直档位与垂直位置
- [x] 水平缩放（独立于时基，不重新采集）
- [x] 时基 / 滚动 / 运行停止（概念已拆开）
- [x] 内置函数发生器（4 波形 / 8 频率 / 4 幅度 / 10 档相位）
- [x] ADC 模式下信号源自动禁用（GEN_ENA）

### 待完成
| 编号 | 功能 | 优先级 |
|---|---|---|
| A1 | 触发电平虚线 | P2 |
| A2 | 触发点标记 | P2 |
| A3 | 采集状态指示（ARMED/TRIG'D/STOP/AUTO） | P2 |
| A4 | 光标测量（ΔT / ΔV） | P4 |
| A5 | 通道颜色可选 | P4 |
| A6 | 菜单交互增强（闪烁/加速） | P4 |
| B1 | AUTOSET 自动量程 | P3 |
| B2 | 双通道真并行采集（当前交错写同一 RAM，设计缺陷） | P3 |
| B3 | 双缓冲显示（消除撕裂） | P4 |
| B4 | Vrms 有效值 | P3 |
| B5 | 频率连续可调（现仅 8 档） | P3 |
| B6 | 外部 ADC 实测验证 | P2 |
| B7 | 预触发 / 保持时间界面化 | P3 |
| C1 | LED 状态指示 + 电平条 | P2 |
| C2 | 数码管显示信号源参数 | P2 |
| C3 | 拨码开关扩展 | P4 |
| D1 | 串口新增参数命令 | P3 |
| D2 | 设置导出 / 状态回读 | P4 |
| E1 | 配置 Flash 固化 | P1 |
| E2 | 手册随固件同步 | P1 |
| E3 | 按键行为回归用例 | P2 |

---

## 16. 2026-11-02：彻底移除 dc_removal（固件 scope_local29）

**诉求**：用户实测"直流偏置问题变严重了"，决定放弃自适应偏置 —— "实在不行将直流偏置关了吧"。

**实际状态**：该功能在 local27（`ca7b71f`）起就已旁路（`dc_on(1'b0)`），
所以"变严重"正是"关掉"的直接结果：以前那个有 bug 的一次性校零至少会把波形往上顶 +512，
现在不顶了，ADC 原始零点落在哪就画在哪。

**本次改动**（`vga_scope_top.v:492-506`）：
- 删除 `dc_removal u_dc0 / u_dc1` 两处例化，`bpf50` 的 `din` 直接接 `ch0_in/ch1_in`；
- `dc_removal.v` 文件保留但不再被例化（要找回随时可以）；
- 显示通路 = **原始采样 -> bpf50(SW15) -> 显示 RAM -> trace_layer**，中间没有任何偏置运算。

**证据（为什么说它和画面无关）**：local29 与 local28 的综合结果**逐项相同** ——
LUT 7108/19600（36.27%）、REG 2256、DSP 29/29、BRAM32K 2/16、PAD 101/188、
setup slack **+7.765 ns**、0 setup / 0 hold 违规。
即该模块早已被综合器当常量直通优化掉，删不删都不改变比特流行为。

**留下的诊断入口（不用改代码）**：底部第 1 页 `AD=<CH0 原始码 hex> U=<CH1 hex> TB=<tb_div>`，
第 2 页 `HI=<vmax> LO=<vmin> AV=<vmean>`（每 2 秒翻页）。判断 ADC 是否正常就看这三个数。

**下一步（若用户要求"上电居中"）**：用 `scope_meas` 已有的 `vmean` 做静态重定位
`y = clamp(ch0_in - vmean + 512)`，无状态机、上电不会锁零点；**不要恢复 dc_removal**。

---

## 17. 2026-11-02 下午：SW13 带通总开关 + 修复带通系数（固件 scope_local30）

**背景**：用户实测"现象 DAC 几乎没有"，并提两条新需求。

### 17.1 根因：带通系数没跟着采样率改（真 bug）

`80878dc` 把 48Hz 带通挪到 `decim512` 之后（采样率 3.15MHz → **6152.34Hz**），
但 `bpf_ctrl.v` 的系数一直停留在 3.15MHz 时代的 `F_Q24 = 1606`：

| 量 | 值 |
|---|---|
| 旧 F_Q24 | 1606 → f = 1606/2^24 = 9.57e-5 |
| 实际中心频率 | `asin(f/2)*fs/pi` = **0.094 Hz**（不是 48 Hz）|
| 48Hz 处增益 | ≈ f0/f = 0.002，即 **-54 dB** |
| 后果 | y 基本等于直流 → ESO 的 z3 恒定 → **u 恒定 → DAC 几乎不动** |

已改为 **F_Q24 = 822350**（= 2·sin(π·48/6152.34)），中心 48Hz / Q=2.4（38~58Hz），
与 HANDOFF §4.2 文档里写的值一致（文档对、代码没跟上）。

### 17.2 新增需求：SW13（R14）做带通总开关

| SW13 | 显示 CH0 | ADRC 的 y | SW15（显示卡尔曼） |
|---|---|---|---|
| **拨上（开）** | 带通输出 `ad_bpf` | 带通输出 `ad_bpf` | **失效**（被屏蔽）|
| 拨下（关） | 原始采样 `ad_val` | 原始采样 `ad_val` | 生效 |

实现（`sparkroad_scope_top.v`）：
- `:144-145` 新增 `sw_edge u_sw13`（`sw[13]` = R14）
- `:276-278` `bpf_on = sw13_lv`；`ad_ctrl = bpf_on ? ad_bpf : ad_val`，
  显示与 y **共用同一个 `ad_ctrl`**，保证"屏上看到的 = 算法喂进去的"
- `:347` `ch0_val = adc_mode ? ad_ctrl : gen0_data`
- `:412` `sw_filt = sw15_lv & ~bpf_on`（SW15 只在带通关闭时生效）
- `:559` LED[13] 指示 SW13 当前电平（低亮）

---

## 18. 2026-11-02 傍晚：带通打开后变成"开关信号"——有符号乘法 bug（固件 scope_local31）

**现象**（用户实测，两张对比图）：SW13 拨下（关带通）CH0 是正常正弦；
SW13 拨上（开带通）CH0 变成满幅方波，用户描述"y 变成了开关信号"。

**根因**：`bpf_ctrl.v:63` 的乘法少了 `$signed()`：

```
wire signed [63:0] qb_64 = band * {{48'b0, Q_Q16}};   // 错：右操作数无符号
```

Verilog 规则：只要有一个操作数无符号，有符号的 `band` 会先**零扩展**成 64bit 再相乘。
于是正弦负半周（band 为负）时，`-1000` 被当成 `0x00000000_FFFFFC18`(≈4.29e9)，
乘积巨大且为正，再 `>>>16`（无符号=逻辑右移）得到错误的 `qb` →
`high`/`band` 被彻底带偏 → 输出在两个电平之间来回跳。

**为什么之前没暴露**：系数 1606（对应 3.15MHz）时 f 极小，被破坏的反馈量也极小，
表现为"输出几乎等于直流"（就是第 17 节那个"DAC 几乎没有"）；系数改成 822350 之后
f 放大 512 倍，每个半周都被打坏 → 立刻变成方波。

**修复**：`wire signed [63:0] qb_64 = band * $signed({48'b0, Q_Q16});`

**验证**（两条独立路径。注：先前写的"Icarus 对该乘法段错误、无法写 TB"是误判，
真因是 `vvp` 的 PATH 漏了 `oss-cad-suite/lib`；补上后 RTL 仿真正常）：

路径 A —— RTL 仿真 `sim/tb_bpf_ctrl.v`（已注册进 `run_all.ps1`）：
| 版本 | n | hits | pp | gain | 判定 |
|---|---|---|---|---|---|
| 输入 48Hz ±47 码 | — | — | 94 | 1.0 | — |
| 修复前 | 5000 | 4000 | 487 | **5.181** | FAIL |
| 修复后 | 5000 | 4000 | 93 | **0.989** | PASS |

路径 B —— 位精确 Python 模型 `tools/bpf_model.py`（逐拍复现 32bit 回卷与算术右移）：

| | min | max | pp | 结论 |
|---|---|---|---|---|
| 输入 48Hz 正弦 ±100 码 | 412 | 612 | 200 | — |
| 修复前 | 214 | 809 | **595** | 两个电平来回跳 = "开关信号" |
| 修复后 | 411 | 612 | **201** | 增益 1.00，平滑正弦 |

运行：`python tools/bpf_model.py`（PASS 返回 0）。

---

## 19. 2026-11-02：verilator 门禁落地 + 一处 56bit 符号扩展真缺陷（固件 scope_local32）

### 19.1 环境：不需要下载，工具本来就在

上一轮写"本机 verilator 缺 Perl 模块 Pod::Usage，需要先修环境"，**结论错了一半**：

| 问题 | 真相 | 解法 |
|---|---|---|
| `bin/verilator` 报 Can't locate Pod/Usage.pm | 它是 Perl 包装脚本，走本机 MSYS perl 5.42（缺该模块） | 直接调同目录的 **`verilator_bin.exe`**（真二进制），无需安装任何东西 |
| `verilator_bin` 报 Cannot find verilated_std.sv | 二进制里 `VERILATOR_ROOT` 编译期写死成构建机路径 `/yosyshq/share/verilator` | `export VERILATOR_ROOT=<suite>/share/verilator` |

两条都封进 `tools/lint.sh`，以后一条命令即可：`bash tools/lint.sh`。

### 19.2 门禁策略（BLOCK / ADVISORY）

- **BLOCK**：`bpf_ctrl.v` —— 必须零告警（本次事故模块）
- **ADVISORY**：`bpf50(1) / decim512(2) / eso(24) / trace_layer(8) / scope_meas(3)` 共 38 条历史遗留宽度告警，只打印不阻塞；清完一个挪一个进 BLOCK

### 19.3 一个必须说清的边界（自我纠正）

**verilator -Wall 抓不到本次这个 bug。** 它没有 signedness 告警；
它对 `band * {{48'b0,Q_Q16}}` 不吭声。它抓到的是**宽度**问题。
所以：

| 缺陷类别 | 守卫 |
|---|---|
| 宽度/截断/符号扩展位数 | `tools/lint.sh`（verilator） |
| **有符号/无符号混用** | `sim/tb_bpf_ctrl.v`（已进回归，修复前 gain=5.181 FAIL）+ `tools/bpf_model.py` 双重守卫 |
| 功能正确性 | testbench 已补齐并注册（此前"无法建 TB"的结论已更正） |

上一轮我说"这类混合符号会给 SIGNED/WIDTH 警告"，那句是错的，这里更正。

### 19.4 lint 顺手抓出的真缺陷（已修）

`bpf_ctrl.v:52` 原来是 `{{32{F_Q24[23]}}, F_Q24}`：24 + 32 = **56 bit**，
赋值给 64bit 时被零扩展补满。当前 `F_Q24=822350`（正数，符号位=0）时结果碰巧正确，
但一旦把它改成负数就会错。已改为 `{{40{F_Q24[23]}}, F_Q24}`（24+40=64）。

另 3 处 `x <= m64 >>> N`（64→32 截断告警）改成部分选择 `m64[55:24] / qb_64[47:16]`，
对二进制补码与原写法**位等价**，但让告警消失、门禁可读。

### 19.5 综合对比（scope_local32）

| 项 | local31 | local32 |
|---|---|---|
| LUT | 7351（37.51%） | 7351（37.51%） |
| REG | 2326 | 2326 |
| DSP / BRAM32K | 29/29、2/16 | 29/29、2/16 |
| slack | +5.369 ns | +5.369 ns |
| 置位位数 | 268007 | 268007 |

逐项相同 → 宽度清理是**零行为变化**的等价改写。

---

## 20. 2026-11-02 晚：仿真环境真因查明 + tb_bpf_ctrl 进回归（本轮无 RTL 逻辑改动）

### 20.1 自我更正（重要）

前两轮我一直说"Icarus 14 对该模块 32×64 有符号乘法会段错误，所以无法建 TB"。
**错。** 真因是 vvp 运行时 **PATH 漏了 `oss-cad-suite/lib`**（DLL 目录）：

| 命令 | 结果 |
|---|---|
| `export PATH=<suite>/bin` + `vvp` | 段错误（exit 139），连 "hello world" 的 TB 都崩 |
| `export PATH=<suite>/bin:<suite>/lib` + `vvp` | 正常输出、`$finish` 正常 |

HANDOFF §2.4 早就写了"必须先把它加进 PATH"，我只加了 `bin` 没加 `lib`，
于是把自己环境问题误判成模拟器缺陷，还写进了文档和提交信息。已全部更正。

### 20.2 tb_bpf_ctrl 重写并进回归

旧版本有两个硬伤：en 分频 4096 + 只跑 300 万拍 → 只有 732 个采样，
而判据要求 `n>2000`，于是 hits 恒为 0、mx/mn 保持初值，**必然 FAIL**。

重写后（en 每 8 拍一次，跑 4 万拍 = 5000 个采样，判据显式给 pp 窗口）：

| 被测 RTL | n | hits | pp（输入 94） | gain | 判定 |
|---|---|---|---|---|---|
| 修复前（`qb_64` 无 `$signed`） | 5000 | 4000 | 487 | 5.181 | **FAIL** |
| 修复后（当前） | 5000 | 4000 | 93 | 0.989 | **PASS** |

**结论：这条 TB 能真正拦住那个 bug**（不是摆设），已注册进 `run_all.ps1`。

### 20.3 回归基线（21 个用例）

```
TOTAL: PASS=16  FAIL=5  SKIP=0
```

| 失败用例 | 原因 |
|---|---|
| `trace_layer` | TB 端口 `vshift` 在 Q12 增益重构后已不存在（改名 `vgain`）→ 编译失败 |
| `scope_app` | TB 端口 `vs0/vs1` 已改名 `vstep0/vstep1` → 编译失败 |
| `vga_scope_top` / `_pix2` | 11 条坐标/幅度期望值是垂直增益重构前的旧值 |
| `sparkroad_top` | 3 条：整机波形/幅度期望值未跟上 SW13 与 ad_ready 的改动 |

### 20.4 本轮**没做**的事（以及为什么）

ADVISORY 里 38 条宽度告警**本轮不动**，理由是本轮刚用血的教训换来的规矩：

> **没有 testbench 覆盖的模块，不允许为了消警告改位宽。**

`eso.v`(24)、`trace_layer.v`(8)、`scope_meas.v`(3)、`decim512.v`(2)、`bpf50.v`(1)
里这些是真·隐式符号扩展（有符号运算里位宽小的一方本来就会被符号扩展，语义正确），
属于**风格问题不是缺陷**。要动就先把 TB 补齐（`eso` 已有、其余没有），再改，
改完用 TB 证明位等价。顺序建议：`trace_layer`（顺带修好它的 TB 端口）→ `scope_meas` → `decim512` → `bpf50` → `eso`。

---

## 21. 2026-11-02 深夜：trace_layer 进 BLOCK（TB 端口适配 + 位宽清理）

### 21.1 先把 TB 变成可信 oracle，再动 RTL

`sim/tb_trace_layer.v` 用的是旧端口 `vshift`（右移位数），Q12 重构后已不存在。
**不是改个名字**：映射从 `(d*7)>>>vs` 变成了 `(d*vgain)>>>12`，两者在二进制补码下逐位等价的前提是

```
vgain = 7 << (12 - vs)      // vs=3 -> 3584,  vs=4 -> 1792
(d*7) >>> vs  ==  (d*vgain) >>> 12
```

所以 TB 里保留 `vs` 作为用例参数，端口传 `7<<(12-vs)`，参考模型同步改。
先对**未改动的 RTL** 跑一遍：19 个用例 × 480 行逐像素比对 **PASS** —— 这时它才有资格当判据。

### 21.2 trace_layer.v 的位宽清理（位等价）

| 原写法 | 现写法 | 理由 |
|---|---|---|
| `localparam [11:0] PLOT_TOP = PLOT_H - 1;` | `PLOT_H[11:0] - 12'd1` | 参数派生常量显式限位，消除 WIDTHTRUNC 噪音 |
| `localparam signed [18:0] Y_MAX = PLOT_H - 1;` | `{7'd0, PLOT_H[11:0]-12'd1}` | 同上 |
| `z_now = p_now >>> 12;` | `z_now = p_now[30:12];` | 31bit 算术右移 12 位后本就只剩 19 位 |
| `px < H_VIS` / `py < PLOT_H` | 先做 `H_VIS12/PLOT_H12` 再比 | 消除 12bit vs 32bit 隐式扩展噪音 |
| 参数 `SCALE_NUM/SCALE_SHIFT` | **删除**（连同 2 处 vga_scope_top 例化和 TB 传参） | Q12 重构后已成死参数（UNUSEDPARAM） |

改完再用同一个 TB 跑：仍然 **PASS**（19×480 逐像素）→ 位等价成立。

### 21.3 门禁进展

| | 本轮前 | 本轮后 |
|---|---|---|
| BLOCK | bpf_ctrl（1 个） | **bpf_ctrl + trace_layer（2 个）** |
| ADVISORY | 38 条 | **30 条**（bpf50 1 / decim512 2 / eso 24 / scope_meas 3） |

### 21.4 `tb_scope_app` 为什么这轮没修

它不是端口改名能解决的：断言值全是旧的"右移档 2..7"，而 `scope_app` 现在输出
`vstep0/vstep1`（有符号 6bit，复位 0，每档 ±1，夹紧 ±30，每档 ×1.125）。
旧用例里"按到 7 就夹紧"这种语义已经不存在（要按满 30 档才夹）。

这属于**按新语义重写用例 + 新增夹紧测试**，不是机械替换，下一轮单独做，
避免"为了把 FAIL 变绿而改断言"。

