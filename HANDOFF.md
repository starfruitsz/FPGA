# HANDOFF — 交接文档（新会话从这里开始）

> 生成时间：2026-11-01 23:30；最后更新：2026-11-02 00:20（Asia/Shanghai）
> 当前固件：**scope_local36**（3 个 RTL bug + duty 溢出 + eso 位宽清理；2026-11-03 20:37 已烧 SRAM + 固化 Flash，
> 回读 ver36 vs img36 前 4096 B `diff=0`；备份在 `backup/fw/local36`，tag `fw-local36`）
> 仓库：https://github.com/starfruitsz/FPGA.git（main 分支）

---

## 0. 一句话现状

示波器 + ADRC 控制板已经能跑：VGA 显示、双通道、触发、滚动、缩放、菜单、串口、
48 Hz 带通 + 512 点抽取 + ADRC 闭环、卡尔曼显示滤波、底部 X/Y/T/V 读数全部就位。
**当前最棘手的问题：用户反映 ADC 采集到的波形幅度很小甚至像 0/1 信号。**

---

## 1. 硬件与环境

| 项 | 值 |
|---|---|
| 开发板 | 安路 SparkRoad-V（EG4S20BG256）|
| TD 工具链 | `C:\\Anlogic\\TD_5.6.5_SP5_170.155`（需通行证，已装好，lic 到 2027-09-30）|
| TD CLI | `C:\\Anlogic\\TD_5.6.5_SP5_170.155\\bin\\td_commands_prompt.exe -nogui`（从 stdin 读 Tcl）|
| JTAG | Anlogic AL-Link Mini（VID_336C/PID_1002，驱动 anlocyusb 已装）|
| Flash | GigaDevice ID 0xC8，32 Mbit，**烧写必须 -spd 1** |
| 仿真 | `downloads\\oss-cad-suite\\`（Icarus Verilog 14），**必须先把它加进 PATH** |
| 工作目录 | `D:\\Desktop\\fpga` |

---

## 2. 构建 / 烧写 / 固化（复制即用）

### 2.1 构建
```bash
cd /d/Desktop/fpga/FPGA_TD
rm -rf scope_localNN.al scope_localNN_Runs          # 必须删，否则 create_project 报错
TD='/c/Anlogic/TD_5.6.5_SP5_170.155/bin/td_commands_prompt.exe'
cat make_scope_localNN.tcl | "$TD" -nogui 2>&1 | grep -E "ERROR|bitstream|wait_run:" | tail -6
```
构建脚本 `make_scope_localNN.tcl` 是从上一个版本复制后改工程名/加文件，**新增 .v 文件必须加到里面**。

### 2.2 烧 SRAM（快，25 s）
```bash
printf 'download -bit D:/Desktop/fpga/FPGA_TD/scope_localNN_Runs/best_result/scope_localNN.bit -mode jtag_burst -spd 4 -cable 0\nexit\n' | "$TD" -nogui
```

### 2.3 固化 Flash（慢，269 s）
```bash
cat > /tmp/fl.tcl <<EOF
create_flash_file -bit1 BIT -bit2 BIT -output D:/Desktop/fpga/downloads/imgNN.bin -start_addr 0x100000 -rom_size 32M
download -bit BIT -mode program_spi -chip EG4S20BG256 -flashsize 32 -cable 0 -spd 1
exit
EOF
"$TD" -nogui < /tmp/fl.tcl
# 校验
printf 'read_flash -start_addr 0 -length 4096 -output D:/Desktop/fpga/downloads/verNN.bin -cable 0\nexit\n' | "$TD" -nogui
cmp -n 4096 downloads/verNN.bin downloads/imgNN.bin   # 必须一致
```

### 2.4 仿真
```bash
export PATH="/d/Desktop/fpga/downloads/oss-cad-suite/bin:/d/Desktop/fpga/downloads/oss-cad-suite/lib:$PATH"
cd /d/Desktop/fpga && pwsh -File sim/run_all.ps1 -IverilogPath /d/Desktop/fpga/downloads/oss-cad-suite/bin
```
当前：**24 PASS / 0 FAIL**（用例总数 24；2026-11-03 新增 decim512/bpf50/scope_meas 三个 TB）。
本轮还修出 3 个 RTL 真 bug（自动量程居中乘法位宽、夹紧限位乘法位宽、
信号源模式被上电保护永久冻结），详见 PROJECT_STATE §22。
lint 门禁：`bash tools/lint.sh` —— **6 个定点模块全部零告警**（bpf_ctrl / trace_layer /
decim512 / bpf50 / scope_meas / eso），ADVISORY 已归零（2026-11-03）。
**注意：运行 vvp 时 PATH 必须同时含 `oss-cad-suite/bin` 和 `oss-cad-suite/lib`，
少了 lib 会段错误（exit 139），别误判成模拟器 bug。**

---

## 3. 当前信号链路

