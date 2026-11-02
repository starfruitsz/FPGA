# HANDOFF — 交接文档（新会话从这里开始）

> 最后更新：**2026-11-02 20:45**（Asia/Shanghai）
> 当前固件：**scope_local36**（已烧 SRAM + 已固化 Flash，回读 ver36 vs img36 前 4096 B `diff=0`）
> 仓库：https://github.com/starfruitsz/FPGA.git（main，HEAD `6fb36a9`）
> 备份：`backup/fw/local36`，git tag `fw-local36`

---

## 0. 一分钟看懂现状

示波器 + ADRC 控制板已经能跑，**软件侧欠账已全部清零**：

| 维度 | 状态 |
|---|---|
| 仿真回归 | **24 PASS / 0 FAIL**（21 个用例 + 新增 3 个定点模块用例）|
| lint 门禁 | **6 个定点模块零告警**（原来 38 条告警全清）|
| 已修真 bug | **5 个**（见 §9，全部上板验证过或由 TB 复核）|
| 板上固件 | **scope_local36**（断电重上电也跑它）|
| 待办 | ADRC 参数整定（需硬件在环）、串口排查（用户暂缓）|

**下一步最可能做的事**：接上串口线看实际数据，或按现象调 ADRC 参数。

---

## 1. 新会话第一件事（30 秒自检）

```bash
export PATH="/d/Desktop/fpga/downloads/oss-cad-suite/bin:/d/Desktop/fpga/downloads/oss-cad-suite/lib:$PATH"
cd /d/Desktop/fpga
bash tools/lint.sh                                   # 期望：6 个模块 OK，LINT_RC=0
pwsh -File sim/run_all.ps1 -IverilogPath /d/Desktop/fpga/downloads/oss-cad-suite/bin | tail -1
                                                     # 期望：TOTAL: PASS=24 FAIL=0 SKIP=0
git log --oneline -3 && git status --short           # 期望：干净
```

> ⚠️ **PATH 必须同时含 `bin` 和 `lib`**。只加 bin 时 `vvp` 会段错误（exit 139），
> 连 hello-world 都崩 —— 这个坑曾让我误判成"Icarus 不支持某模块"，浪费了半天。

---

## 2. 硬件与环境

| 项 | 值 |
|---|---|
| 开发板 | 安路 SparkRoad-V（EG4S20BG256）|
| TD 工具链 | `C:\Anlogic\TD_5.6.5_SP5_170.155`（lic 到 2027-09-30）|
| TD CLI | `...\bin\td_commands_prompt.exe -nogui`（从 stdin 读 Tcl）|
| JTAG | Anlogic AL-Link Mini（VID_336C/PID_1002，驱动 anlocyusb）|
| Flash | GigaDevice ID `0xC8`，32 Mbit，**烧写必须 `-spd 1`** |
| 仿真 | `downloads/oss-cad-suite`（Icarus 14 + Verilator 5.053）|
| 串口 | 板载 USB2UART，**TX=F16 / RX=E16**，115200 8N1（与 JTAG 无关）|
| 工作目录 | `D:\Desktop\fpga` |

---

## 3. 构建 / 烧写 / 固化（复制即用）

### 3.1 综合
```bash
cd /d/Desktop/fpga/FPGA_TD
rm -rf scope_localNN.al scope_localNN_Runs          # 必须删，否则 create_project 报错
TD='/c/Anlogic/TD_5.6.5_SP5_170.155/bin/td_commands_prompt.exe'
"$TD" -nogui < make_scope_localNN.tcl 2>&1 | grep -E "ERROR|Generate bitstream|wait_run:" | tail -5
```
新增 .v **必须**同时加到 `make_scope_localNN.tcl` 和 `sim/run_all.ps1`。

### 3.2 烧 SRAM（25 s）
```bash
printf 'download -bit D:/Desktop/fpga/FPGA_TD/scope_localNN_Runs/best_result/scope_localNN.bit -mode jtag_burst -spd 4 -cable 0\nexit\n' | "$TD" -nogui
```

### 3.3 固化 Flash（269 s）
```bash
cat > /tmp/fl.tcl <<EOF
create_flash_file -bit1 BIT -bit2 BIT -output D:/Desktop/fpga/downloads/imgNN.bin -start_addr 0x100000 -rom_size 32M
download -bit BIT -mode program_spi -chip EG4S20BG256 -flashsize 32 -cable 0 -spd 1
exit
EOF
"$TD" -nogui < /tmp/fl.tcl
printf 'read_flash -start_addr 0 -length 4096 -output D:/Desktop/fpga/downloads/verNN.bin -cable 0\nexit\n' | "$TD" -nogui
cmp -n 4096 downloads/verNN.bin downloads/imgNN.bin    # 必须 diff=0
```
> 回读偶尔报 `PRG-9505 USB device open error`：是 program 刚结束 USB 被瞬时占用，
> **等 3 秒重试即可**，不代表写入失败（2026-11-02 实测）。

