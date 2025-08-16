[CmdletBinding()]
param(
  [switch]$NoLogs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "==> Building containers (api + ui)..." -ForegroundColor Cyan
docker compose build

Write-Host "==> Starting services..." -ForegroundColor Cyan
docker compose up -d chatbot-api chatbot-ui

function Get-MappedPort {
  param([string]$Service, [int]$Port, [int]$DefaultPort)
  try {
    $out = docker compose port $Service $Port 2>$null
    if (-not $out) { return $DefaultPort }
    # Expected format: 0.0.0.0:12345 or [::]:12345
    return ($out.Split(":")[-1] | ForEach-Object { $_.Trim() })
  } catch {
    return $DefaultPort
  }
}

$apiPort = Get-MappedPort -Service "chatbot-api" -Port 8000 -DefaultPort 8000
$uiPort  = Get-MappedPort -Service "chatbot-ui"  -Port 3000 -DefaultPort 3000

$apiUrl = "http://localhost:$apiPort"
$uiUrl  = "http://localhost:$uiPort"

Write-Host "==> Waiting for API to be ready at $apiUrl ..." -ForegroundColor Cyan
$max = 60
for ($i=0; $i -lt $max; $i++) {
  try {
    Invoke-WebRequest -UseBasicParsing "$apiUrl/docs" -TimeoutSec 2 | Out-Null
    Write-Host "==> API is up." -ForegroundColor Green
    break
  } catch {
    try {
      Invoke-WebRequest -UseBasicParsing "$apiUrl/openapi.json" -TimeoutSec 2 | Out-Null
      Write-Host "==> API is up." -ForegroundColor Green
      break
    } catch {
      Start-Sleep -Seconds 1
    }
  }
  if ($i -eq ($max - 1)) {
    Write-Error "API did not become ready in time. Check logs with: docker compose logs -f chatbot-api"
    exit 1
  }
}

Write-Host "==> Opening UI at $uiUrl ..." -ForegroundColor Cyan
Start-Process $uiUrl | Out-Null

if (-not $NoLogs) {
  Write-Host "==> Tail logs (Ctrl+C to stop):" -ForegroundColor Cyan
  docker compose logs -f --since 1m chatbot-api chatbot-ui
}
