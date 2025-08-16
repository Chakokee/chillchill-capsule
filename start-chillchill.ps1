# start-chillchill.ps1
# Purpose: Fast, reliable startup for the local ChillChill stack with health-gated readiness.
[CmdletBinding()]
param(
  [switch]$PullLatest = $false,
  [switch]$NoWarmup = $false
)

$ErrorActionPreference = "Stop"
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Write-Info($msg) { Write-Host "[INFO ] $msg" }
function Write-Warn($msg) { Write-Host "[WARN ] $msg" -ForegroundColor Yellow }
function Write-Err ($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }

# 0) Load .env if present (key=value lines)
$envPath = Join-Path $PSScriptRoot ".env"
if (Test-Path $envPath) {
  Write-Info "Loading environment from .env"
  Get-Content $envPath | ForEach-Object {
    if ($_ -match '^\s*(#|$)') { return }
    $k, $v = $_.Split('=',2)
    if ($k) { [Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim()) }
  }
} else {
  Write-Warn ".env not found. Using current environment."
}

# 1) Ensure Docker is available
Write-Info "Checking Docker Desktop..."
try {
  docker version | Out-Null
} catch {
  Write-Err "Docker CLI not available or Docker Desktop not running."
  throw
}

# 2) Optional: pull latest images
if ($PullLatest) {
  Write-Info "Pulling images via docker compose..."
  docker compose pull
}

# 3) Start the stack (detached)
Write-Info "Starting ChillChill stack..."
docker compose up -d

# 4) Wait for services to be healthy (requires healthchecks in compose)
Write-Info "Waiting for service health..."
# Separate call keeps compatibility across Compose versions
docker compose up --wait | Out-Null

# 5) Show health summary
Write-Info "Service status:"
docker compose ps

# 6) Optional warmup calls (e.g., LLM registry, vector index)
$doWarmup = -not $NoWarmup -and ([Environment]::GetEnvironmentVariable("ENABLE_INDEX_WARMUP") -ne "false")
if ($doWarmup) {
  try {
    $apiPort = [Environment]::GetEnvironmentVariable("API_PORT"); if (-not $apiPort) { $apiPort = 8000 }
    Write-Info "Running warmup requests..."
    Invoke-WebRequest -Uri "http://localhost:$apiPort/models" -TimeoutSec 10 | Out-Null
    # Implement /warmup in your FastAPI app if desired:
    # e.g., loads models, primes vector cache, etc.
    try {
      Invoke-WebRequest -Uri "http://localhost:$apiPort/warmup" -TimeoutSec 30 | Out-Null
    } catch {
      Write-Warn "Warmup endpoint /warmup not available or failed (non-fatal): $($_.Exception.Message)"
    }
    Write-Info "Warmup completed."
  } catch {
    Write-Warn "Warmup encountered a non-fatal error: $($_.Exception.Message)"
  }
}

# 7) Background log tail to file for quick diagnostics
$logsDir = Join-Path $PSScriptRoot "logs"
New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = Join-Path $logsDir "startup-$ts.log"
Write-Info "Tailing logs to $logPath (separate window)."
Start-Process powershell -ArgumentList "-NoLogo -NoProfile -Command `"docker compose logs -f *> `'$logPath`'`""

$stopwatch.Stop()
Write-Host ("[DONE ] Startup ready in {0:N1}s" -f $stopwatch.Elapsed.TotalSeconds) -ForegroundColor Green
