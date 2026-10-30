# VS Code 代码阅读指南

本仓库是「高云 GW5A-25A 原始工程 + Anlogic EG4S20BG256 示波器移植」的混合工程，
源码 39 个 Verilog 文件、19 章 LaTeX 文档。本文说明如何用 VS Code 快速读懂。

## 1. 打开工程

    code C:\Users\Administrator\Desktop\task

或双击仓库根目录（含 .vscode/settings.json）。首次打开会推荐扩展：
Verilog-HDL/SystemVerilog、GitLens、Markdown、LaTeX Workshop、Python。

> 若「转到定义(F12)」不可用，安装 ctags（Universal Ctags）后重启 VS Code；
> 没有 ctags 时用「大纲(Outline)」和全局搜索也能覆盖大部分阅读需求。

## 2. 推荐阅读顺序（30 分钟版）

1. `PROJECT_STATE.md` —— 项目全貌、引脚、构建、限制；
2. `FPGA/src/sparkroad_scope_top.v` —— 顶层数据流（UART/ADC/VGA/数码管）；
3. `FPGA/src/vga/vga_scope_top.v` —— 像素流水线与图层装配；
4. `FPGA/src/vga/hal/vga_timing.v` —— 640x480 时序与 pix_ce；
5. `FPGA/src/vga/app/scope_capture.v` —— 触发状态机（IDLE/ARMED/FILL/DONE）；
6. `FPGA/src/adc/adc_ad7606_top.v` + `src/adc/hal/adc_ad7606_spi.v` —— AD7606 串行时序；
7. `FPGA/src/adc/abs/adc_norm.v` + `adc_cfg.v` —— 归一化与 CSR 寄存器；
8. 其余图层：`abs/grid_layer.v`、`trace_layer.v`、`text_layer.v`、`compositor.v`。

## 3. 文件职责速查

| 文件 | 职责 |
|---|---|
| `sparkroad_scope_top.v` | 板级顶层：24MHz、VGA 24bit、AD7606、串口、数码管 |
| `vga_scope_top.v` | 示波器集成：采集/触发/测量/图层 |
| `vga/hal/vga_timing.v` | VGA 时序（px/py/de/hs/vs/pix_ce） |
| `vga/hal/vram_sdp.v` | 1024x10 双口 BSRAM |
| `vga/hal/font_rom.v` | 8x8 字模 |
| `vga/abs/trace_layer.v` | 波形连线（无帧缓存的核心技巧） |
| `vga/abs/text_layer.v` | 两页文本模板 + 5 个数字域 |
| `vga/app/scope_capture.v` | 触发状态机、预触发、保持时间 |
| `vga/app/scope_app.v` | 时基/触发/滚动寄存器、按键、翻页 |
| `vga/app/scope_meas.v` | Vpp/max/min/mean/period/freq/duty |
| `vga/app/scope_cmd.v` | 示波器 ASCII 命令 |
| `adc/adc_ad7606_top.v` | AD7606 采集通道（驱动+CSR+归一化） |
| `adc/hal/adc_ad7606_spi.v` | CONVST/BUSY/CS/SCLK/DOUTA 时序 |
| `adc/abs/adc_norm.v` | 对齐/位宽/补码转换 |
| `adc/abs/adc_cfg.v` | CSR 0x00–0x28 |
| `adc/app/adc_cmd.v` | ADC ASCII 命令（R/O/S/K/N） |

## 3.5 可视化层次树与跨文件跳转

- **层次树**：打开 `HIERARCHY.md`，按 `Ctrl+Shift+V` 预览，可看到 Mermaid 模块图 + ASCII 树；
  修改代码后运行任务 **7. 生成模块层次树** 重新生成；
- **跨文件跳转（F12）**：`tools/ctags/ctags.exe` 已安装，根目录 `tags` 已生成，
  `.vscode/settings.json` 已指向它；把光标放在模块名/实例上按 `F12`（或 `Alt+F12` 预览定义）；
  若失效：运行任务 **6. 生成 ctags 索引**，再执行 `Ctrl+Shift+P → Reload Window`；
- **TerosHDL**：已安装，命令面板搜 `TerosHDL` 可打开 Hierarchy / Dependencies 视图；
- `Ctrl+T` 工作区符号、`Ctrl+Shift+O` 当前文件大纲。

## 4. VS Code 使用技巧

- `Ctrl+P`：按文件名跳转（如 `scope_capture.v`）；
- `Ctrl+Shift+O`：当前文件大纲（module/always/assign 列表）；
- `Ctrl+Shift+F`：全局搜索，常用关键词：
  - `[块`：本工程注释的块编号（如 `[块 4b]`）；
  - `怎么读这个文件`：VGA 各模块开头的导读；
  - `[修复`：历史缺陷修复点；
  - `TODO`：未完成项；
  - `localparam` / `parameter`：可配置项；
- `Alt+Click` 多光标、`Ctrl+/` 注释、`F2` 重命名（谨慎用于 RTL）；
- 左侧 Source Control（GitLens）看 `fix/review-p1-p11` 的提交历史；
- 阅读 LaTeX：打开 `doc/main.tex`，LaTeX Workshop 可编译/预览 PDF。

## 5. 代码组织约定

- 分层：`hal/`（器件/时序）→ `abs/`（归一化/图形）→ `app/`（业务）→ 顶层；
- 每个模块头有中文导读；`[块 N]` 标记语句块；
- 只加 `//` 行注释，注释改动不改代码 token；
- 位宽约定：内部颜色 RGB444，VGA 输出复制成 RGB888；ADC 归一化后右对齐 10bit。

## 6. 想改代码时

| 目标 | 改哪里 | 之后做什么 |
|---|---|---|
| 换引脚 | `FPGA/src/adc/pins/board_pins.csv` | 跑 `python tools/gen_adc_pins.py`，重综合 |
| 换分辨率/时序 | `vga_scope_top` 参数 | 重综合 |
| 改量程/过采样/SCLK | `adc_cmd`（R/O/S/K/N）或 CSR | 无需重综合 |
| 加 ADC 型号 | `src/adc/hal/` 新驱动 + `adc_top.v` 分支 | 加引脚、重生成约束 |
| 改文档 | `doc/ch*.tex` | `cd doc && xelatex main.tex` 两次 |

## 7. 已排除的目录（避免干扰）

`_remote/`（仓库副本）、`*_Runs/`（TD 运行产物）、`impl/`、`doc/rendered/`、
`_sparkroad*/`、`_ad7606/`、`*.pdf`、`*.log`。需要看构建结果时用 `Ctrl+P` 直接输路径。

## 8. 一键任务

`Ctrl+Shift+B` 或 Terminal → Run Task，可选：

1. 生成引脚约束；
2. 端口连接检查；
3. TD 5.6.5 打开工程；
4. 重跑综合+布局布线；
5. 编译 LaTeX 文档。