```
AD 模块 ──► ad_da_par（ADCLK=3.15MHz，下降沿锁存+两拍同步）──► ad_val(10bit)
                                                                    │
   ┌────────────────────────────────────────────────────────────────┤
   │ 显示通路（CH0 黄）                                              │ 控制通路
   ▼                                                                ▼
dc_removal（一次性校零）                                    decim512（512点平均→6152Hz）
   │                                                                │
   ▼                                                                ▼
bpf50 卡尔曼（SW15 开关，150Hz 低通）                       bpf_ctrl（48Hz带通 BW20）
   │                                                                │
   ▼                                                                ▼
显示 RAM ──► VGA（波形）                                    ADRC(eso.v)，3.15MHz 推进
                                                                    │
                                                                    ▼
                                                        DAC = clamp(u + 512)，CH1 蓝
```

---

## 4. 关键参数（改参数就改这些地方）

### 4.1 ADRC（`FPGA/src/eso.v`）
| 参数 | 当前值 | 位置 |
|---|---|---|
| `B01/B02/B03` | 90 / 2700 / 27000 | 第 91-93 行 |
| `b0` | 5000 | 第 94 行 |
| `c` / `k` | 150 / 20（在 top 里由 `c_date/k_date` 传入）| `sparkroad_scope_top.v` |
| 控制律 | `u = (k*(c*z1+z2) + sgn + c*z2 - z3) >>> 15`，输出限幅 ±512 | 级 6 |
| 等效增益 | Kp ≈ 0.0916，Kd ≈ 0.00519 | — |

> 曾试过经典形式 `u=(KP*(Y_REF-z1)-KD*z2)/B0`（KP=20/KD=0/B0=500），**用户要求回退了**。

### 4.2 算法级带通（`FPGA/src/vga/app/bpf_ctrl.v`）
| 参数 | 值 |
|---|---|
| 中心 / 带宽 | **48 Hz / 20 Hz（38~58）**，Q=2.4 |
| f | **822350（Q24）** = 2·sin(π·48/6152.34) |
| q | **27307（Q16）** = 1/Q |
| 状态 | Q16 / 32 bit（low、band）|
| 归一化 | 输出 ×q → 中心增益 = 1.000 |
| 群延迟 | 15.9 ms（调 ADRC 时要留相位裕度）|

### 4.3 抽取（`FPGA/src/vga/app/decim512.v`）
512 点累加平均，3.15 MHz → **6152.34 Hz**，同时抑制量化噪声约 30 dB。

### 4.4 显示滤波（`bpf50.v`，SW15）
一阶稳态卡尔曼 `x += K*(z-x)`，K 按 {adc_mode, tb_idx} 查表，等效截止 150 Hz。

### 4.5 直流消除（`dc_removal.v`）
alpha = **1/65536**，只在前 2^20 采样点跟踪后冻结（等效截止 7.6 Hz）。

---

## 5. 开关与按键

| 开关 | 功能 |
|---|---|
| SW0 | 菜单 |
| SW1 | 运行/冻结 |
| SW2 | 通道选择（P1 页翻页）|
| SW4 | 自动量程 |
| SW5 | 滚动模式 |
| SW6 | **ADRC 使能**（拨上=闭环）|
| SW7 | 基线移动 |
| SW8 | 模式（上=AD/DA，下=双信号源）|
| **SW13** | **48 Hz 算法带通总开关（R14，2026-11-02 新增）**：拨上=开，显示屏 CH0 与 ADRC 的 y 都取带通输出；拨下=关，两者都取原始采样 |
| SW14 | u 符号取反（T15）|
| SW15 | 显示卡尔曼滤波（R15），**仅在 SW13 拨下（带通关闭）时生效** |

按键：L/R = 采样率逐档（自适应，一屏满 1024 点）；U/D = 纵向缩放 ±15.0；菜单里 U/D 改参数。

底部读数：`X:+2 Y:-1 T=180U V=3.30V`（横轴档 / 纵向档 / 整屏时间 / 整屏电压跨度，ADC 0~1023 ↔ 0~3.3 V）。

---

## 6. 引脚（关键，别乱改）

- `sw[0..15]` = T4,R5,T5,T6,M6,P6,N6,P8,N8,R9,P9,N9,T14,R14,T15,R15
- `ad0..ad9` = C9,C8,C5,E8,A14,A4,A12,A10,A6,A7；`adclk` = A8
- `da0..da9` = C7,C11,A11,B16,B15,C15,C16,A5,A9,A13；`daclk` = A3
- 表在 `FPGA/src/adc/pins/adda_pins.csv`，用 `tools/gen_adda_pins.py` 重新生成 `.adc` 的标记块
- 约束文件 `FPGA_TD/eg4/SparkRoad.adc`

**⚠️ 用户接线表来自照片，若 ADC 只有 0/1 两档，优先怀疑这里错位。**

---

## 7. 踩过的坑（血泪，别重犯）

