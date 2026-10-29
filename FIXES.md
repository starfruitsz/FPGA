# 缺陷修复分支：fix/review-p1-p11

本分支从 `main` 切出，用于按第 14 章《设计审查》的建议修复风险与缺陷。
**main 保持不变**，随时可以切回；本分支的所有改动都集中在下面列出的文件里。

仓库：<https://github.com/starfruitsz/FPGA>

---

## 1. 如何回退

```bash
git fetch origin
git checkout main                 # 直接回到未修改的版本
# 或者只撤销某次修复：
git revert <commit>
```

---

## 2. 修复清单

| 编号 | 文件 | 改动 | 行为影响 | 验证 |
|---|---|---|---|---|
| **P1** | `src/eso.v` | 参数锁存由 `if/else-if` 优先级改为两个独立 `if` | 收到过 A 帧后 k 参数仍能更新（原 bug 已消除） | TD 分析通过 |
| **P2** | `src/eso.v` | 符号项 `4'b1111`（补零=+15）改为 `5'sd1 / -5'sd1` | 控制律的符号补偿由 +15 变为真正的 ±1，**闭环动态会变化** | TD 分析通过 |
| **P3** | — | 复核后撤销：32bit + 22bit 有符号相加只需 33bit，`she` 宽度足够 | 无（仅更正注释与文档说法） | 手工位宽推导 |
| **P4** | `src/bcd.v`、`src/seg.v` | BCD 扩到 4 位并新增 `thou`；seg 增加“千位优先”显示分支 | 显示 1000~1023 不再回绕（4 位显示时最左位是数字，不显示负号） | TD 分析通过 |
| **P5** | `src/adda.v`、`src/vga/adda_scope_top.v` | 新增 **`UART_MODE` 开关**（0=连续发送 / 1=按标志位定时）+ **`REPORT_MS` 可配置上报周期**；`uart_tx.pi_flag` 接 `tx_req` | 默认 26ms 一帧（约 38 帧/s）；改 `REPORT_MS` 即可调速率，`UART_MODE=0` 恢复连续发送 | TD 分析通过 |
| **P6** | `src/seg.v` | `sel <= ~sel_reg;` 改为 `sel <= ~sel_reg[3:0];` | 无功能变化，去掉隐式截断 | TD 分析通过 |
| **P7** | `src/seg.v` | `point[cnt_sel]` 改为 `(cnt_sel<=3) ? point[cnt_sel[1:0]] : 0` | 消除越界索引（仿真不再读 X） | TD 分析通过 |
| **P8** | `src/divider.v` | 注释“500 分频”更正为 50000 分频 | 仅注释 | — |
| **P9** | — | **已回撤**（见第 6 节）：保留 `ad_clk`/`da_clk` 输入端口 | 无（端口未使用，综合会自动裁剪，仅保留接口兼容） | TD 分析 + 端口检查 |
| **P10** | `src/adda.v` | 删除 `initial` 初值，改为在块 5 复位分支里清 `po_flag2` | 可综合性更好，行为不变 | TD 分析通过 |
| **P11** | `src/project_2025_11_07.cst` | 补上数码管 `sel[3:0]`/`seg[7:0]` 共 12 个引脚约束（取自 PnR 报告） | 重新布局后数码管引脚不再漂移 | 约束共 50 个端口，端口/引脚均唯一 |
| **P12** | `project_2025_11_07.gprj` | 从工程文件列表移除未例化的 `gowin_pll.v`/`fifo_top.v` | 工程与网表一致；文件仍保留在磁盘 | 文件数 28 → 26 |

> **上板前必读**：P2 会改变闭环控制律（符号项由 +15 变成 -1），P4 会改变数码管显示格式，
> P5 会改变串口上报速率。换到本分支后建议先在 `TEST_MODE=1` 下确认屏幕，
> 再重新整定 `c`/`k`。

---

## 3. 改动文件一览

```
src/adda.v                  端口/初值/pi_flag（P5 P10；P9 已回撤）
src/eso.v                   参数优先级/符号项（P1 P2，P3 注释更正）
src/bcd.v                   4 位 BCD（P4）
src/seg.v                   4 位显示 + 越界保护（P4 P6 P7）
src/divider.v               注释更正（P8）
src/vga/adda_scope_top.v    P9 已回撤（保留 ad_clk/da_clk 端口与连线）
src/project_2025_11_07.cst  数码管引脚约束（P11）
project_2025_11_07.gprj     移除未例化 IP（P12）
```

---

## 4. 验证记录

| 项 | 结果 |
|---|---|
| TD 6.0.3 前端分析 | ✅ 27 个源文件通过 |
| 端口连接静态检查 | ✅ 25 个模块、31 处例化、0 个未定义端口 |
| 约束文件检查 | ✅ 50 个端口 / 50 个唯一引脚，无重复 |
| 逻辑综合 / 时序 | ⏳ 需在 Gowin EDA 中运行（本机未安装） |
| 上板 | ⏳ 未验证 |

## 5. 未处理的建议（保留原设计）

- 数码管在 1000 以上不再显示负号（4 位已占满），如需符号+4 位需要 5 位数码管或改显示内容；
- 触发对齐仍有 ±1 采样误差，串口 ASCII 命令与二进制帧共用线路（VGA 部分，风险低）；
- SDRAM/BSRAM 相关 IP 未使用，已从工程移除但文件保留。

