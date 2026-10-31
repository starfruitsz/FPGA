$path = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'run_all.ps1'
$errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $path).Path, [ref]$null, [ref]$errs)
Write-Host ('error_count=' + @($errs).Count)
foreach ($e in $errs) {
  Write-Host ('LINE ' + $e.Extent.StartLineNumber + ':' + $e.Extent.StartColumnNumber + ' ' + $e.Message)
  Write-Host ('   TEXT: ' + $e.Extent.Text)
}
