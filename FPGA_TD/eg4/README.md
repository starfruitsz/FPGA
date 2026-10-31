# EG4S20BG256 工程说明

## 1. 器件库

EG4/Eagle 器件库只随 TD 5.6.x 提供，TD 6.0.3 只带 PH1/PH2。

- 已安装：`C:\Anlogic\TD_5.6.5_SP5_170.155`（TD 5.6.5 SP5）
- 器件库：`arch/eagle_20.db`（EG4S20），默认封装 `BGA256X`
- 安装脚本：`tools/install_td56.ps1`
- 安装包：`C:\Users\Administrator\Downloads\TD_5.6.5_SP5_170155_NL.msi`
  （SHA-256 `36a775f6...8acb`）

## 2. License（必须）

TD 5.6 综合需要 `license/Anlogic.lic`，缺失时 `optimize_rtl` 报：

    RUN-8418 ERROR: Cannot find license file .../license/Anlogic.lic

申请方式：安路官网账号 → 工具与资料下载 → License（或联系 FAE），
提供本机 MAC：**40-A5-EF-5E-1D-40**。拿到后放到：

    C:\Anlogic\TD_5.6.5_SP5_170.155\license\Anlogic.lic

## 3. 工程

- `FPGA_TD/scope_eg4.al`：35 个源文件 + `SparkRoad.adc` 约束，
  顶层 `sparkroad_scope_top`，器件 EG4S20BG256
- 重建脚本：`FPGA_TD/make_scope_eg4.tcl`
- 打开/分析：`td_commands_prompt.exe` 执行
  `open_project scope_eg4.al`（35 文件全通过）

## 4. 综合流程（License 就位后）

    launch_runs syn_1
    wait_run syn_1
    launch_runs phy_1
    wait_run phy_1
    write_bitstream

具体命令以 TD 5.6 的 `-help` 为准（`launch_runs run_name -step <string>`）。
