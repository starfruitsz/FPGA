# SparkRoad-V 数字示波器 —— 续作交接文档

> 用途：开新会话时先读这一份，即可接上进度。
> 最后更新：2026-10-31，固件 P11

---

## 1. 当前状态快照

| 项 | 值 |
|---|---|
| 板卡 | SparkRoad-V，安路 EG4S20BG256 |
| 当前固件 | **scope_eg4_p21.bit（2026-10-31 18:36 烧写；丝滑横轴缩放 pxz=(px*S)>>6、长按 30ms 连续、SW7 基线移动、贴边假线修复）** |
| 比特流路径 | FPGA_TD/scope_eg4_p18_Runs/best_result/scope_eg4_p18.bit（638,952 B） |
| 构筑脚本 | FPGA_TD/full_flow_p18.tcl（逐版递增 p1..p18） |
| 顶层 | sparkroad_scope_pll（PLL 25.2MHz / 60Hz / 内置信号源） |
| 资源 | LUT 3801/19600 (19.4%)、REG 1460、DSP 12/29、BRAM32K 2/16、PAD 76 |
| 时序 | setup 最差 +12.991 ns、0 setup / 0 hold 违规 |
| 仿真回归 | sim/run_all.ps1 → 18/18 PASS（2026-10-31 下午新增 3 个用例） |
| 仓库分支 | fix/review-p1-p11（**尚未推送**）；本轮 P12 改动（滚动/假线/长按重复）尚未提交 |
| 文档 | FPGA_scope_manual.pdf（手册 v1.4）、FPGA_project_analysis.pdf（141 页） |

---

## 2. 标准工作流

```powershell
# 1) 仿真回归（18 用例，约 150 秒）
powershell -ExecutionPolicy Bypass -File C:\Users\Administrator\Desktop\task\sim\run_all.ps1
#    期望最后一行: TOTAL: PASS=18  FAIL=0  SKIP=0

# 2) 新建构筑脚本（TD 不允许复用工程名，必须递增编号）
#    复制 full_flow_p11.tcl -> full_flow_p12.tcl，把里面所有 p11 替换成 p12
cd C:\Users\Administrator\Desktop\task\FPGA_TD
Get-Content .\full_flow_p12.tcl | & 'C:\Anlogic\TD_5.6.5_SP5_170.155\bin\td_commands_prompt.exe' -nogui

# 3) 烧写到 SRAM
"download -bit <bit路径> -cable 0" | & 'C:\Anlogic\TD_5.6.5_SP5_170.155\bin\td_commands_prompt.exe' -nogui
```

**注意**

- TD GUI 开着时命令行下载可能抢占 USB 设备，最好先关 GUI。
- 新增源文件要同时改两处：full_flow_pNN.tcl 的 add_files 和 sim/run_all.ps1 的源文件清单。
- 新增引脚要改 FPGA_TD/eg4/SparkRoad.adc。

---

## 3. 源码地图

```
FPGA/src/
  sparkroad_scope_pll.v      演示顶层（PLL 25.2MHz，60Hz，内置信号源）
  sparkroad_scope_demo.v     演示顶层（24MHz，无 PLL）
  sparkroad_scope_top.v      板级顶层（ADC 通路、数码管、LED、开关消抖）
  sparkroad_vga_test.v       屏幕自检诊断顶层（彩条/灰阶/棋盘）
  vga/
    vga_scope_top.v          示波器主体：采集+图层+菜单+双缓冲地址
    hal/vga_timing.v         VGA 时序产生
    hal/vram_sdp.v           简单双口 RAM（1024 深，现用 2 块拼乒乓）
    hal/font_rom.v           8x8 点阵字模（0-9 A-Z 部分 = : . - 空格）
    abs/grid_layer.v         网格与零轴
    abs/trace_layer.v        波形图层（运行时垂直缩放/平移）
    abs/text_layer.v         底部两行读数
    abs/compositor.v         图层合成（波形>文字>网格>背景）
    abs/menu_layer.v         菜单 OSD（双页，9/4 行）
    app/scope_app.v          寄存器与按键/开关状态机（核心可调点）
    app/scope_capture.v      采集状态机 + 乒乓缓冲切换
    app/scope_meas.v         Vpp/Vmax/Vmin/Vmean/周期/频率/占空比
    app/scope_ui.v           单键消抖 + 短按/长按事件
    app/scope_cmd.v          串口命令解析（T/R/A/L/E/S/M/C/P/H）
    app/func_gen.v           内置函数发生器（4 波形/8 频率/4 幅度/10 相位）
    app/sine_50hz.v          早期固定 50Hz 正弦（备用，已不参与主路径）
    app/sw_edge.v            拨动开关同步+消抖+边沿
```

