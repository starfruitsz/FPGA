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
| ad7606_convst | A7 | 排针 3 |
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
| License | license/Anlogic.lic（node-locked；本机 MAC 40-A5-EF-5E-1D-40） |
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
- 新功能只加在 fix/review-p1-p11 分支，main 保持原样以便回退。

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