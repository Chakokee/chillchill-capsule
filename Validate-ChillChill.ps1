# Validate-ChillChill.ps1 — Provider wiring & Ollama readiness (fixed 2025-08-21)
param(
  [switch]$EnableRAG
)

$ErrorActionPreference = 'Stop'
$root = 'C:\AiProject'
$api  = Join-Path $root 'chatbot\agent-api'
$envP = Join-Path $root '.env'
$report = @()
function say($m,$c='Gray'){ Write-Host $m -ForegroundColor $c; $report += $m }
$green=$true

# 1) Core health
try {
  $r1 = Invoke-WebRequest 'http://127.0.0.1:8000/health' -TimeoutSec 10
  if ($r1.StatusCode -ne 200) { throw "API /health=$($r1.StatusCode)" }
  say "[API] /health :: 200" 'Green'
} catch { say "[API] /health :: $($_.Exception.Message)" 'Red'; $green=$false }

# /chat is POST — do a minimal POST
try {
  $body = @{ message = "ping" } | ConvertTo-Json
  $r2 = Invoke-WebRequest 'http://127.0.0.1:8000/chat' -Method POST -TimeoutSec 10 -ContentType 'application/json' -Body $body
  say "[API] /chat (POST) :: $($r2.StatusCode)" 'Green'
} catch { say "[API] /chat (POST) :: $($_.Exception.Message)" 'Yellow' }

# 2) Env checks
$hostHost   = 'http://127.0.0.1:11434'
$dockerHost = 'http://host.docker.internal:11434'
$ollModel   = 'llama3.2:3b'
if (Test-Path $envP) {
  $envTxt = Get-Content $envP -Raw
  if ($envTxt -match 'NEXT_PUBLIC_API_BASE_URL\s*=\s*http://127\.0\.0\.1:8000') {
    say "[ENV] NEXT_PUBLIC_API_BASE_URL :: OK (127.0.0.1:8000)" 'Green'
  } else {
    say "[ENV] NEXT_PUBLIC_API_BASE_URL :: WARN (missing/mismatch)" 'Yellow'
  }
  $m = [regex]::Match($envTxt,'OLLAMA_MODEL\s*=\s*(\S+)').Groups[1].Value
  if ($m){ $ollModel=$m }
  $hHost = [regex]::Match($envTxt,'OLLAMA_HOST_HOST\s*=\s*(\S+)').Groups[1].Value
  if ($hHost){ $hostHost=$hHost }
  $dHost = [regex]::Match($envTxt,'OLLAMA_HOST_DOCKER\s*=\s*(\S+)').Groups[1].Value
  if ($dHost){ $dockerHost=$dHost }
} else {
  say "[ENV] .env missing — using defaults" 'Yellow'
}

# 3) Ollama probes (host)
try {
  $tags = Invoke-WebRequest "$hostHost/api/tags" -TimeoutSec 20
  say "[Ollama/Host] /api/tags :: OK" 'Green'
} catch { say "[Ollama/Host] /api/tags :: FAIL ($($_.Exception.Message))" 'Yellow' }

try {
  $payload = @{ model=$ollModel; prompt='ping'; stream=$false } | ConvertTo-Json
  $gen = Invoke-WebRequest "$hostHost/api/generate" -Method POST -ContentType 'application/json' -Body $payload -TimeoutSec 30
  say "[Ollama/Host] /api/generate ($ollModel) :: OK" 'Green'
} catch { say "[Ollama/Host] /api/generate ($ollModel) :: FAIL ($($_.Exception.Message))" 'Yellow' }

# 4) Provider wiring check (expects in-container to use OLLAMA_HOST_DOCKER)
$providersPy = Join-Path $api 'providers.py'
if (Test-Path $providersPy) {
  $content = Get-Content $providersPy -Raw
  $hasClass   = $content -match '(?i)class\s+OllamaProvider'
  $readsHost  = $content -match '(?i)OLLAMA_HOST_DOCKER' -or $content -match '(?i)host\.docker\.internal'
  if ($hasClass -and $readsHost) {
    say "[API] providers.py :: Ollama provider present (docker-host aware)" 'Green'
  } else {
    say "[API] providers.py :: Ollama provider MISSING or not docker-host aware" 'Red'
    $green=$false
  }
} else {
  say "[API] providers.py :: not found at $providersPy" 'Red'
  $green=$false
}

# 5) Optional RAG checks
if ($EnableRAG) {
  try {
    $q = Test-NetConnection -ComputerName '127.0.0.1' -Port 6333 -WarningAction SilentlyContinue
    if ($q.TcpTestSucceeded) { say "[RAG] Qdrant:6333 :: OK" 'Green' } else { say "[RAG] Qdrant:6333 :: SKIPPED (not running)" 'Yellow' }
  } catch { say "[RAG] Qdrant probe :: WARN ($($_.Exception.Message))" 'Yellow' }
}

Write-Host "===== VALIDATION SUMMARY =====" -ForegroundColor Cyan
$report | ForEach-Object { Write-Host $_ }
Write-Host "===== END VALIDATION =====" -ForegroundColor Cyan

# Risk Meter (Validate)
Write-Host "`nRISK METER:" -ForegroundColor Magenta
if ($green) {
  Write-Host "Traffic Light: GREEN — Stack healthy; Ollama reachable; provider wired." -ForegroundColor Green
  exit 0
} else {
  Write-Host "Traffic Light: AMBER/RED — See failures above; run Fix." -ForegroundColor Yellow
  exit 1
}
