# stop-chillchill.ps1
# Purpose: Gracefully stop the ChillChill stack, capture logs, and auto-clean containers + network.

[CmdletBinding()]
param(
  [switch]$CleanupVolumes = $false   # WARNING: removes volumes if set
)

$ErrorActionPreference = "Stop"
$sw = [System.Diagnostics.Stopwatch]::StartNew()

function Info($m) { Write-Host "[INFO ] $m" }
function Warn($m) { Write-Host "[WARN ] $m" -ForegroundColor Yellow }
function Done($m) { Write-Host "[DONE ] $m" -ForegroundColor Green }

# --- Derive project network name (docker-compose default = "<folder>_default") ---
$projectRoot = Split-Path -Parent $PSCommandPath
$projectName = (Split-Path $projectRoot -Leaf)
$networkName = ($projectName.ToLower() + "_default")

# 1) Capture logs before shutdown
$logsDir = Join-Path $PSScriptRoot "logs"
New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = Join-Path $logsDir "shutdown-$ts.log"
Info "Saving final logs to $logPath"
try {
  docker compose logs *> $logPath
} catch {
  Warn "Could not collect compose logs: $($_.Exception.Message)"
}

# 2) Compose down (primary path)
Info "Stopping stack via docker compose down..."
if ($CleanupVolumes) {
  Warn "CleanupVolumes is ON - removing volumes!"
  docker compose down -v
} else {
  docker compose down
}

# 3) Fallback clean: stop/remove any containers still on the project network
#    This protects against race conditions or stray containers.
function Get-ContainersOnNetwork($netName) {
  try {
    $json = docker network inspect $netName --format "{{ json .Containers }}" 2>$null
    if (-not $json) { return @() }
    $data = $null
    try { $data = $json | ConvertFrom-Json } catch { return @() }
    if (-not $data) { return @() }
    return $data.Keys
  } catch { return @() }
}

$remaining = Get-ContainersOnNetwork $networkName
if ($remaining.Count -gt 0) {
  Warn "Network '$networkName' still has attached containers: $($remaining -join ', ')"
  Info "Stopping remaining containers..."
  docker stop $remaining 2>$null | Out-Null
  Info "Removing remaining containers..."
  docker rm $remaining 2>$null | Out-Null
} else {
  Info "No containers remain on network '$networkName'."
}

# 4) Remove the project network if it exists
try {
  Info "Removing network '$networkName' (if present)..."
  docker network rm $networkName 2>$null | Out-Null
} catch {
  Warn "Could not remove network '$networkName': $($_.Exception.Message)"
}

$sw.Stop()
Done ("Shutdown completed in {0:N1}s" -f $sw.Elapsed.TotalSeconds)
