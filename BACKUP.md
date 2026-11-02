# 固件备份与回退

> 目的：任何一次新固件出问题时，能在 5 分钟内退回**已知可用**版本。
> 建立时间：2026-11-02

## 为什么需要单独备份

`FPGA_TD/*_Runs/` 在 `.gitignore` 里，**比特流不进仓库**；而源码 diff 又无法还原
"当时烧进板子的是哪一份 netlist"。所以要同时固定两样：**源码 tag** + **比特流实体**。

- 源码回退点：git tag `fw-localNN`
- 比特流实体：`backup/fw/localNN/`（受 git 管理，含 SHA256）

## 备份清单

| 版本 | git tag | 比特流 | SHA256（前 12 位） | 已固化 Flash |
|---|---|---|---|---|
| local33 | `fw-local33` | `backup/fw/local33/scope_local33.bit`（638,952 B） | `8842fbe1b720` | ✅ ver33 vs img33 diff=0 |

## 回退步骤

### A. 只退 SRAM（最快，约 25 s）

```bash
cd /d/Desktop/fpga
printf 'download -bit D:/Desktop/fpga/backup/fw/local33/scope_local33.bit -mode jtag_burst -spd 4 -cable 0\nexit\n' \
  | "/c/Anlogic/TD_5.6.5_SP5_170.155/bin/td_commands_prompt.exe" -nogui
```

### B. 退到 Flash（断电重启也生效，约 270 s）

```bash
cd /d/Desktop/fpga
printf 'download -bit D:/Desktop/fpga/backup/fw/local33/scope_local33.bit -mode program_spi -chip EG4S20BG256 -flashsize 32 -cable 0 -spd 1\nexit\n' \
  | "/c/Anlogic/TD_5.6.5_SP5_170.155/bin/td_commands_prompt.exe" -nogui
```

### C. 退源码

```bash
git switch -c rollback/local33 fw-local33    # 建分支回退（推荐）
# 或只读查看： git checkout fw-local33
```

## 新版本发布时必须做

1. 综合通过 → `cp` bit + tcl 到 `backup/fw/localNN/`，生成 `SHA256SUMS`
2. 提交后 `git tag -f fw-localNN <commit>`，并 `git push origin fw-localNN`
3. 在上表加一行（含 SHA256 前 12 位、是否已固化）

> 注：`downloads/_backup/` 是本地临时副本（被 .gitignore 忽略），**不作为正式备份**。