**关键接口**

- vga_scope_top：输入 key_n[3:0]、sw_*、ch0_in/ch1_in/adc_valid；
  输出 gen_wave/gen_freq/gen_amp/gen_phase（给信号源）、dbg_status[7:0]（给 LED）。
- dbg_status 位定义：{done, trig, state[1:0], scroll, run, roll, menu}。
- scope_capture：输出 buf_wr/buf_disp 驱动乒乓缓冲。
  写地址 = {buf_wr, waddr}，读地址 = {buf_disp, 地址}（滚动模式用 buf_wr）。

---

## 4. 已完成功能

- 4 键短按：U/D 垂直缩放、L/R 水平缩放（不重采）
- 拨动开关（电平语义）：sw[5:0] 已引出（T4/R5/T5/T6/M6/P6）。**滚动开关 = SW5(P6)，拨上=非滚动、拨下=滚动**；
  SW3(T6) 实测无反应，已弃用。演示模式下**数码管显示采集完成次数**（判断采集是否在跑）
- 4 拨动开关（电平语义）：SW0 菜单 / **SW1 拨上=冻结、拨下=运行（v1.5 反转）** /
  SW2 菜单页 / SW3(或 SW5) 滚动；长按 500 ms 后每 500 ms 重复一档
- 双页菜单 OSD：P0 示波器 9 项、P1 信号源 4 项
- 内置信号源：正弦/方波/三角/锯齿，8 频率档，4 幅度档，10 相位档
- ADC 模式下信号源整体禁用（GEN_ENA 参数）
- 乒乓双缓冲：跟踪模式不再出现截断
- LED 调试指示 + 数码管显示信号源参数
- 串口 10 条命令
- **SW3 滚动模式真正生效**（2026-10-31 修复）：采集侧自由循环写（不触发、不翻乒乓、
  arm 不复位写指针），显示读正在写的那半、最右列最新；拨下回到「采满一屏再换」的乒乓换页。
  菜单 ROL 与串口 S 命令共用同一份状态（以前 SW3 只喂 LED，显示根本不认它）
- **越界不再画边缘假线**（2026-10-31 修复）：相邻两点都在可视区同一侧之外时整段不画，
  跨越边界时只画可见段
- **长按 U/D/L/R = 连续缩放**（2026-10-31 新增）：按下 1200 ms 后先走一档，之后每 300 ms
  再走一档；短按仍是一档。参数在 scope_app 例化处（LONG_MS / REPEAT_MS），想更迟钝就调大
- **画面自行缓慢滚动/跳变已修复**（2026-10-31）：根因是显示读地址用的是 `rd_base`，而它每次
  arm 都会被清 0；屏幕这时还在显示上一屏的缓冲，于是每采完一屏画面就整体平移一次。
  改为在 `done` 时锁存显示基准 `rd_base_d0/d1`（与 buf_disp 同一拍更新），显示只用锁存值。
  回归新增判据 A2（rd_base 清 0 而 rd_base_d0 保持），整机演示 12 帧仿真确认窗口内容恒定

---

## 5. 未完成项（详细实现说明）

> **已定稿设计**：AUTOSET / 智能缩放 / 自动量程 —— 见 `AUTOSET_plan.md`
> （2026-10-31 v0.2，决策已拍板：SW4 拨上=自动且持续自适应、双通道取最大、V/DIV 读数、无长按）。
> **尚未实现**，下一步 P1-a（16 档表重构）。
> 注：上面的「长按连续缩放」只作用于缩放，AUTOSET 仍然只由 SW4 触发，两者不冲突。

### P1 —— 建议先做

#### E1 配置 Flash 固化（命令行已探到底，走 GUI）

