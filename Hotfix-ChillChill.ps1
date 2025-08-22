# Hotfix-ChillChill.ps1
[CmdletBinding()]
param(
  [string]$RepoRoot = "C:\AiProject",
  [string]$ProvidersRel = "chatbot\agent-api\providers.py",
  [int]$MaxWaitSec = 45,
  [switch]$ForceRebuildIfDown  # add this to force docker compose --build if health doesn't recover
)

$ErrorActionPreference = 'Stop'
Push-Location $RepoRoot

function Test-Url {
  param([string]$Url,[int]$Timeout=5,[string]$Method="GET",[string]$Body=$null)
  try {
    if ($Method -eq "POST") {
      (Invoke-WebRequest -Uri $Url -Method POST -Body $Body -ContentType "application/json" -TimeoutSec $Timeout).StatusCode
    } else {
      (Invoke-WebRequest -Uri $Url -TimeoutSec $Timeout).StatusCode
    }
  } catch { return "FAIL" }
}

function Get-ApiContainerName {
  try {
    $json = docker compose ps --format json | ConvertFrom-Json
    return ($json | ? { $_.Name -match 'api' }).Name
  } catch { return $null }
}

function Print-ApiLogs {
  param([int]$Tail=200)
  $api = Get-ApiContainerName
  if ($api) {
    Write-Host "`n--- API LOGS (last $Tail lines) ---"
    docker logs --tail $Tail $api 2>&1
  } else {
    Write-Warning "API container name not found"
  }
}

function Restore-Providers-IfCrash {
  # Look for Python/uvicorn import/syntax/runtime errors, then auto-restore most recent .bak
  $api = Get-ApiContainerName
  if (-not $api) { return $false }
  $logs = docker logs --tail 400 $api 2>&1
  $crash = $false
  foreach ($p in @('Traceback','SyntaxError','ModuleNotFoundError','ImportError','Exception in ASGI application')) {
    if ($logs -match [regex]::Escape($p)) { $crash = $true; break }
  }
  if (-not $crash) { return $false }

  $providersPath = Join-Path $RepoRoot $ProvidersRel
  $bak = Get-ChildItem "$providersPath.*.bak" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($bak) {
    Write-Warning "Detected API crash indicators; restoring providers.py from backup: $($bak.FullName)"
    Copy-Item $bak.FullName $providersPath -Force
    docker compose restart api | Out-Null
    return $true
  } else {
    Write-Warning "Crash detected but no providers.py backup found"
    return $false
  }
}

Write-Host "=== HOTFIX START ==="

# 1) Quick health probe
$h1 = Test-Url "http://127.0.0.1:8000/health"
if ($h1 -ne 200) {
  Print-ApiLogs
  $restored = Restore-Providers-IfCrash
  if (-not $restored) {
    Write-Host "Waiting for API to become healthy..."
    $sw = [Diagnostics.Stopwatch]::StartNew()
    do {
      Start-Sleep 2
      $h1 = Test-Url "http://127.0.0.1:8000/health"
    } while ($h1 -ne 200 -and $sw.Elapsed.TotalSeconds -lt $MaxWaitSec)
  }
}

# 2) If still down, optionally rebuild
if ($h1 -ne 200 -and $ForceRebuildIfDown) {
  Write-Warning "API still not healthy; forcing rebuild..."
  docker compose up -d --build --remove-orphans
  $sw2 = [Diagnostics.Stopwatch]::StartNew()
  do {
    Start-Sleep 3
    $h1 = Test-Url "http://127.0.0.1:8000/health"
  } while ($h1 -ne 200 -and $sw2.Elapsed.TotalSeconds -lt ($MaxWaitSec + 30))
}

# 3) Final checks (API + simple /chat)
$chat = if ($h1 -eq 200) { Test-Url "http://127.0.0.1:8000/chat" -Method POST -Body '{"message":"ping"}' } else { "FAIL" }

Write-Host "===== FINAL SUMMARY ====="
Write-Host ("API /health    :: {0}" -f $h1)
Write-Host ("API /chat POST :: {0}" -f $chat)

if ($h1 -eq 200 -and $chat -eq 200) {
  Write-Host "TRAFFIC LIGHT: GREEN — API recovered."
} elseif ($h1 -eq 200) {
  Write-Host "TRAFFIC LIGHT: AMBER — Health OK; /chat not OK. See logs below."
  Print-ApiLogs
} else {
  Write-Host "TRAFFIC LIGHT: RED — API still down. Logs follow."
  Print-ApiLogs
}

Write-Host "=== HOTFIX END ==="
Pop-Location
