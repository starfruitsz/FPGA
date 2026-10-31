# 下载 Universal Ctags 到 tools/ctags（用于 VS Code F12 跨文件跳转）
$ErrorActionPreference = 'Stop'
$dir = Join-Path $PSScriptRoot 'ctags'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$zip = Join-Path $dir 'ctags.zip'
if(-not (Test-Path (Join-Path $dir 'ctags.exe'))){
  curl.exe -sS --ssl-no-revoke -L -o $zip 'https://github.com/universal-ctags/ctags-win32/releases/download/v6.1.0/ctags-v6.1.0-x64.zip'
  Expand-Archive -Path $zip -DestinationPath $dir -Force
}
& (Join-Path $dir 'ctags.exe') --version | Select-Object -First 1
Write-Host 'ctags ready: tools/ctags/ctags.exe'