**2026-10-31 补充：命令行路径已全部试过，结论是必须用 GUI。**

**已探明的 create_flash_file 语义**（这一步已经能成功）：

```
create_flash_file -bit1 <比特流1> -bit2 <比特流2> \
                  -output <xxx.bin> -start_addr 0x100000 -rom_size 32M
```
- `-rom_size` 格式必须是 `4M` / `32M` 这种（`4194304`/`4096K` 都会报格式错误）
- **`-start_addr` 指的是第二个比特流的放置地址**，不是第一个！
  取 `0x0` 会与第一个重叠，报 `start addr cannot cover original file region`
- `-bit1` 和 `-bit2` 都必填（只给 bit1 会报 `Please specify the file to be added`）
- 生成的镜像结构：**32 字节头（cc 55 aa 33 …）+ 比特流从地址 0x20 开始**，
  第二个比特流在 `start_addr` 处
- 已生成可用镜像：`FPGA_TD/scope_eg4_p11_Runs/best_result/img2.bin`（1,680,001 字节）

**但写入这一步没有 CLI 出口**：

| 命令 | 结果 |
|---|---|
| `program_spi -input img2.bin -cable 0` | `PRG-9514 SpiEraseSector: bit string error (length=0)` |
| `program_spi -mode program/spi/... -input ...` | 同上，`-mode` 取值无效 |
| `program_spi -output ...` | 同上 |
| `download -mode flash -bit/bin ...` | **只做芯片校验，不写入** |
| `download -bin img2.bin -flashsize 32` | 实际执行 `bit_to_vec` + `program -mode svf -p`，
  这是**写 SRAM**，不是 Flash（会把 SRAM 写坏，需重新 download -bit 恢复）|

**→ 唯一可行路径：TD GUI 的 Programmer**

1. 打开 TD（工程 `FPGA_TD/scope_eg4_p11.al`）
2. 菜单 **Tools → Programmer**（注意：CLI 脚本无法可靠点击 Qt 菜单，需人工操作）
3. Cable = `USB-JTAG-Cable`
4. Access Mode / Operation = **`Program Flash`**（不要选 Program/SRAM）
5. File 选 `scope_eg4_p11.bit`（GUI 会自动做镜像转换）
6. Start Address 保持默认
7. 点 **Run**，等进度 100%
8. 断电重上电，若不接 JTAG 也能出画面即成功

**风险**：会覆盖板厂出厂 demo（文件不在仓库内）。失败可用 JTAG 重新 download 救回。
#### E3 按键行为回归用例
- 目标：现在仿真只测数据通路，按键/菜单/开关行为无自动化测试。
- 做法：写 sim/tb_key_menu.v，实例化 scope_app，直接驱动 key_n / sw_*，
  断言：短按 U 使 vsc0 递减、菜单项切换、gen_ena=0 时 P1 不可达、
  开关电平立即反映到 menu_on/run/roll。
- 接入：run_all.ps1 的 $cases 数组加一条，源文件加 scope_app.v + scope_ui.v。

### P2 —— 可用性提升

#### A1/A2/A3 触发可视化
- A1 触发电平虚线：新增 abs/trig_layer.v，输入 trig_level[9:0] 与 vsc0，
  在与波形相同坐标系下算出 y，在整行画虚线（隔像素点亮）。
  在 compositor 里插到网格之上、波形之下。
- A2 触发点标记：rd_base 对应触发点，屏幕列 = (rd_base - 显示起点)，
  在该列画竖线或顶部小三角。
- A3 状态文字：text_layer 模板固定，需要加一路可编程字符串输入，
  或基于 menu_layer 做 status_layer（ARMD/TRIG/STOP/AUTO，A-Z 字模够用）。

#### B6 外部 ADC 实测
- 接 AD7606，用 sparkroad_scope_top（DEMO_SINE=0）重新构筑。
- 重点验证量程/线性度、adc_locked、四通道数据是否串（见 B2）。

#### C3 剩余拨动开关扩展
- 已用 SW0~SW3；剩余 SW4~SW15 引脚：
  SW4=M6, SW5=P6, SW6=N6, SW7=P8, SW8=N8, SW9=R9, SW10=P9, SW11=N9,
  SW12=T14, SW13=R14, SW14=T15, SW15=R15。
