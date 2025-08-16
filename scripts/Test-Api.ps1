param(
  [string]$BaseUrl = "http://localhost:8000"
)
Write-Host ">>> GET /health"
try {
  $h = Invoke-RestMethod -Uri "$BaseUrl/health" -Method Get -TimeoutSec 10
  $h | ConvertTo-Json -Depth 5
} catch { Write-Error $_; exit 1 }

Write-Host "`n>>> GET /openapi.json (first 20 route keys)"
try {
  $open = Invoke-RestMethod -Uri "$BaseUrl/openapi.json" -Method Get -TimeoutSec 10
  $open.paths.PSObject.Properties.Name | Select-Object -First 20
} catch { Write-Error $_; exit 1 }

Write-Host "`n>>> POST /chat"
try {
  $body = @{ message = "hello" } | ConvertTo-Json
  $resp = Invoke-RestMethod -Uri "$BaseUrl/chat" -Method Post -ContentType "application/json" -Body $body -TimeoutSec 15
  $resp | ConvertTo-Json -Depth 5
} catch { Write-Error $_; exit 1 }

Write-Host "`nAll checks passed."
# --- Capsule auto-refresh (added by Operator) ---
try {
  powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\capsule\Update-Manifest.ps1" | Out-Null
  powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\capsule\Add-Changelog.ps1" -Message "Smoke OK; manifest refreshed" | Out-Null
} catch { Write-Verbose "Capsule refresh skipped: $($_.Exception.Message)" }
