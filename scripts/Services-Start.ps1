param([switch]$OpenUI,[switch]$Warmup)
$ErrorActionPreference = "Stop"
$root = "C:\AiProject"
$logs = Join-Path $root "logs"
$ts   = Get-Date -Format "yyyyMMdd_HHmmss"
Start-Transcript -Path (Join-Path $logs "services_start_$ts.log") -Append | Out-Null

function Wait-Docker {
  param([int]$TimeoutSec=180)
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $apiFallbackSet = $false
  do {
    try { docker info | Out-Null; return } catch {
      if ($_.Exception.Message -match "supports the requested API version" -and -not $apiFallbackSet) {
        $env:DOCKER_API_VERSION = "1.43"   # session-only
        $apiFallbackSet = $true
      }
      Start-Sleep 3
    }
  } while ((Get-Date) -lt $deadline)
  throw "Docker engine did not become ready within $TimeoutSec seconds."
}

function Start-DockerDesktop {
  if (-not (Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue)) {
    Write-Host "Starting Docker Desktop..." -ForegroundColor Cyan
    Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe" | Out-Null
  }
  Wait-Docker
}

function Start-Chatbot {
  Write-Host "Starting Chatbot..." -ForegroundColor Cyan
  Push-Location $root
  if (Test-Path ".\start-all.ps1") {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File ".\start-all.ps1" -OpenUI:$OpenUI -Warmup:$Warmup
  } else {
    docker compose up -d
  }
  Pop-Location
}

function Start-N8N {
  $n8nPath = "C:\AiProject\n8n"   # update if needed
  $compose = Join-Path $n8nPath "docker-compose.yml"
  if (Test-Path $compose) {
    Write-Host "Starting n8n (compose)..." -ForegroundColor Cyan
    Push-Location $n8nPath; docker compose up -d; Pop-Location
  } elseif (Test-Path "C:\Program Files\n8n\n8n.exe") {
    Write-Host "Starting n8n Desktop..." -ForegroundColor Cyan
    Start-Process "C:\Program Files\n8n\n8n.exe" | Out-Null
  } else {
    Write-Host "n8n not found (no compose or desktop). Skipping." -ForegroundColor Yellow
  }
}

Start-DockerDesktop
Start-Chatbot
Start-N8N

Write-Host "`nAll start tasks attempted." -ForegroundColor Green
Stop-Transcript | Out-Null