---

## 6. 回撤记录

| 日期 | 编号 | 内容 | 原因 |
|---|---|---|---|
| 2026-10-29 | P9 | 恢复 `adda.v` 的 `ad_clk`/`da_clk` 输入端口，以及 `adda_scope_top.v` 的对应端口与连线 | 按需求保留原有接口，避免下游引用这两个信号时出错；端口未使用，综合时会自动裁剪，不增加资源 |

回撤后状态：

- `adda` 端口：`sys_clk / sys_rst_n / ad_date[9:0] / key_in / ad_clk / da_clk / rx`（与原始设计一致）；
- `adda_scope_top` 对应恢复 `ad_clk / da_clk`，并在 `u_adda` 例化处接回；
- TD 前端分析 27 个文件通过，端口连接检查 0 错误。

### P5 配置方式

```verilog
// adda_scope_top.v（顶层，推荐在这里改）
module adda_scope_top #(
    parameter integer UART_MODE = 1,   // 0=连续发送  1=按标志位定时发送
    parameter integer REPORT_MS = 26   // 标志位模式下的上报周期(ms)
)(
...
    adda #(.UART_MODE(UART_MODE), .REPORT_MS(REPORT_MS)) u_adda (...);
```

- **连续模式**（`UART_MODE=0`）：`pi_flag` 恒为 1，发送器连续发帧（原行为，占满串口带宽）；
- **标志位模式**（`UART_MODE=1`，默认）：计数器每 `REPORT_MS` 毫秒产生一个单周期脉冲，触发一帧；
- 周期由 `CNT_MAX = (CLK_FREQ/1000)*REPORT_MS - 1` 自动推导，例如：
  `50MHz` 下 `26ms → 1,299,999`、`10ms → 499,999`、`100ms → 4,999,999`；
- 计数器已加宽到 32bit，最长可配置到约 85 秒；
- 未选中的分支（连续模式下的定时器 / 标志位模式下的常量 1）会被综合常量折叠。

一键切换示例（在 `adda_scope_top.v` 里改参数即可，不用动内部逻辑）：

| 用途 | 参数 |
|---|---|
| 默认：每 26ms 一帧 | `UART_MODE=1, REPORT_MS=26` |
| 高速上报：每 5ms 一帧 | `UART_MODE=1, REPORT_MS=5` |
| 低速上报：每 200ms 一帧 | `UART_MODE=1, REPORT_MS=200` |
| 连续发送（旧行为） | `UART_MODE=0` |


---

## 7. v2 应用层增强（P13）

在保持 HAL/ABS 封装不变的前提下，只改 APP 与顶层，加入：

### 7.1 触发状态机

```
IDLE --arm--> ARMED --触发--> FILL --采满一屏--> DONE
                 ^                                |
                 |------ arm (normal 自动 / single 手动)
```

- `trig_mode`：0=auto（自由滚动，仅用触发对齐）、1=normal（采满一屏停住，自动重触发）、2=single（停住，等按键/串口 arm）
- `pre_trig`：触发时锁存 `rd_base = 写指针 - pre_trig`，显示从 `rd_base` 开始，能看到触发点之前的波形
- `holdoff`：触发后保持 N 个采样点内的新触发被忽略（消抖/防重触发）
- `trig_src`：触发源可选 CH0/CH1，与显示通道解耦

### 7.2 扩展测量（scope_meas v2）

| 输出 | 含义 | 实现 |
|---|---|---|
| vpp | 峰峰值 | max-min（每帧） |
| vmax / vmin | 本帧最大/最小 | 比较器 |
| vmean | 均值 | 前 256 点累加后右移 8 位（无除法器） |
| period | 周期 | 相邻上升沿之间的采样点数 |
| freq | 频率 | 帧内上升沿次数 × 60Hz |
| duty | 占空比 | 前 256 点中高于阈值的比例 |

RMS 需要开方，本版未实现（可后续用 CORDIC/查表）。

### 7.3 双页文本

`page` 每 2 秒翻转：

- page=0：`AD / U / TB / VP / FR`
- page=1：`HI / LO / AV / PE / DU`（最大/最小/均值/周期/占空比）

### 7.4 串口命令（新增）

| 命令 | 含义 | 范围 |
|---|---|---|
| `M<hex>` | 触发模式 | 0=auto 1=normal 2=single |
| `C<hex>` | 触发源 | 0=CH0 1=CH1 |
| `P<hex>` | 预触发点数 | 0~3FF |
| `H<hex>` | 保持时间 | 0~FFFF 采样点 |

原有 T/R/A/L/E/S 不变。

### 7.5 上位机 MVP

`tools/scope_host.py`：pyserial 读取 2 字节帧（先低后高），matplotlib 实时滚动显示，可存 CSV。

### 7.6 许可

- 仓库新增 MIT `LICENSE`；
- `THIRD_PARTY.md` 记录参考项目（AtomGit/MIT、UMD 教程、sigrok/ngscopeclient/ScopeFun 仅参考设计，未复制 GPL 代码）。

### 7.7 验证与限制

- TD 前端分析：27 个文件通过；端口检查：25 模块 / 31 例化 / 0 错误；
- **未做仿真、未上板**：状态机与预触发偏移的实际波形需要实测；
- ETS（等效采样）未实现，需要 PLL 相位或延时链；
- 频率/周期统计基于采样节拍，低采样率下分辨率有限。
