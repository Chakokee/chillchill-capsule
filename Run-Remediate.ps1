$ErrorActionPreference = "Stop"
$root   = "C:\AiProject"
$envFile= Join-Path $root ".env"
$apiUrl = "http://localhost:8000"
$uiUrl  = "http://localhost:3000"

function Write-Info($msg){ Write-Host $msg -ForegroundColor Cyan }
function Write-Warn($msg){ Write-Host $msg -ForegroundColor Yellow }
function Write-Ok($msg){ Write-Host $msg -ForegroundColor Green }
function Write-Bad($msg){ Write-Host $msg -ForegroundColor Red }

Set-Location $root

Write-Info "== Step 1: Ensure .env provider/model and key =="
if (!(Test-Path $envFile)) { New-Item -ItemType File -Path $envFile | Out-Null }
$content = (Get-Content -Path $envFile -Raw -ErrorAction SilentlyContinue)
if (-not $content) { $content = "" }

function UpsertKV([string]$k,[string]$v){
  if ($content -match ("^" + [regex]::Escape($k) + "=.*") ){
    $script:content = [regex]::Replace($script:content, "^" + [regex]::Escape($k) + ".*", $k + "=" + $v, 'Multiline')
  } else {
    if ($script:content.Length -gt 0 -and $script:content[-1] -ne "`n") { $script:content += "`r`n" }
    $script:content += ($k + "=" + $v + "`r`n")
  }
}

UpsertKV "LLM_PROVIDER" "openai"
UpsertKV "LLM_MODEL"    "gpt-4o-mini"

# Optional: prompt once for OPENAI_API_KEY (press Enter to skip)
$haveOpenAI = [regex]::IsMatch($content, '^OPENAI_API_KEY=.+', 'Multiline')
if (-not $haveOpenAI){
  $plain = Read-Host "Optional: paste OPENAI_API_KEY (or press Enter to skip)"
  if ($plain) { UpsertKV "OPENAI_API_KEY" $plain } elseif ($content -notmatch '^OPENAI_API_KEY=') { UpsertKV "OPENAI_API_KEY" "" }
}

if ($content -notmatch '^GROQ_API_KEY='){ UpsertKV "GROQ_API_KEY" "" }
if ($content -notmatch '^GOOGLE_API_KEY='){ UpsertKV "GOOGLE_API_KEY" "" }
if ($content -notmatch '^OLLAMA_HOST='){ UpsertKV "OLLAMA_HOST" "http://host.docker.internal:11434" }

Set-Content -Path $envFile -Value $content -Encoding UTF8
Write-Ok "Updated .env with provider/model and key placeholders."

Write-Info "== Step 2: Recreate api/ui and remove orphans =="
docker compose up -d --build --force-recreate --remove-orphans api ui

Write-Info "== Step 3: Service status (JSON with text fallback) =="
$apiUp = $false; $uiUp = $false
try {
  $psJson = docker compose ps --format json 2>$null
  if ([string]::IsNullOrWhiteSpace($psJson)) { throw "no-json" }
  $ps = $psJson | ConvertFrom-Json
  $apiUp = ($ps | Where-Object { $_.Name -match "api" -and $_.State -match "running" }).Count -ge 1
  $uiUp  = ($ps | Where-Object { $_.Name -match "ui"  -and $_.State -match "running" }).Count -ge 1
} catch {
  $txt = docker compose ps 2>$null
  $apiUp = ($txt -match "chill_api" -and $txt -match "Running") -or ($txt -match "api" -and $txt -match "running")
  $uiUp  = ($txt -match "chill_ui"  -and $txt -match "Running") -or ($txt -match "ui"  -and $txt -match "running")
}
Write-Host ("Detected: api=" + $apiUp + ", ui=" + $uiUp)

Write-Info "== Step 4: Health checks =="
try { $h = Invoke-RestMethod -Uri ($apiUrl + "/health") -TimeoutSec 8; Write-Ok ("API health: " + ($h | ConvertTo-Json -Compress)) } catch { Write-Warn "API /health not responding yet." }
try { $r = Invoke-WebRequest -Uri $uiUrl -TimeoutSec 8; Write-Ok ("UI status: " + $r.StatusCode) } catch { Write-Warn "UI not responding yet." }

Write-Info "== Step 5: Lint --fix (non-fatal) =="
try { docker compose exec -T ui sh -lc "npm -s run lint -- --fix || true" | Out-Host } catch { Write-Warn "lint step skipped or failed (non-fatal)" }

Write-Info "== Step 6: Functional probe (/chat) =="
$echoAns = $null
try {
  $b = @{ message="Say ok once."; use_rag=$false } | ConvertTo-Json -Compress
  $resp = Invoke-RestMethod -Uri ($apiUrl + "/chat") -Method Post -ContentType "application/json" -Body $b -TimeoutSec 20
  $echoAns = ($resp.answer | Out-String).Trim()
  Write-Host ("/chat answer= " + $echoAns)
} catch { Write-Warn "POST /chat failed" }

Write-Info "== Step 7: Verdict and next step =="
$needKey = ($echoAns -match '^Echo:')
if (-not $apiUp -or -not $uiUp) {
  Write-Bad "Next: Services not detected running. Check 'docker compose ps' and container logs."
  exit 2
} elseif ($needKey) {
  Write-Warn "Next: Provide a valid provider API key (OPENAI_API_KEY recommended) in .env and rerun this script."
  exit 6
} else {
  Write-Ok "Next: Proceed to Security Baseline (auth, CORS/CSP, rate-limit)."
  exit 0
}