- 建议分配：SW4~5 通道选择、SW6~7 触发模式、SW8~10 时基直选、SW11 ADC/信号源切换。
- 做法同现有：sw_edge 例化 + scope_app 增输入 + .adc 加引脚。

### P3 —— 功能增强

#### B1 AUTOSET 自动量程
- scope_meas 已输出 vpp/freq。根据 vpp 选 vsc（小则放大），根据 freq 选 tb_div
  （让屏幕上约 3 个周期）。
- 触发方式：菜单加一项 AUT，选中即执行一次。

#### B4 Vrms 有效值
- scope_meas 里加平方累加 sum_sq += (din-512)^2，一屏后开方。
- 开方可逐次逼近（10 步）或查表；资源充足（当前仅用 15%）。

#### B5 频率连续可调
- func_gen 现在是 8 档查表 inc。加一个微调寄存器，inc = base_inc + fine，
  菜单 P1 页加 FIN 项。

#### B7 预触发/保持时间界面化
- scope_app 已有 pre_trig/holdoff 与串口命令，只差菜单项。
- 菜单 P0 已满 9 项，建议加第三页 P2 触发设置。

### P4 —— 锦上添花

#### A4 光标测量
- 两套 cur_sel[1:0] + cur_pos[9:0]，按键移动；新图层画两条竖线 + 文字区显示 ΔT/ΔV。

#### A5 通道颜色可选
- vga_scope_top 的 COL_CH0/COL_CH1 是参数，改成寄存器 + 菜单项即可。

#### B2 双通道真并行采集（架构级）
- 现状是缺陷：adc_ad7606_top 把 4 个通道交错写进同一路径，CH0/CH1 实际混在一起。
- 做法：每通道独立缓冲（当前 2048 拼乒乓，可拆成每通道 1024 × 2 通道），
  或按 AD7606 的 4 通道顺序做解复用。
- 需改 adc_ad7606_top 的通道选择逻辑和 vga_scope_top 的采集例化。

#### D1 串口新命令
- 现有 10 条未覆盖：水平缩放、滚动、信号源参数。
- 仿照 scope_cmd 已有格式（8'h54: T 等）加字母，并在 scope_app 接对应 ext_*_we。

#### D2 设置导出
- 需先定协议（例如 ? 命令返回键值串），工作量中等。

---

## 6. 已知坑与教训

1. **显示器会骗人**：出现「上半正常、下半异常」这种空间分割，一定是显示器/同步问题。
   VGA 逐行扫描，同一列所有行读同一地址，FPGA 不可能画出这种图。
   排查顺序：换线 → 换显示器 → 检查 scaler 是否热漂移。
2. **TD 不允许复用工程名**：每次构筑必须新建 full_flow_NN.tcl 并改 create_project 名。
3. **替换构筑脚本要确认命中**：曾因 top_module 没替换成功，烧进去还是旧顶层。
4. **Verilog 乘法位宽**：a*b 结果宽度 = 两者最大值，12bit × 25 会溢出，要写 18'sd25。
5. **有符号/无符号混算**：10'd512 + 有符号数 会让整个表达式变无符号。
6. **隐式网线**：端口声明晚于例化会生成 1 位隐式网线，宽度悄悄变错。
7. **JTAG 驱动**：报 PRG-9505 时装 TD 自带 driver/al-link/win10/x64/anlocyusb.inf。
8. **开关消抖**：上电首次采样必须立即采用当前开关位置，否则要等 8ms。
9. **电平语义 vs 边沿语义**：拨动开关要「拨上即开、拨下即关」，不要用边沿 toggle。
10. **算法优先找开源**：算法类代码优先从开源社区（如 GitHub）取现成实现（注明仓库 + license）；
    GitHub 上找不到、或用户明确强调/指定实现时，才手搓。

---

## 7. 下次开工建议顺序

1. 先跑 sim/run_all.ps1 确认基线 15/15
2. 读第 5 节，挑一项
3. 改 RTL → 跑回归 → 新建 flow 脚本 → 综合 → 烧写 → 让用户验证
4. 每完成一项，更新本文件第 4/5 节 + 手册附录 C + 版本历史

---