---

## 4. 当前固件的信号链与关键参数

```
AD 并口(3.15MHz) ─► ad_da_par ─► ad_val(10bit)
                                   ├─ SW13=上：decim512(6152Hz) ─► bpf_ctrl(48Hz带通) ─► ad_bpf
                                   │                                      │
                                   │                                      └─► ADRC 的 y = ad_bpf-512
                                   └─ SW13=下：直接 ad_val（ADRC 的 y = ad_val-512）
显示 CH0 = (SW13 ? ad_bpf : ad_val) ─► bpf50(SW15，仅 SW13=下时生效) ─► 显示 RAM ─► VGA
ADRC(eso.v) ─► u ─► DAC = clamp(u+512) ─► CH1
```

| 参数 | 值 | 位置 |
|---|---|---|
| 48Hz 带通系数 | `F_Q24 = 822350`（=2·sin(π·48/6152.34)）、`Q_Q16=27307` | `bpf_ctrl.v:34-35` |
| 抽取 | 512 点平均 → 6152.34 Hz | `decim512.v` |
| ADRC 观测器 | `B01/B02/B03 = 90/2700/27000`，`b0 = 5000` | `eso.v:91-94` |
| 控制律 | `u = (k*(c*z1+z2) + sgn + c*z2 - z3) >>> 15`，c=150/k=20，限幅 ±512 | `eso.v` 级 6 |
| 显示滤波 | 一阶稳态卡尔曼，等效截止 150Hz，K 按 {adc_mode,tb_idx} 查表 | `bpf50.v:37-69` |
| 垂直缩放 | Q12 连续增益 `vstep`（±30 步，每步 ×1.125，复位 0）| `scope_app.v` / `trace_layer.v` |
| 横轴缩放 | `hscale` 固定 102（自适应采样率），L/R 改 `tb_idx`(0..15) | `scope_app.v` |
| 自动量程 | SW4 拨上：按两路峰值选档 + 各自精细居中 | `vga_scope_top.v:251-304` |

---

## 5. 开关与按键（**SW13/SW15 语义已变更**）

| 开关 | 引脚 | 功能 |
|---|---|---|
| SW0 | T4 | 菜单开关 |
| SW1 | R5 | 运行/冻结（拨上=冻结）|
| SW2 | T5 | 菜单开=翻页；菜单关=通道选择（上=CH1）|
| SW4 | M6 | 自动量程（拨上=持续自适应，两路共同档、各自居中）|
| SW5 | P6 | 滚动（拨上=非滚动）|
| SW6 | N6 | **ADRC 闭环使能**（拨上=闭环）|
| SW7 | P8 | U/D 移动基线（优先级高于通道选择）|
| SW8 | N8 | 模式（上=AD/DA，下=内置双信号源）|
| **SW13** | R14 | **48Hz 算法带通总开关**：拨上=显示与 ADRC 的 y 都取带通输出；拨下=都取原始采样 |
| SW14 | T15 | 控制量 u 符号取反 |
| SW15 | R15 | 显示平滑滤波（卡尔曼），**仅 SW13 拨下时生效** |
| LED[13] | — | SW13 当前电平（低亮）|

按键：L/R = 横轴（自动跨时基档）；U/D = 纵向档（或 SW7 拨上时移基线）；长按 500ms 后每 30ms 一档。

---

## 6. 引脚（关键，改之前先查 CSV）

- `sw[0..15]` = T4,R5,T5,T6,M6,P6,N6,P8,N8,R9,P9,N9,T14,R14,T15,R15
- `ad0..ad9` = C9,C8,C5,E8,A14,A4,A12,A10,A6,A7；`adclk` = A8（带上拉）
- `da0..da9` = C7,C11,A11,B16,B15,C15,C16,A5,A9,A13；`daclk` = A3
- 权威表：`FPGA/src/adc/pins/adda_pins.csv` → `tools/gen_adda_pins.py` → `FPGA_TD/eg4/SparkRoad.adc`
- **不要凭猜测改引脚**（可能把 DA 输出接到 AD 上，有损坏风险）

---

## 7. 固件备份与回退

见 `BACKUP.md`。规矩：**只备份"固化过"的版本**。

| 版本 | tag | 关键改动 |
|---|---|---|
| local30 | `fw-local30` | SW13 开关 + 带通系数 822350 |
| local31 | `fw-local31` | `qb_64` 补 `$signed()`（修"开关信号"）|
| local32 | `fw-local32` | verilator 门禁 + 位宽清理 |
| local33 | `fw-local33` | trace_layer 清理 + TB 适配 |
| **local36** | `fw-local36` | **当前**：3 个 RTL bug + duty 溢出 + eso 位宽清理 |