1. **Flash 必须 `-spd 1`**，4 分频会报 `PRG-9516 Erase spi unknown flash id`。
2. **重建前必须删 `.al` 和 `_Runs`**，否则 `create_project` 报 "Project should be opened first"。
3. **`.al` 里 `<Speed>` 不能为空**，用 `create_project ... -speed -5`。
4. **TD 可能在 `FPGA/src/work/` 生成临时文件**，已在 .gitignore 排除，别提交。
5. **定点乘法要注意 32 bit 溢出**：`high(32b) × f(24b)` 乘积超 2^31 会被截断，
   必须用 64 bit 中间量（`bpf_ctrl` 就是这么修好的）。
6. **JS 模型里不能用 `>>`** 处理大数（超 2^31 会截断），要用 `Math.floor(v/2**N)`。
7. **滤波器时间常数 vs 信号周期**：`dc_removal` 曾用 1/1024，在 3.15 MHz 下 τ=0.33 ms
   ≪ 48 Hz 的 20.8 ms，结果把信号本身当直流减掉 → "ADC 采样几乎没了"。
8. **仿真器需要 PATH**：`oss-cad-suite` 不设 PATH 会报 `0xC0000139`（符号找不到）。
9. **testbench 的 posedge 采样竞争**：观测寄存器值要 `#1` 延后。
10. **TB 分频器位宽**：`reg [3:0] div` 配 `div==0` 是 16 分频不是 8 分频，容易把激励频率搞错。

---

## 8. 已知问题 / 未完成

### 8.1 【最高优先】ADC 波形幅度/零点异常
现状（2026-11-02 00:20 更新）：
- **dc_removal 已彻底移除**（不是旁路，是删例化）：`vga_scope_top.v` 显示通路现在
  直连 `ch0_in/ch1_in` -> `bpf50` -> 显示 RAM。综合结果与 local28 **逐项相同**
  （LUT 7108 / REG 2256 / DSP 29 / BRAM32K 2，slack +7.765 ns），证明该模块本来
  就被综合器优化掉了 —— **屏幕偏下不是它造成的**。
- 因此屏幕纵向位置 = ADC 原始码值的直接映射：`y = 223 - (s-512)*vgain/4096`
  （`trace_layer.v:74`）。0 V 在屏幕哪里，取决于模块输出在 0 V 时给多少码。
- 板上已有现成诊断读数（不用改代码）：底部第 1 行 `AD=` 是 CH0 原始码（十六进制），
  每 2 秒翻页到第 2 页的 `HI= / LO= / AV=` 就是整屏 最大/最小/均值 码值。
  判断表：`HI≈03FF & LO≈0000` = 单极性模块（0 V 在底部属正常）；
  `HI≈01FF` = bit9 那根线没通；`LO` 明显 >0 = 模块有零点偏移。
- 用户已明确：**不要再加自适应偏置**。若要"上电居中"，只能走每帧均值 `vmean`
  静态重定位（无状态机），不要恢复 `dc_removal`。
- 待查：① `ad0..ad9` 引脚映射与实物是否一致；② AD 模块 D1~D9 连通性；
  ③ 上面三个读数（HI/LO/AV）到底是几

### 8.2 CH1（DAC）输出偏小
- 若滤波器工作正常（已用浮点+定点双模型证明中心增益 1.0），
  则 u 小是因为 ADRC 等效增益 0.0916 太小 → 把 `k` 从 20 调到 200（×10）试

### 8.3 仿真 4 项 FAIL（都是旧期望值）
| 用例 | 原因 |
|---|---|
| `vga_scope_top` / `_pix2` | 垂直档位从 `vs=2..7` 改成 Q12 连续增益后，TB 里写死的 y 坐标预期过期 |
| `tb_bpf_ctrl` | 需要跑 ~2 亿时钟才到稳态（6 万个采样点），仿真时长不可行；建议改成"抽取器+带通"级联短窗口验证 |

### 8.4 手册需要补的内容
- 48 Hz 带通 / 512 点抽取 / 一次性校零 这几节还没写进 `doc/manual.tex`
- `V=` 读数（整屏电压跨度）已写

---

## 9. 用户偏好（重要）

- 用户只让 **agent 构建 + 烧 SRAM + 固化 Flash**，自己不上手电烙铁/不手动改硬件
- 每次改完必须：**算资源 → 烧 SRAM → 告知 →（用户说"固化"再固 Flash）**
- 提交信息用中文，格式 `feat(scope): ...` / `fix(...): ...` / `docs(...): ...`
- 回答要给出**具体的数值与文件行号**，用户会核对
- 不要凭猜测改引脚（可能把 DA 输出接到 AD 输出上，有损坏风险）

---

## 10. 相关文档

| 文件 | 内容 |
|---|---|
| `PROJECT_STATE.md` | 项目总状态、每次改动记录 |
| `ADRC_TUNING.md` | ADRC 参数与调参说明 |
| `NEXT_SESSION.md` | 上一版交接笔记 |
| `doc/manual.tex` / `manual.pdf` | 19 页使用手册（v1.7）|
| `HANDOFF.md` | **本文件** |
