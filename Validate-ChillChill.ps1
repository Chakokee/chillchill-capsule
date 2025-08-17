# C:\AiProject\Validate-ChillChill.ps1
param()

$ErrorActionPreference = 'Stop'
Set-Location C:\AiProject

function Test-Http200($url,[int]$timeout=5){
  try{ (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec $timeout).StatusCode -eq 200 }catch{ $false }
}

# ---- Dev stack checks (expects 1.0-style dev override active) ----
$apiOK = Test-Http200 'http://localhost:8000/health'
Start-Sleep -Seconds 2
$uiOK = $false
try{ $uiOK = (Invoke-WebRequest 'http://localhost:3000' -UseBasicParsing -TimeoutSec 5).StatusCode -in 200,301,302 }catch{ $uiOK = $false }

$devTraffic = if($apiOK -and $uiOK){'GREEN'} elseif($apiOK){'AMBER'} else{'RED'}

Write-Host "== DEV =="
Write-Host "API /health (200):  " ($apiOK ? 'OK' : 'FAIL')
Write-Host "UI reachable :3000: " ($uiOK  ? 'OK' : 'FAIL')
Write-Host "DEV TRAFFIC LIGHT: $devTraffic"

# ---- Prod-profile dry-run analysis (no containers started) ----
$prodFile = Join-Path (Get-Location) 'docker-compose.prod.yml'
$prodExists = Test-Path $prodFile

$sec11=$false; $bind127=$false; $portsCleared=$false; $wrapCmd=$false
if($prodExists){
  $cfg = docker compose -f docker-compose.yml -f docker-compose.prod.yml config | Out-String
  $sec11        = ($cfg -match 'SEC_PATCH_11:\s*"?on"?')
  $bind127      = ($cfg -match 'BIND_HOST:\s*"?127\.0\.0\.1"?')
  # Consider ports cleared if there is no explicit host:container mapping for 8000
$portsCleared = -not ($cfg -match '^\s*ports:\s*\[' -and $cfg -match '8000:8000')
  $wrapCmd      = ($cfg -match 'entrypoint_wrapper\.sh' -or $cfg -match 'sh\s+-lc')
}

$prodTraffic = if($prodExists -and $sec11 -and $bind127 -and $portsCleared){'GREEN'} elseif($prodExists){'AMBER'} else{'RED'}

Write-Host "== PROD PROFILE (dry run) =="
Write-Host "File exists:      " ($prodExists ? 'YES' : 'NO')
Write-Host "SEC_PATCH_11:on:  " ($sec11 ? 'YES' : 'NO')
Write-Host "BIND_HOST=127.0.0.1:" ($bind127 ? 'YES' : 'NO')
Write-Host "ports cleared []: " ($portsCleared ? 'YES' : 'NO')
Write-Host "wrapper/fallback: " ($wrapCmd ? 'YES' : 'NO')
Write-Host "PROD PROFILE TRAFFIC LIGHT: $prodTraffic"

# ---- Summary + RCA hint ----
$overall = if($devTraffic -eq 'GREEN'){ 'GREEN' } elseif($apiOK -and -not $uiOK){ 'AMBER' } else { 'RED' }
Write-Host "TRAFFIC LIGHT (OVERALL DEV): $overall"
if($overall -ne 'GREEN'){
  Write-Host "RCA HINT: If API FAIL, likely 1.1 wrapper/bind/health-path; if UI FAIL, check Next.js build and proxy."
}

# Risk meter (Dev Mode): Read-only validation; no mutations.
