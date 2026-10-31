$ErrorActionPreference='Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$p = Join-Path $here 'run_all.ps1'
$lines = [System.IO.File]::ReadAllLines($p, [System.Text.Encoding]::UTF8)
$sb = New-Object System.Text.StringBuilder
$out = ''
for ($i = 1; $i -le $lines.Count; $i++) {
  $sb.AppendLine($lines[$i-1]) | Out-Null
  if ($i -in 22,24,48,53,58,63,65,67,68) {
    $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput($sb.ToString(), [ref]$null, [ref]$errs)
    $out += ('up-to-line ' + $i + ' errors=' + @($errs).Count)
    foreach ($e in $errs) { $out += (' | ' + $e.Extent.StartLineNumber + ':' + $e.Extent.StartColumnNumber + ' ' + $e.Message) }
    $out += [Environment]::NewLine
  }
}
[System.IO.File]::WriteAllText((Join-Path $here '_diag.txt'), $out, (New-Object System.Text.UTF8Encoding($false)))
