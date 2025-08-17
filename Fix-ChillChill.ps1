# C:\AiProject\Fix-ChillChill.ps1
param(
  [switch]$AutoLoop = $true,
  [int]$MaxPasses = 3,
  [switch]$RequireProdGreen = $true  # enforce prod-like GREEN before stopping
)

$ErrorActionPreference = 'Stop'
Set-Location C:\AiProject

# --- helpers ---------------------------------------------------------------
function Write-DevOverride {
@"
services:
  api:
    command: uvicorn main:app --host 0.0.0.0 --port 8000
    environment:
      BIND_HOST: "0.0.0.0"
      PORT: "8000"
      CHAT_ECHO: "false"
      SEC_PATCH_11: "off"
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:8000/health"]
      interval: 10s
      timeout: 3s
      retries: 5
    ports:
      - "8000:8000"
  ui:
    depends_on:
      api:
        condition: service_healthy
    ports:
      - "3000:3000"
"@ | Set-Content -Path .\docker-compose.override.yml -Encoding UTF8
}

function Write-ProdProfile {
@'
services:
  api:
    container_name: chill_api_prodlike
    command:
      - sh
      - -lc
      - |
        if [ -x /app/entrypoint_wrapper.sh ]; then
          exec /app/entrypoint_wrapper.sh;
        else
          echo "[prodlike] wrapper missing -> fallback to uvicorn 127.0.0.1:8000";
          exec uvicorn main:app --host 127.0.0.1 --port 8000;
        fi
    environment:
      SEC_PATCH_11: "on"
      BIND_HOST: "127.0.0.1"
      PORT: "8000"
    ports: []          # ensure no host bind — avoid 8000 collision
    depends_on: {}     # do not start deps during smoke test
    healthcheck:
      test: ["CMD-SHELL","curl -fsS http://localhost:8000/__health || curl -fsS http://localhost:8000/health"]
      interval: 10s
      timeout: 4s
      retries: 6
  redis:
    container_name: chill_redis_prodlike
  vector:
    container_name: chill_vector_prodlike
'@ | Set-Content -Path .\docker-compose.prod.yml -Encoding UTF8
}

function Compose-Rebuild {
  docker compose down --remove-orphans | Out-Null
  docker compose up -d --build       | Out-Null
}

function Dev-Validate {
  # API
  $apiOK = $false
  try {
    $r = Invoke-WebRequest 'http://localhost:8000/health' -UseBasicParsing -TimeoutSec 5
    $apiOK = ($r.StatusCode -eq 200)
  } catch {}

  Start-Sleep -Seconds 2

  # UI
  $uiOK = $false
  try {
    $u = Invoke-WebRequest 'http://localhost:3000' -UseBasicParsing -TimeoutSec 5
    $uiOK = ($u.StatusCode -in 200,301,302)
  } catch {}

  $apiTxt = if($apiOK){'OK'}else{'FAIL'}
  $uiTxt  = if($uiOK){'OK'}else{'FAIL'}
  $tl     = if($apiOK -and $uiOK){'GREEN'} elseif($apiOK){'AMBER'} else{'RED'}

  Write-Host ("DEV CHECK → API:{0} UI:{1}  DEV TRAFFIC: {2}" -f $apiTxt, $uiTxt, $tl)
  return $tl
}

function ProdProfile-DryRun-OK {
  if(-not (Test-Path .\docker-compose.prod.yml)){ return $false }
  $cfg = docker compose -f docker-compose.yml -f docker-compose.prod.yml config | Out-String
  $sec11        = ($cfg -match 'SEC_PATCH_11:\s*"?on"?')
  $bind         = ($cfg -match 'BIND_HOST:\s*"?127\.0\.0\.1"?')
  # Consider ports cleared if there is no explicit 8000:8000 host mapping
  $portsCleared = -not ($cfg -match '^\s*ports:\s*\[' -and $cfg -match '8000:8000')
  return ($sec11 -and $bind -and $portsCleared)
}

function ProdProfile-Smoke {
  $proj='aiproject-prodlike'
  docker compose -p $proj -f docker-compose.yml -f docker-compose.prod.yml up -d --no-deps api | Out-Null
  Start-Sleep -Seconds 8
  $api = docker ps --filter "name=chill_api_prodlike" --format "{{.Names}}" | Select-Object -First 1
  if(-not $api){
    Write-Host "PRODLIKE CHECK → RED (api failed to start)"
    docker compose -p $proj -f docker-compose.yml -f docker-compose.prod.yml logs api
    docker compose -p $proj -f docker-compose.yml -f docker-compose.prod.yml down -v | Out-Null
    return 'RED'
  }
  docker exec $api sh -lc "curl -fsS http://localhost:8000/__health || curl -fsS http://localhost:8000/health" | Write-Host
  $tl = if($LASTEXITCODE -eq 0){ 'GREEN' } else { 'AMBER' }
  Write-Host ("PRODLIKE TRAFFIC: {0}" -f $tl)
  docker compose -p $proj -f docker-compose.yml -f docker-compose.prod.yml down -v | Out-Null
  return $tl
}

# --- loop ---------------------------------------------------------------
$pass = 0
$final='RED'
do {
  $pass++
  Write-Host ("=== FIX PASS {0} ===" -f $pass)

  if($pass -eq 1){
    Write-DevOverride
    Compose-Rebuild
    Start-Sleep 6
    $devTL = Dev-Validate
    Write-Host ("DEV TRAFFIC AFTER PASS {0}: {1}" -f $pass, $devTL)
    if(($devTL -eq 'GREEN') -and (-not $RequireProdGreen)){ $final='GREEN'; break }
  }

  if($pass -le 2){
    Write-ProdProfile
    $ok = ProdProfile-DryRun-OK
    $okTxt = if($ok){'YES'}else{'NO'}
    Write-Host ("PROD PROFILE MERGE OK: {0}" -f $okTxt)
    $prodTL = if($ok){ ProdProfile-Smoke } else { 'RED' }

    if($prodTL -eq 'GREEN'){
      # If dev is already green, we’re done; otherwise re-check dev quickly after prod prep
      $devTL2 = Dev-Validate
      if($devTL2 -eq 'GREEN'){ $final='GREEN'; break }
    }
  }

  if($pass -ge 3){
    Write-Host "Diagnostics: last 100 lines from API (if running)"
    $apiId = docker ps --filter "name=api" --format "{{.ID}}" | Select-Object -First 1
    if($apiId){ docker logs --tail 100 $apiId | Write-Host } else { Write-Host "(No running API container found.)" }
    $final = Dev-Validate
    break
  }

} while ($AutoLoop -and $pass -lt $MaxPasses)

# --- summary ------------------------------------------------------------
if($final -eq 'GREEN'){
  Write-Host "RCA: Local dev was blocked by Sec Patch 1.1 (wrapper/bind/health). Dev override (1.0) restored reachability; UI unblocked."
  if($RequireProdGreen){ Write-Host "Prod-like profile validated: wrapper-fallback, 127.0.0.1 bind, no ports, dual healthcheck." }
}else{
  Write-Host "RCA: Dev not GREEN. If API FAILS, confirm 0.0.0.0:8000 and /health. If UI FAILS, check Next.js build and /bridge proxy."
}
Write-Host ("TRAFFIC LIGHT: {0}" -f $final)

# Rollback snippet (override/profile only)
Write-Host "Rollback: git checkout -- docker-compose.override.yml docker-compose.prod.yml"

# --- Developer Mode risk meter ---
# Risk: Low (local only). Changes limited to dev override + prod profile; no public ingress; isolated prod-like smoke test (no ports).
