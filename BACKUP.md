# 固件备份与回退

> 规矩（2026-11-02 按用户要求简化）：**只备份"固化过"的版本**，综合出来没烧板子的不备份。

## 为什么需要单独备份

`FPGA_TD/*_Runs/` 在 `.gitignore` 里，**比特流不进仓库**；源码 diff 又无法还原
"当时烧进板子的是哪一份 netlist"。所以同时固定两样：

- 源码回退点：git tag `fw-localNN`
- 比特流实体：`backup/fw/localNN/`（受 git 管理，附 SHA256）

## 备份清单（按固化顺序）

| 版本 | git tag | 主要改动 | 比特流 SHA256（前 12 位） | Flash 校验 |
|---|---|---|---|---|
| local30 | `fw-local30` | SW13 带通总开关 + 带通系数 822350 | `357109671a97` | ver30 vs img30 diff=0 |
| local31 | `fw-local31` | `qb_64` 补 `$signed()`（修"开关信号"） | `85e1add35df8` | ver31 vs img31 diff=0 |
| local32 | `fw-local32` | verilator lint 门禁 + 位宽清理 | `74ad1621cce5` | ver32 vs img32 diff=0 |
| local33 | `fw-local33` | trace_layer 位宽清理 + TB 适配 | `8842fbe1b720` | ver33 vs img33 diff=0 |
| **local36** | `fw-local36` | **当前版本**：3 个 RTL bug（自动量程居中/夹紧位宽、ad_ready 误冻结）+ duty 溢出 + eso 位宽清理 | `ed4843243231` | ver36 vs img36 diff=0 |

> **记录更正史（保留，便于追溯）**：
> - local31 **确实固化过**（td_flash31.log 有 PRG-1001 + 回读 diff=0），早前写"仅 SRAM"是笔误。
> - **local34 / local35 从未烧进板子**：板子在 2026-11-02 16:12 被用户断开，两个 burn 日志
>   都是 `PRG-9505 USB device open error`，故不入备份清单。
> - 2026-11-02 20:37 板子接回，**local36 已烧 SRAM + 固化 Flash 并回读 diff=0**；
>   板上/Flash 当前固件 = **scope_local36**（回读时第一次 PRG-9505 属 USB 瞬时占用，重试即通过）。

## 回退步骤

### A. 退 SRAM（最快，约 25 s）

```bash
cd /d/Desktop/fpga
printf 'download -bit D:/Desktop/fpga/backup/fw/local33/scope_local33.bit -mode jtag_burst -spd 4 -cable 0\nexit\n' \
  | "/c/Anlogic/TD_5.6.5_SP5_170.155/bin/td_commands_prompt.exe" -nogui
```
把 `local33` 换成要回退的版本号即可。

### B. 退 Flash（断电重启也生效，约 270 s）

```bash
printf 'download -bit D:/Desktop/fpga/backup/fw/local33/scope_local33.bit -mode program_spi -chip EG4S20BG256 -flashsize 32 -cable 0 -spd 1\nexit\n' \
  | "/c/Anlogic/TD_5.6.5_SP5_170.155/bin/td_commands_prompt.exe" -nogui
```

### C. 退源码

```bash
git switch -c rollback/local33 fw-local33
```

## 每次固化后必须做（3 步）

```bash
v=34    # 新版本号
mkdir -p backup/fw/local$v
cp FPGA_TD/scope_local$v"_Runs"/best_result/scope_local$v.bit backup/fw/local$v/
cp FPGA_TD/make_scope_local$v.tcl backup/fw/local$v/
( cd backup/fw/local$v && sha256sum * > SHA256SUMS )
git tag -f fw-local$v <commit> && git push origin fw-local$v
```
然后在上表加一行。

> `downloads/_backup/` 只是本地临时副本（被 .gitignore 忽略），**不作为正式备份**。
