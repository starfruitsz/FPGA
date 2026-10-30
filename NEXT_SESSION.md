# SparkRoad-V 数字示波器 —— 续作交接文档

> 用途：开新会话时先读这一份，即可接上进度。
> 最后更新：2026-10-31，固件 P11

---

## 1. 当前状态快照

| 项 | 值 |
|---|---|
| 板卡 | SparkRoad-V，安路 EG4S20BG256 |
| 当前固件 | scope_eg4_p11.bit（烧在 SRAM，断电丢失） |
| 比特流路径 | FPGA_TD/scope_eg4_p11_Runs/best_result/scope_eg4_p11.bit |
| 构筑脚本 | FPGA_TD/full_flow_p11.tcl（逐版递增 p1..p11） |
| 顶层 | sparkroad_scope_pll（PLL 25.2MHz / 60Hz / 内置信号源） |
| 资源 | LUT 3086/19600 (15.7%)、REG 1239、BRAM32K 2/16、IO 74 |
| 仿真回归 | sim/run_all.ps1 → 15/15 PASS |
| 仓库分支 | fix/review-p1-p11，最新提交 b6d7804（**尚未推送到 GitHub**） |
| 文档 | FPGA_scope_manual.pdf（手册 v1.4）、FPGA_project_analysis.pdf（141 页） |

---

## 2. 标准工作流

```powershell
# 1) 仿真回归（15 用例，约 100 秒）
powershell -ExecutionPolicy Bypass -File C:\Users\Administrator\Desktop\task\sim\run_all.ps1
#    期望最后一行: TOTAL: PASS=15  FAIL=0  SKIP=0

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
- 4 拨动开关（电平语义）：SW0 菜单 / SW1 运行 / SW2 菜单页 / SW3 滚动
- 双页菜单 OSD：P0 示波器 9 项、P1 信号源 4 项
- 内置信号源：正弦/方波/三角/锯齿，8 频率档，4 幅度档，10 相位档
- ADC 模式下信号源整体禁用（GEN_ENA 参数）
- 乒乓双缓冲：跟踪模式不再出现截断
- LED 调试指示 + 数码管显示信号源参数
- 串口 10 条命令

---

## 5. 未完成项（详细实现说明）

### P1 —— 建议先做

#### E1 配置 Flash 固化
- 目标：断电重启后自动加载，不用每次 JTAG 下载。
- 现状：program_spi -input <bit> -cable 0 报 PRG-9514 SpiEraseSector: bit string error。
- 已探明：需先用 create_flash_file 生成 Flash 镜像，参数 -bit1 -bit2 -output -start_addr -rom_size，但：
  - -output 必须是 .bit/.bin/.hex（用 .flash 报错）
  - 只给 -bit1 报 'Please specify the file to be added'
  - 给全 -bit1 -bit2 后报 'start addr cannot cover original file region'
  （rom_size 试过 4M/8M/16M/32M 均不行，取值语义未知）
- 建议：直接用 TD GUI 的 Tools → Programmer → Program Flash，选 scope_eg4_p11.bit。
- 注意：会覆盖板厂出厂 demo（文件不在仓库内）。

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