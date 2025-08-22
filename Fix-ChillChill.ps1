# Fix-ChillChill.ps1  (v4)
[CmdletBinding()]
param(
  [switch]$EnableOllamaContainer,
  [switch]$AutoPullModel,           # pulls if Ollama reachable but empty
  [string]$Model = "llama3.2:3b",
  [int]$MaxWaitSec = 20
)

$ErrorActionPreference = 'Stop'
$root = Get-Location
$validatorPath = Join-Path $root 'Validate-ChillChill.ps1'
if (-not (Test-Path $validatorPath)) { throw "Validator not found at $validatorPath" }

# Backup validator
$ts  = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item $validatorPath "$validatorPath.$ts.bak" -Force

# Overwrite with safe validator content (from the message)
$validatorText = @'
<<VALIDATOR_CONTENT>>
'@.Replace('<<VALIDATOR_CONTENT>>', (Get-Content -Raw -Path $validatorPath))  # noop if you paste validator first

# If you pasted validator content above, comment the two lines above
# and uncomment the next line to write from a local file you already saved:
# $validatorText = Get-Content -Raw -Path $validatorPath

# Ensure Ollama is reachable
$ollamaUrl = "http://127.0.0.1:11434"
function Test-Url { param([string]$Url,[int]$Timeout=6) try { Invoke-WebRequest -Uri $Url -TimeoutSec $Timeout | Out-Null; $true } catch { $false } }

if (-not (Test-Url "$ollamaUrl/")) {
  if ($EnableOllamaContainer) {
    if (Test-Path ".\docker-compose.ollama.yml") {
      Write-Host "Starting Ollama overlay container..."
      docker compose -f docker-compose.yml -f docker-compose.ollama.yml up -d --remove-orphans | Out-Null
      $sw = [Diagnostics.Stopwatch]::StartNew()
      do { Start-Sleep 2 } while (-not (Test-Url "$ollamaUrl/") -and $sw.Elapsed.TotalSeconds -lt $MaxWaitSec)
    } else {
      Write-Warning "docker-compose.ollama.yml not found; cannot start overlay."
    }
  } else {
    Write-Warning "Ollama not reachable and overlay not requested. Start it manually (ollama serve)."
  }
}

# Optional: pull a small model if tags call fails (fresh server has none)
if (Test-Url "$ollamaUrl/") {
  try {
    $tagsOk = Test-Url "$ollamaUrl/api/tags"
    if (-not $tagsOk -and $AutoPullModel) {
      Write-Host "Pulling model $Model (this may take a while)..."
      $body = @{ name = $Model } | ConvertTo-Json -Compress
      Invoke-WebRequest -Uri "$ollamaUrl/api/pull" -Method POST -Body $body -ContentType "application/json" -TimeoutSec ($MaxWaitSec*3) | Out-Null
    }
  } catch {
    Write-Warning "Tags/pull step failed: $($_.Exception.Message)"
  }
}

# Re-run validator
Write-Host "Re-running validator..."
pwsh -NoLogo -NoProfile -File $validatorPath