回退：`git switch -c rollback/localNN fw-localNN` + 烧 `backup/fw/localNN/scope_localNN.bit`。

---

## 8. 验证资产（别绕过它们）

| 资产 | 用法 | 覆盖 |
|---|---|---|
| `sim/run_all.ps1` | 一键回归 24 例 | RTL 功能 |
| `tools/lint.sh` | verilator 门禁，BLOCK=6 模块 | 宽度/未用信号 |
| `tools/bpf_model.py` | 48Hz 带通**位精确**模型（返回 0=PASS）| 定点语义 |
| `tools/check_ports.py` | 模块/例化端口一致性（49 模块 / 76 例化）| 连线错误 |

新增模块的规矩：**先写 TB → 再改 RTL → 改完 TB 复验 → 最后进 BLOCK**。

---

## 9. 这段时间修掉的 5 个真 bug（教训都在这里）

| # | 现象 | 根因 | 教训 |
|---|---|---|---|
| 1 | 开 SW13 后 DAC 几乎不动 | 带通系数仍是 3.15MHz 时代的 1606，实际中心频率 0.094Hz | 改采样率必须同步改系数 |
| 2 | 开 SW13 后 y 变满幅方波 | `qb_64 = band * {{48'b0,Q}}` 少 `$signed()`，负半周被零扩展成 4.29e9 | **Verilog 有符号/无符号混算** |
| 3 | SW8 拨下（信号源）屏幕无波形 | `sw_run_eff = sw1 \| ~ad_ready`，而 ad_ready 在非 ADC 模式被清 0 → 永久冻结 | 上电保护要限定作用域 |
| 4 | 占空比读数恒为 0 | `high_cnt(9bit) * 8'd100` 按 9bit 算，12800 溢出 | **乘法结果宽度 = 操作数最大值** |
| 5 | 自动量程波形整体偏下 64 行 | `mid_d(13bit) * vg_auto(17bit)` 按 17bit 算，乘积溢出 | 同上（同类坑第 3 次）|

> **这个项目的头号系统性风险**：Verilog 里 `a*b` 的结果宽度取**操作数最大宽度**，
> 不是相加。写定点运算时先把中间量显式声明到足够宽（如 `wire signed [29:0] p = a*b;`）。

---

## 10. 串口 vs JTAG（2026-11-02 查证）

- **安路 TD 不支持 JTAG 转串口**：手册 369 页里 `ChipWatcher`(12 处)/`ChipProbe`(3)/`BramEditor`(5)
  都是在线调试工具，`UART`/虚拟串口 **0 处**；TD 的 `bin/` 里也没有串口桥工具。
- 板子有**独立 USB2UART**（F16/E16），工程已实现：`uart_tx` 连续上报 `{6'd0, ad_val}`
  （`TX_MODE=0`，约 5.7k 帧/秒）；`uart_rx` + `scope_cmd.v` 支持 `T/R/A/L/E/S/M/C/P/H` 命令。
- 实测本机 **没有任何 COM 口**（`SerialPort::GetPortNames()` 为空）→ 串口线没插/驱动没装。
- 用户已明确：**串口的事先放着**。

---

## 11. 交付包

`嵌入式FPGA代码/`（163 文件 / 1.5 MB）：`rtl/` + `sim/` + `build/` + `tools/` + README。
只含代码与必要工程文件，**包内实跑验证过**（回归 24/24、lint 全绿、端口检查 0 错误）。
注意：目录名含中文，TD 对非 ASCII 路径未做保证。

---

## 12. 未完成 / 下一步

1. **ADRC 参数整定**（需硬件在环）：闭环时 u 若贴 0/1023 或振荡，按 `ADRC_TUNING.md` 调 `k`/`b0`
   或 `B01/B02/B03`（三个必须同比例）。
2. **串口功能**：用户暂缓。后续可选：加 `?` 命令回读状态、或用 ChipWatcher 走 JTAG 观测。
3. **ADC 零点/幅度**：目前显示 0V 在屏幕底部（模块单极性），若要"上电居中"应改用
   `scope_meas.vmean` 做静态重定位，**不要恢复已删除的 `dc_removal`**。
4. 历史遗留：`rtl/fifo_top`、`rtl/gowin_pll` 是原厂参考工程，未参与当前构建。

---

## 13. 用户偏好（重要）

