# QuickWins-ChillChill.ps1
# Purpose: Apply "quick wins" in one pass
#   1) Pin OLLAMA_MODEL=llama3.2:3b in .env
#   2) Ensure NEXT_PUBLIC_API_BASE_URL=http://127.0.0.1:8000 (UI→API)
#   3) Set provider routing: Ollama (llama3.2:3b) → Groq (llama3-70b-8192) → Gemini → OpenAI
#   4) Restart containers
#   5) Validate /health, /chat, and Ollama /api/tags & /api/generate
# Includes backups + rollback snippet
[CmdletBinding()]
param(
  [string]$RepoRoot = "C:\AiProject",
  [string]$EnvFile  = ".env",
  [string]$ApiRel   = "chatbot\agent-api",
  [string]$ProvidersRel = "chatbot\agent-api\providers.py",
  [string]$UiRel    = "chatbot\chatbot-ui",
  [switch]$Build    # add -Build to force rebuild images
)

$ErrorActionPreference = 'Stop'
Push-Location $RepoRoot

function Backup-File {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $null }
  $ts  = Get-Date -Format 'yyyyMMdd-HHmmss'
  $bak = "$Path.$ts.bak"
  Copy-Item $Path $bak -Force
  return $bak
}

function Upsert-Line {
  param(
    [string]$Path,
    [string]$Key,
    [string]$Value
  )
  $content = @()
  if (Test-Path $Path) { $content = Get-Content $Path -Raw -ErrorAction SilentlyContinue -Encoding UTF8 } else { $content = "" }
  if ($content -match "(?m)^\s*$([regex]::Escape($Key))\s*=") {
    $new = [regex]::Replace($content, "(?m)^\s*$([regex]::Escape($Key))\s*=.*$", "$Key=$Value")
  } else {
    $trimmed = $content.TrimEnd()
    if ($trimmed.Length -gt 0) { $new = "$trimmed`r`n$Key=$Value`r`n" } else { $new = "$Key=$Value`r`n" }
  }
  Set-Content -Path $Path -Value $new -Encoding UTF8
}

function Ensure-ProviderRouting {
  param([string]$ProvidersPath)
  if (-not (Test-Path $ProvidersPath)) { throw "providers.py not found at $ProvidersPath" }
  $bak = Backup-File $ProvidersPath
  $txt = Get-Content $ProvidersPath -Raw -Encoding UTF8

  # Normalize GROQ model name
  $txt = [regex]::Replace($txt, "(?m)^\s*GROQ_MODEL\s*=\s*['""]([^'""]+)['""]", "GROQ_MODEL = 'llama3-70b-8192'")
  if ($txt -notmatch "(?m)^\s*GROQ_MODEL\s*=") {
    $txt = "GROQ_MODEL = 'llama3-70b-8192'`r`n$txt"
  }

  # Ensure OLLAMA model default
  $txt = [regex]::Replace($txt, "(?m)^\s*OLLAMA_MODEL\s*=\s*['""]([^'""]+)['""]", "OLLAMA_MODEL = 'llama3.2:3b'")
  if ($txt -notmatch "(?m)^\s*OLLAMA_MODEL\s*=") {
    $txt = "OLLAMA_MODEL = 'llama3.2:3b'`r`n$txt"
  }

  # Provider order list (prefer local first, then Groq, then Gemini, then OpenAI)
  # Matches a list like: PROVIDER_ORDER = ['gemini','groq','openai','ollama']
  $order = "['ollama','groq','gemini','openai']"
  if ($txt -match "(?m)^\s*PROVIDER_ORDER\s*=") {
    $txt = [regex]::Replace($txt, "(?m)^\s*PROVIDER_ORDER\s*=\s*\[.*?\]", "PROVIDER_ORDER = $order")
  } else {
    $txt = "PROVIDER_ORDER = $order`r`n$txt"
  }

  Set-Content -Path $ProvidersPath -Value $txt -Encoding UTF8
  return $bak
}

Write-Host "=== QUICK WINS START ==="

# 1) .env updates
$envPath = Join-Path $RepoRoot $EnvFile
$envBak  = $null
if (Test-Path $envPath) { $envBak = Backup-File $envPath }
Upsert-Line -Path $envPath -Key "OLLAMA_MODEL" -Value "llama3.2:3b"
# Keep UI→API path stable for browser:
Upsert-Line -Path $envPath -Key "NEXT_PUBLIC_API_BASE_URL" -Value "http://127.0.0.1:8000"

# 2) providers.py routing/model updates
$providersPath = Join-Path $RepoRoot $ProvidersRel
$provBak = Ensure-ProviderRouting -ProvidersPath $providersPath

# 3) Restart containers (UI pick up NEXT_PUBLIC_*, API pick up provider changes)
if ($Build) {
  docker compose up -d --build --remove-orphans
} else {
  # Restart API & UI to refresh env/code
  docker compose restart api ui | Out-Null
}

# 4) Post-change validation
function Test-Http {
  param([string]$Url,[int]$Timeout=10,[string]$Method="GET",[string]$Body=$null,[string]$ContentType="application/json")
  try {
    if ($Method -eq "POST") {
      return (Invoke-WebRequest -Uri $Url -Method POST -Body $Body -ContentType $ContentType -TimeoutSec $Timeout).StatusCode
    } else {
      return (Invoke-WebRequest -Uri $Url -TimeoutSec $Timeout).StatusCode
    }
  } catch {
    return "FAIL"
  }
}

$results = [ordered]@{}
$results["API /health"] = Test-Http "http://127.0.0.1:8000/health"
$results["API /chat (POST)"] = Test-Http "http://127.0.0.1:8000/chat" -Method POST -Body '{"message":"ping"}'
$results["Ollama /api/tags"] = Test-Http "http://127.0.0.1:11434/api/tags"
$results["Ollama /api/generate"] = Test-Http "http://127.0.0.1:11434/api/generate" -Method POST -Body '{"model":"llama3.2:3b","prompt":"ok"}'

Write-Host "===== VALIDATION SUMMARY ====="
$green = $true
foreach ($k in $results.Keys) {
  $v = $results[$k]
  $ok = ($v -eq 200)
  if (-not $ok) { $green = $false }
  Write-Host ("{0,-22} :: {1}" -f $k, $v)
}

if ($green) {
  Write-Host "TRAFFIC LIGHT: GREEN — Quick wins applied successfully."
} else {
  Write-Host "TRAFFIC LIGHT: AMBER — Core updated; one or more checks failed. Inspect API/UI logs or Ollama service."
}

Write-Host "=== QUICK WINS END ==="

# Rollback snippet (printed for convenience)
"`n--- ROLLBACK ---"
if ($envBak)  { "To rollback .env:    Copy-Item `"$envBak`" `"$envPath`" -Force" }
if ($provBak) { "To rollback providers: Copy-Item `"$provBak`" `"$providersPath`" -Force" }
"Then restart: docker compose restart api ui"

Pop-Location
