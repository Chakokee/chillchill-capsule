# Fix-ChillChill.ps1 — Dual-host Ollama env + provider patch + rebuild (fixed 2025-08-21)
param(
  [switch]$AutoLoop,
  [int]$MaxPasses = 3
)

$ErrorActionPreference = 'Stop'
$root='C:\AiProject'
$api = Join-Path $root 'chatbot\agent-api'
$envP= Join-Path $root '.env'
function say($m,$c='Gray'){ Write-Host $m -ForegroundColor $c }

# Helpers
function Set-Or-AppendLine {
  param([string]$Text,[string]$Key,[string]$Value)
  $pattern = "(?m)^\s*$([regex]::Escape($Key))\s*="
  if ($Text -match $pattern) {
    return ([regex]::Replace($Text,$pattern,"$Key=$Value"))
  } else {
    if ($Text -and -not $Text.EndsWith("`r`n")) { $Text += "`r`n" }
    return ($Text + "$Key=$Value`r`n")
  }
}

# 0) Ensure .env contains API base + dual OLLAMA hosts
if (-not (Test-Path $envP)) { New-Item -ItemType File -Path $envP -Force | Out-Null }
$envTxt = Get-Content $envP -Raw
$envTxt = Set-Or-AppendLine -Text $envTxt -Key 'NEXT_PUBLIC_API_BASE_URL' -Value 'http://127.0.0.1:8000'
$envTxt = Set-Or-AppendLine -Text $envTxt -Key 'OLLAMA_MODEL'            -Value 'llama3.2:3b'
$envTxt = Set-Or-AppendLine -Text $envTxt -Key 'OLLAMA_HOST_HOST'        -Value 'http://127.0.0.1:11434'
$envTxt = Set-Or-AppendLine -Text $envTxt -Key 'OLLAMA_HOST_DOCKER'      -Value 'http://host.docker.internal:11434'
$envTxt | Set-Content -Path $envP -Encoding UTF8
say "[ENV] .env updated with API base + dual OLLAMA hosts" 'Yellow'

# 1) Patch providers.py for an Ollama provider that uses OLLAMA_HOST_DOCKER
$providersPy = Join-Path $api 'providers.py'
if (-not (Test-Path $providersPy)) { throw "providers.py not found at $providersPy" }
$src = Get-Content $providersPy -Raw

$needPatch = ($src -notmatch '(?i)class\s+OllamaProvider') -or ($src -notmatch '(?i)OLLAMA_HOST_DOCKER')
if ($needPatch) {
  $patch = @"
# --- Ollama provider (added by Fix-ChillChill) ---
import os, requests

class OllamaProvider:
    def __init__(self):
        self.host = os.environ.get("OLLAMA_HOST_DOCKER", "http://host.docker.internal:11434")
        self.model = os.environ.get("OLLAMA_MODEL", "llama3.2:3b")

    def generate(self, prompt: str, stream: bool=False):
        url = f"{self.host}/api/generate"
        payload = {"model": self.model, "prompt": prompt, "stream": False}
        r = requests.post(url, json=payload, timeout=30)
        r.raise_for_status()
        j = r.json()
        return (j.get("response") or j.get("message") or "")

try:
    PROVIDERS  # noqa
except NameError:
    PROVIDERS = {}

# Register if missing
if "ollama" not in PROVIDERS:
    PROVIDERS["ollama"] = OllamaProvider()
# --- end Ollama provider patch ---
"@
  $src += "`r`n" + $patch
  $src | Set-Content -Path $providersPy -Encoding UTF8
  say "[API] providers.py patched with docker-host-aware Ollama provider" 'Yellow'
} else {
  say "[API] providers.py already docker-host aware; no change" 'Green'
}

# 2) Rebuild containers
Push-Location $root
try {
  docker compose up -d --build chill_api | Out-Null
  say "[Docker] Rebuilt chill_api" 'Green'
  docker compose up -d --build chill_ui  | Out-Null
  say "[Docker] Rebuilt chill_ui" 'Green'
} finally { Pop-Location }

# 3) Auto-loop Validate until GREEN (optional)
function Validate { & (Join-Path $root 'Validate-ChillChill.ps1'); return $LASTEXITCODE }
$pass=0
do {
  $pass++
  say "Validate pass #$pass..." 'Cyan'
  $code = Validate
  if ($code -eq 0) { say "Traffic Light: GREEN" 'Green'; break }
  if (-not $AutoLoop -or $pass -ge $MaxPasses) { say "Traffic Light: AMBER/RED — manual follow-up required." 'Yellow'; break }
  say "Applying next pass..." 'Yellow'
} while ($true)

# Rollback (git)
Write-Host "`nRollback:" -ForegroundColor Magenta
Write-Host "  git checkout -- $providersPy ; (git restore --staged . 2>$null)" -ForegroundColor DarkGray
