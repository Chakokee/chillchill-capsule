# GuardAndSmoke.ps1  (clean)
[CmdletBinding()]
param(
  [string]$RepoRoot = "C:\AiProject",
  [string]$ProvidersRel = "chatbot\agent-api\providers.py",
  [string]$EnvRel = ".env",
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$providersPath = Join-Path $RepoRoot $ProvidersRel
$envPath       = Join-Path $RepoRoot $EnvRel

function Fail([string]$msg){ Write-Error $msg; return $false }
function Test-Http {
  param([string]$Url,[int]$Timeout=8,[string]$Method="GET",[string]$Body=$null,[string]$ContentType="application/json")
  try {
    if ($Method -eq "POST") { (Invoke-WebRequest -Uri $Url -Method POST -Body $Body -ContentType $ContentType -TimeoutSec $Timeout).StatusCode }
    else { (Invoke-WebRequest -Uri $Url -TimeoutSec $Timeout).StatusCode }
  } catch { "FAIL" }
}

$ok = $true

# Static config checks
if (-not (Test-Path $providersPath)) { $ok = Fail "providers.py not found at $providersPath" -and $ok } else {
  $p = Get-Content $providersPath -Raw -Encoding UTF8
  if ($p -notmatch "PROVIDER_ORDER\s*=\s*\[\s*'ollama'\s*,\s*'groq'\s*,\s*'gemini'\s*,\s*'openai'\s*\]") { $ok = Fail "PROVIDER_ORDER must be ['ollama','groq','gemini','openai']" -and $ok }
  if ($p -notmatch "GROQ_MODEL\s*=\s*'llama3-70b-8192'")                                    { $ok = Fail "GROQ_MODEL must be 'llama3-70b-8192'" -and $ok }
  if ($p -notmatch "OLLAMA_MODEL\s*=\s*'llama3\.2:3b'")                                     { $ok = Fail "OLLAMA_MODEL must be 'llama3.2:3b'" -and $ok }
}
if (-not (Test-Path $envPath)) { $ok = Fail ".env not found at $envPath" -and $ok } else {
  $e = Get-Content $envPath -Raw -Encoding UTF8
  if ($e -notmatch "(?m)^\s*OLLAMA_MODEL\s*=\s*llama3\.2:3b\s*$")                           { $ok = Fail ".env → OLLAMA_MODEL must be llama3.2:3b" -and $ok }
  if ($e -notmatch "(?m)^\s*NEXT_PUBLIC_API_BASE_URL\s*=\s*http://127\.0\.0\.1:8000\s*$")   { $ok = Fail ".env → NEXT_PUBLIC_API_BASE_URL must be http://127.0.0.1:8000" -and $ok }
}

# Runtime smoke
$apiHealth = Test-Http "http://127.0.0.1:8000/health"
$apiChat   = Test-Http "http://127.0.0.1:8000/chat" -Method POST -Body '{"message":"ping"}'
$tags      = Test-Http "http://127.0.0.1:11434/api/tags"
$gen       = Test-Http "http://127.0.0.1:11434/api/generate" -Method POST -Body '{"model":"llama3.2:3b","prompt":"ok"}'

Write-Host "===== GUARD + SMOKE SUMMARY ====="
("{0,-28} :: {1}" -f "providers.py/.env checks", ($(if($ok){"OK"}else{"FAIL"}))) | Write-Host
("{0,-28} :: {1}" -f "API /health", $apiHealth) | Write-Host
("{0,-28} :: {1}" -f "API /chat (POST)", $apiChat) | Write-Host
("{0,-28} :: {1}" -f "Ollama /api/tags", $tags) | Write-Host
("{0,-28} :: {1}" -f "Ollama /api/generate", $gen) | Write-Host

$runtimeOk = ($apiHealth -eq 200 -and $apiChat -eq 200 -and $tags -eq 200 -and $gen -eq 200)
if ($ok -and $runtimeOk) {
  Write-Host "Traffic Light: GREEN — Config + runtime healthy."
  if (-not $NoPause) { Pause }
  exit 0
} else {
  Write-Host "Traffic Light: RED — Guard/Smoke failed."
  if (-not $ok) { Write-Host "Tip: Fix config first (providers.py/.env), then rerun." }
  if (-not $NoPause) { Pause }
  exit 1
}
