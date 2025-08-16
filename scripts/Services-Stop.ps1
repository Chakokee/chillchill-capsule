param([switch]$StopDocker=$false)
$ErrorActionPreference = "Stop"
$root = "C:\AiProject"
$logs = Join-Path $root "logs"
$ts   = Get-Date -Format "yyyyMMdd_HHmmss"
Start-Transcript -Path (Join-Path $logs "services_stop_$ts.log") -Append | Out-Null

function Stop-Chatbot {
  Write-Host "Stopping Chatbot..." -ForegroundColor Cyan
  Push-Location $root
  if (Test-Path ".\stop-all.ps1") {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File ".\stop-all.ps1"
  } else {
    docker compose down
  }
  Pop-Location
}

function Stop-N8N {
  $n8nPath = "C:\AiProject\n8n"   # update if needed
  $compose = Join-Path $n8nPath "docker-compose.yml"
  if (Test-Path $compose) {
    Write-Host "Stopping n8n (compose)..." -ForegroundColor Cyan
    Push-Location $n8nPath; docker compose down; Pop-Location
  } else {
    Get-Process -Name "n8n","n8n Desktop" -ErrorAction SilentlyContinue | `
      Stop-Process -Force -ErrorAction SilentlyContinue
  }
}

function Stop-DockerDesktop {
  Write-Host "Stopping Docker Desktop..." -ForegroundColor Yellow
  Stop-Process -Name "Docker Desktop","com.docker.backend" -Force -ErrorAction SilentlyContinue
}

Stop-Chatbot
Stop-N8N
if ($StopDocker) { Stop-DockerDesktop }

Write-Host "`nAll stop tasks attempted." -ForegroundColor Green
Stop-Transcript | Out-Null