- **不要问"要不要继续"**：能做完的直接做完，只对会实质改变交付的事提问。
- 回答要给出**具体数值与文件行号**，用户会核对。
- 每次改完：**算资源 → 烧 SRAM → 告知**；用户说"固化"再写 Flash。
- 提交信息用中文，格式 `feat(scope): ...` / `fix(...): ...` / `docs(...): ...`。
- 改动后同步更新：`PROJECT_STATE.md`（详细记录）、本文件（入口摘要）、`BACKUP.md`（若固化）。
- **只备份固化过的版本**，不为每次综合留档。

---

## 14. 踩过的坑（合并版）

1. Flash 必须 `-spd 1`，4 分频报 `PRG-9516`。
2. 重建前必须删 `.al` 和 `_Runs`，否则 `create_project` 报错。
3. `vvp` 的 PATH 必须含 `oss-cad-suite/lib`，否则段错误。
4. TB 里 `@(posedge clk); en=0;` 与采样 always 同时间步，必须 `#1` 延后撤信号。
5. `dvalid` 与 `dout` 同拍非阻塞赋值，观测要晚一拍。
6. verilator 包装脚本缺 `Pod::Usage` 时，直接调 `verilator_bin.exe` 并设 `VERILATOR_ROOT`。
7. verilator **抓不到**有符号/无符号混用，那类问题只能靠 TB/位精确模型。
8. TD 偶尔在 `wait_run syn_1` 处自己段错误，重跑即可（与代码无关）。
9. 回读 Flash 偶发 `PRG-9505`，等 3 秒重试。
10. 板子拔掉后所有烧写都会失败（`PRG-9505`），别误判成代码问题 —— 先确认 USB 在不在。

---

## 15. 软核 / 处理器（2026-11-02 查证）

### 15.1 芯片本身：**没有硬核 CPU**

EG4S20BG256 属 Eagle 系列纯 FPGA，`arch/eagle_20.db` 里没有 ARM/MIPS 硬核。
安路的硬核 SoC 在别的系列：`ip/cm3_cpu/cm3_core.dat` 对应 `ph1_logic_SopcMcu`（PH1），
`ip/sf1_riscv/sf1_mcu_core.dat` 对应 SF1。

### 15.2 工具链自带软核：**Agile RISC-V 32 位，官方支持 EG4S20**

TD 手册 §3.12（p105–107）：

- 入口：**Tools → IP Generator → Create an IP core → Soft IP → Micro-Controller → Agile RISC-V**
- 配置界面标题即 **EG4_LOGIC_CPU**，Device 栏截图就是 **EG4S20BG256**
- 参数：RAM 4096×32bit（EMB9K / EMB32K 可选）、CPU 时钟 1Hz–1GHz（例 100 MHz）、
  **内置 UART（Baud Rate 110–2,000,000，例 115200）**、可指定 init 文件（.mif/.dat 预装程序）
- 生成物：`xxx_gate.v`（**加密门级网表，只支持 Verilog，不支持 VHDL**）
- 生成模块接口（手册 p107 截图）：

```
bus_addr[27:0] bus_wdata[31:0] bus_rdata[31:0]
bus_wen bus_ren bus_wstrb[3:0] bus_merr bus_rerr     // 28 位地址、32 位数据的主口
txd rxd                                              // 自带 UART
gpio[31:0] irq_id[3:0] irq_szd                       // GPIO 与中断
parameter Cpu_rate = 100_000_000; Bd_rate = 115200;
```

### 15.3 本工程现状：**没有用任何处理器**

采集/触发/菜单/串口命令/ADRC 全是 RTL 状态机。

### 15.4 资源账（要不要上的依据）

| 项 | 当前 | 加软核后（估算）|
|---|---|---|
| LUT | 7410 / 19600（37.8%）| +约 2000~5000（加密网表，实测才知道）|
| BRAM32K | 2 / 16 | 4096×32 = 128 Kbit ≈ 再加 4 块 |
| DSP | **29 / 29（已满）** | 软核要乘法的话只能走 LUT 实现 |

结论：能放下但余量不大，**建议新开工程做 RISC-V 验证，不要直接塞进示波器工程**。

### 15.5 对项目的价值与边界

- 价值：菜单/协议/参数整定可用 C 写；软核自带 115200 UART（仍走 F16/E16）。
- 边界：**它不是 JTAG 串口**——JTAG 在安路工具链里只做下载/固化和在线调试（ChipWatcher/ChipProbe）。
- 落地三步：① GUI 生成 `xxx_gate.v` → ② 顶层例化 + 总线接 BRAM/外设 + init 镜像 →
  ③ RISC-V GCC 编译 C（Anlogic 是否自带 SDK 未查证，通用 `riscv32-unknown-elf-gcc` 可用）。
- 另外：TD CLI 里有 `create_syn_ip` 命令，理论上可命令行生成 IP（命令名已确认，参数未验证）。
