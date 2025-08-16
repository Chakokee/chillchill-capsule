param([switch]$OpenUI,[switch]$Warmup)
$ErrorActionPreference = "Stop"
$root = "C:\AiProject"
$logs = Join-Path $root "logs"
$ts   = Get-Date -Format "yyyyMMdd_HHmmss"
Start-Transcript -Path (Join-Path $logs "services_restart_$ts.log") -Append | Out-Null

& (Join-Path $root 'scripts\Services-Stop.ps1')
& (Join-Path $root 'scripts\Services-Start.ps1') -OpenUI:$OpenUI -Warmup:$Warmup

Write-Host "`nRestart completed." -ForegroundColor Green
Stop-Transcript | Out-Null
