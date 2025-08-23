# Fix-ChillChill.ps1
param(
  [switch]$AutoLoop = $true,
  [int]$MaxPasses = 3
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = 'C:\AiProject'
$apiDir = Join-Path $root 'chatbot\agent-api'
$composeOverride = Join-Path $root 'docker-compose.override.yml'
$manifestPath = Join-Path $root 'operator.manifest.json'
$envPath = Join-Path $root '.env'
$provPath = Join-Path $apiDir 'providers.py'

function Ensure-Line($path,$key){
  if(-not (Test-Path $path)){ New-Item -ItemType File -Path $path -Force | Out-Null }
  $c = Get-Content $path -Raw
  if($c -notmatch ("^\s*{0}=" -f [regex]::Escape($key))){
    Add-Content -Path $path -Value "$key=" -Encoding UTF8
  }
}

# 1) Write manifest (idempotent)
$manifest = @{
  autoswitch = @('gemini','groq','mistral')
  personas = @{ GP='gemini'; Chef='groq'; Accountant='groq' }
  rag = @{
    embedder = 'bge-small-en'
    retrieval = @{ top_k=6; rerank_top=3; chunk=850; overlap=120 }
    rules = @{ require_citations=$true; unknown_say="I don't know" }
  }
} | ConvertTo-Json -Depth 6
$manifest | Set-Content -Path $manifestPath -Encoding UTF8

# 2) Ensure .env keys exist (values to be supplied by you)
Ensure-Line $envPath 'GEMINI_API_KEY'
Ensure-Line $envPath 'GROQ_API_KEY'
Ensure-Line $envPath 'MISTRAL_API_KEY'

# 3) Patch compose override to mount manifest & pass keys; remove OpenAI/Ollama wiring
if(-not (Test-Path $composeOverride)){ New-Item -ItemType File -Path $composeOverride -Force | Out-Null }
$y = Get-Content $composeOverride -Raw

if($y -notmatch 'services:\s*api:'){
  $y = @"
services:
  api:
    environment:
      - GEMINI_API_KEY
      - GROQ_API_KEY
      - MISTRAL_API_KEY
    volumes:
      - ./operator.manifest.json:/app/operator.manifest.json:ro
"@
}else{
  # Ensure env and volume entries exist
  if($y -notmatch 'GEMINI_API_KEY'){ $y = $y -replace 'environment:\s*', "environment:`n      - GEMINI_API_KEY`n      - GROQ_API_KEY`n      - MISTRAL_API_KEY`n" }
  if($y -notmatch 'operator\.manifest\.json'){
    $y = $y -replace 'volumes:\s*', "volumes:`n      - ./operator.manifest.json:/app/operator.manifest.json:ro`n"
  }
}
# Strip OpenAI/Ollama lines if present
$y = ($y -split "`r?`n" | Where-Object { $_ -notmatch 'OPENAI_API_KEY|OLLAMA_' }) -join [Environment]::NewLine
$y | Set-Content -Path $composeOverride -Encoding UTF8

# 4) Update providers.py autoswitch/personas (surgical, tolerant if structure differs)
if(Test-Path $provPath){
  $t = Get-Content $provPath -Raw
  $t = $t -replace "(?s)'autoswitch'\s*:\s*\[[^\]]*\]","'autoswitch': ['gemini','groq','mistral']"
  $t = $t -replace "(?s)('GP'.*?:\s*')[^']+(')","`$1gemini`$2"
  $t = $t -replace "(?s)('Chef'.*?:\s*')[^']+(')","`$1groq`$2"
  $t = $t -replace "(?s)('Accountant'.*?:\s*')[^']+(')","`$1groq`$2"
  $t | Set-Content -Path $provPath -Encoding UTF8
}else{
  throw "providers.py not found at $provPath"
}

# 5) Rebuild & restart API with new config
Push-Location $root
try{
  docker compose down
  docker compose up -d --build
} finally {
  Pop-Location
}

# 6) Health checks
try{
  $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/health' -TimeoutSec 10
  Write-Host "[API] /health :: OK"
}catch{
  Write-Host "[API] /health :: FAIL"
}

# Re-Validate (loop up to MaxPasses)
if($AutoLoop){
  for($i=1; $i -le $MaxPasses; $i++){
    Write-Host "=== VALIDATE PASS $i ==="
    pwsh -NoLogo -NoProfile -File (Join-Path $root 'Validate-ChillChill.ps1') | Write-Host
    $summary = pwsh -NoLogo -NoProfile -File (Join-Path $root 'Validate-ChillChill.ps1') | Select-String 'Traffic Light:'
    if($summary -and ($summary.Line -match 'GREEN')){ break }
    if($i -lt $MaxPasses){
      Write-Host "Applying Fix adjustments (pass $($i+1))..."
      Start-Sleep -Seconds 2
    }
  }
}

# Rollback hint
"`nRollback: restore previous state via git or revert compose/manifest/providers.py changes."