## 8. 文档位置

| 文件 | 内容 | 面向 |
|---|---|---|
| FPGA_scope_manual.pdf | 产品使用手册 v1.4 | 使用者 |
| doc/manual.tex | 手册源码 | — |
| FPGA_project_analysis.pdf | 代码逐层解析（141 页） | 开发者 |
| PROJECT_STATE.md | 项目状态与待办 | 开发者 |
| NEXT_SESSION.md | 续作交接（本文档） | 下一个会话 |
---

## 9. 版本记录 p22-p28（2026-10-31 晚）

| 版本 | 内容 | 时序 |
|---|---|---|
| p22-p24 | 引脚约束反复踩坑：旧名残留、sw[8] 重复、空格不同的重复行，均未出比特流 | - |
| p25 | 并口 AD/DA + ADRC 首次综合 | FAIL 16 条 setup 违规，最差 -13.5 ns |
| p26 | ESO 流水化（乘法分两级、z1/z2/z3 拆两级） | OK +4.0 ns |
| p27 | 双通道自动量程（两路取较大峰值定档、各自居中） | OK +7.3 ns |
| p29 | 无触发超时换页（AUTO 触发）：ARMED 等满 1024 点自动 FILL，修非滚动下新旧数据混屏 | OK +9.2 ns |
| **p28** | 双信号源(gen0/gen1) + P1 菜单扩 8 项 + SW2 通道选择 | OK +6.9 ns |

**当前固件：p28**（FPGA_TD/scope_eg4_p28_Runs/best_result/scope_eg4_p28.bit），回归 20/20。

**引脚教训**：改 .adc 后先 grep 确认没有旧信号名残留、没有同一信号重复行（注意空格差异），否则 TD 只报 USR-8052/USR-8055。

## 10. 按键与开关（p28 现行）

### 4 键（U/D/L/R；长按>=500ms 进入连续重复，500ms/步）
| 场景 | 功能 |
|---|---|
| 菜单关闭、SW7 拨下 | U/D = 当前选中通道垂直放大/缩小；L/R = 水平缩小/放大 |
| 菜单关闭、SW7 拨上 | U/D = 上下移动零点基线(16px/步)；L/R 仍为水平缩放 |
| 菜单打开 | L/R = 移动光标；U/D = 调整当前项 |

### 拨动开关
| 开关 | 引脚 | 功能 |
|---|---|---|
| SW0 | T4 | 菜单显示/隐藏（拨上显示） |
| SW1 | R5 | 运行/冻结（拨上冻结、拨下运行） |
| SW2 | T5 | 菜单打开=翻页(P0/P1)；菜单关闭=通道选择（拨下CH0、拨上CH1） |
| SW3 | T6 | 已弃用（硬件无反应） |
| SW4 | M6 | 自动量程（拨上=持续自适应，两路共档、各自居中） |
| SW5 | P6 | 滚动（拨上非滚动、拨下滚动） |
| SW6 | N6 | 横轴缩放开上限（1x...256x） |
| SW7 | P8 | U/D 语义（拨上=移动基线） |
| SW8 | N8 | 通道来源（拨下=双信号源，拨上=AD/DA：CH0=ADC、CH1=ADRC u） |

### 菜单
- P0（9 项）：CH0 / CH1 / VS0 / VS1 / VP0 / VP1 / HSC / TB(0..F) / ROL
- P1（8 项）：CH0 的 WAV/FRE/ATT/PHA + CH1 的 WAV/FRE/ATT/PHA

## 11. p29 补充（2026-10-31 23:00）

**问题**：非滚动模式切到 AD/DA 模式后，屏幕出现函数发生器旧波形与 ADC 新数据混叠。

**根因**：外部无信号（直流/悬空）时触发永不发生，采集停在 ARMED，持续写入正在显示的半区；另一半区仍残留切换前数据。

**修法**：scope_capture 增加无触发超时——ARMED 连续 1024 个采样 tick 未触发则自动进入 FILL，rd_base 锁为当时 waddr（AUTO 触发行为）。触发正常时行为不变。

**验证**：tb_scope_capture / tb_scope_trigger 增加无触发换页断言，回归 20/20；p29 时序 +9.156 ns，0 违规。
