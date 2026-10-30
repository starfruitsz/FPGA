# TD 5.6.5 silent install + Eagle (EG4) device check
param(
    [string]$Msi = "C:\Users\Administrator\Downloads\TD_5.6.5_SP5_170155_NL.msi"
)
$ErrorActionPreference = "Stop"
if(-not (Test-Path $Msi)){ throw "MSI not found: $Msi" }
Write-Host ("MSI: {0} ({1:N0} bytes)" -f $Msi, (Get-Item $Msi).Length)

$p = Start-Process -FilePath "msiexec.exe" -ArgumentList @("/i", $Msi, "/qn", "/norestart") -Wait -PassThru
Write-Host ("msiexec exit: {0}" -f $p.ExitCode)

$loc = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match "TD_5.6.5" } | Select-Object -First 1).InstallLocation
if(-not $loc){ throw "TD 5.6.5 install location not found in registry" }
Write-Host "InstallLocation: $loc"

$arch = Join-Path $loc "arch"
$eagle = Get-ChildItem $arch -Filter "eagle_*.db" -ErrorAction SilentlyContinue
if($eagle){ Write-Host ("Eagle DB: " + ($eagle.Name -join ", ")) } else { Write-Warning "No eagle_*.db" }

$lic = Join-Path $loc "license\Anlogic.lic"
if(Test-Path $lic){ Write-Host "License found: $lic" }
else { Write-Warning "License missing: $lic (request from Anlogic with MAC 40-A5-EF-5E-1D-40)" }

$cli = Join-Path $loc "bin\td_commands_prompt.exe"
Write-Host "TD CLI: $cli"