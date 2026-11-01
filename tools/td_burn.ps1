# 把比特流通过 JTAG 烧入 FPGA（SRAM，掉电丢失；固化请自己在 TD GUI 里做）
#   用法:  pwsh -File tools\td_burn.ps1                 # 自动用最新 best_result 里的 .bit
#          pwsh -File tools\td_burn.ps1 -Bit D:\path\x.bit
#          pwsh -File tools\td_burn.ps1 -Spd 1          # 慢速（Flash 操作才需要 1）
param(
    [string]$Bit    = "",
    [string]$TdHome = "C:\Anlogic\TD_5.6.5_SP5_170.155",
    [int]   $Spd    = 4,
    [int]   $Cable  = 0
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$cli  = Join-Path $TdHome "bin\td_commands_prompt.exe"
if (-not (Test-Path $cli)) { throw "TD 未安装: $cli" }
if (-not $Bit) {
    $cand = Get-ChildItem (Join-Path $repo "FPGA_TD") -Recurse -Filter "*.bit" -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match 'best_result' } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $cand) { throw "找不到 bit：请先综合，或显式传 -Bit" }
    $Bit = $cand.FullName
}
if (-not (Test-Path $Bit)) { throw "bit 不存在: $Bit" }
Write-Host ("TD   : " + $cli)
Write-Host ("bit  : " + $Bit)
Write-Host ("cable: " + $Cable + "  spd: " + $Spd)
$bmp = $Bit -replace "\\", "/"
$tcl = Join-Path $env:TEMP ("td_burn_" + [guid]::NewGuid().ToString("N") + ".tcl")
Set-Content -Path $tcl -Value @(
    ("download -bit " + $bmp + " -mode jtag_burst -spd $Spd -cable $Cable"),
    "exit"
) -Encoding ascii
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName               = $cli
$psi.Arguments              = "-nogui"
$psi.WorkingDirectory       = Join-Path $repo "FPGA_TD"
$psi.UseShellExecute        = $false
$psi.RedirectStandardInput  = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.CreateNoWindow         = $true
$p = [System.Diagnostics.Process]::Start($psi)
$p.StandardInput.Write((Get-Content $tcl -Raw)); $p.StandardInput.Close()
$o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
if (-not $p.WaitForExit(300000)) { $p.Kill(); throw "烧写超时" }
Remove-Item $tcl -Force -ErrorAction SilentlyContinue
$out = $o.Result + $e.Result
$out -split "\r?\n" | Where-Object { $_ -match "PRG-|RUN-1003|ERROR|fail" } | ForEach-Object { $_.Trim() }
if ($out -match "Chip validation success") { Write-Host "烧入 SRAM 完成（掉电丢失）" -ForegroundColor Green }
else { Write-Host "烧入失败：PRG-9505=驱动问题，缺 PRG-2014=链路问题" -ForegroundColor Red; exit 1 }
