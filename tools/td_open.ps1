# 用安路 TD GUI 打开工程
#   用法:  pwsh -File tools\td_open.ps1                      # 默认打开 scope_local4.al
#          pwsh -File tools\td_open.ps1 -Project scope_eg4_60.al
param(
    [string]$Project = "scope_local16.al",
    [string]$TdHome  = "C:\Anlogic\TD_5.6.5_SP5_170.155"
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$al   = Join-Path $repo ("FPGA_TD\" + $Project)
$exe  = Join-Path $TdHome "bin\td.exe"
if (-not (Test-Path $exe)) { throw "TD 未安装: $exe" }
if (-not (Test-Path $al))  { throw "工程不存在: $al" }
Write-Host ("TD   : " + $exe)
Write-Host ("工程 : " + $al)
Start-Process -FilePath $exe -ArgumentList ('"' + $al + '"') -WorkingDirectory (Join-Path $repo "FPGA_TD")
Write-Host "已启动 TD GUI。"
