# Bootstrap-ChillChill.ps1
[CmdletBinding()]
param(
  [switch]$DisableOllama = $false,   # set to disable Ollama provider use
  [int]$MaxPasses = 3,               # auto-loop rebuild+validate passes
  [int]$TimeoutSec = 5               # HTTP probe timeout
)

$ErrorActionPreference = 'Stop'
$root = "C:\AiProject"
Set-Location $root

function Write-FileUtf8([string]$Path,[string]$Content){
  $dir = Split-Path $Path -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  if (Test-Path $Path -PathType Leaf) {
    $bak = "$Path.bak"
    if (-not (Test-Path $bak)) { Copy-Item $Path $bak -Force }
  }
  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::UTF8)
}

function Ensure-UiHealthEndpoint {
  # Next.js App Router route: chatbot-ui/app/api/health/route.ts
  $uiHealth = Join-Path $root "chatbot\chatbot-ui\app\api\health\route.ts"
  $code = @"
import { NextResponse } from 'next/server';
export async function GET() { return NextResponse.json({ status: 'ok' }, { status: 200 }); }
"@
  Write-FileUtf8 -Path $uiHealth -Content $code
}

function Get-ComposeConfig(){ try { docker compose config 2>$null } catch { "" } }

function Build-OperatorOverrideYml([string]$cfg, [bool]$disableOllama){
  $hasRedis  = ($cfg -split "`r?`n" | Where-Object { $_ -match '^\s*redis:' } | Measure-Object).Count -gt 0
  $hasQdrant = ($cfg -split "`r?`n" | Where-Object { $_ -match '^\s*qdrant:'} | Measure-Object).Count -gt 0

  $ollamaLine = $disableOllama ? '      OLLAMA_ENABLED: "0"' : '      OLLAMA_HOST: "http://host.docker.internal:11434"'

  $y = @()
  $y += "services:"
  $y += "  api:"
  $y += "    env_file:"
  $y += "      - .env.api.local"
  $y += "    environment:"
  $y += "      CHAT_ECHO: null"            # ensure echo is UNSET
  $y += $ollamaLine
  $y += "    extra_hosts:"
  $y += "      - ""host.docker.internal:host-gateway"""

  $y += "  ui:"
  $y += "    env_file:"
  $y += "      - .env.ui.local"
  $y += "    environment: {}"
  $y += "    healthcheck:"
  $y += "      test: [""CMD-SHELL"", ""wget -qO- http://localhost:3000/api/health || curl -fsS http://localhost:3000/api/health || busybox wget -qO- http://localhost:3000/api/health""]"
  $y += "      interval: 15s"
  $y += "      timeout: 5s"
  $y += "      retries: 10"
  $y += "      start_period: 20s"

  if ($hasRedis) {
    $y += "  redis:"
    $y += "    ports:"
    $y += "      - ""6379:6379"""
  }
  if ($hasQdrant) {
    $y += "  qdrant:"
    $y += "    ports:"
    $y += "      - ""6333:6333"""
  }

  return ($y -join "`n")
}

function Ensure-EnvFiles {
  $apiEnvPath = Join-Path $root ".env.api.local"
  $uiEnvPath  = Join-Path $root ".env.ui.local"

  if (-not (Test-Path $apiEnvPath)) {
    $apiEnv = @"
# API service secrets (paste values; no quotes)
GEMINI_API_KEY=AIzaSyDml3AXe4VA6ZQK3kusCyLY2bFh1mxq6Vw
GROQ_API_KEY=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
OPENAI_API_KEY=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
GOOGLE_API_KEY=AIzaSyDml3AXe4VA6ZQK3kusCyLY2bFh1mxq6Vw
# Optional toggles
OLLAMA_ENABLED=
"@
    Write-FileUtf8 -Path $apiEnvPath -Content $apiEnv
  }
  if (-not (Test-Path $uiEnvPath)) {
    $uiEnv = @"
# UI config (non-secret)
API_URL=http://api:8000/chat
NEXT_PUBLIC_API_BASE_URL=http://127.0.0.1:8000
"@
    Write-FileUtf8 -Path $uiEnvPath -Content $uiEnv
  }
}

function Apply-OperatorComposeOverride {
  $cfg = Get-ComposeConfig
  $yaml = Build-OperatorOverrideYml -cfg $cfg -disableOllama:$DisableOllama
  Write-FileUtf8 -Path (Join-Path $root "docker-compose.operator.override.yml") -Content $yaml
}

function ComposeFiles(){
  $files = @("docker-compose.yml")
  if (Test-Path "docker-compose.override.yml") { $files += "docker-compose.override.yml" }
  $files += "docker-compose.operator.override.yml"
  if (Test-Path "docker-compose.ollama.yml")   { $files += "docker-compose.ollama.yml" }
  return $files
}

function Rebuild-Up {
  $files = ComposeFiles
  $args = @(); foreach($f in $files){ $args += @("-f",$f) }; $args += @("up","-d","--build")
  & docker compose @args | Out-Null
  Start-Sleep -Seconds 6
}

# --- VALIDATION HELPERS ---
function Test-HttpGet([string]$Url){
  try { (Invoke-WebRequest -Uri $Url -TimeoutSec $TimeoutSec).StatusCode } catch { $_.Exception.Message }
}
function Test-HttpPost([string]$Url,[object]$Body){
  try {
    $resp = Invoke-WebRequest -Uri $Url -TimeoutSec $TimeoutSec -Method POST -Body ($Body | ConvertTo-Json -Depth 5) -ContentType "application/json"
    $resp.StatusCode
  } catch { $_.Exception.Message }
}
function Test-Tcp { param([string]$DstHost,[int]$DstPort); try { (Test-NetConnection -ComputerName $DstHost -Port $DstPort).TcpTestSucceeded } catch { $false } }

function Validate(){
  Write-Host "===== VALIDATION SUMMARY =====" -ForegroundColor Cyan
  $apiHealth = Test-HttpGet "http://127.0.0.1:8000/health"; Write-Host "[API] /health :: $apiHealth"
  $apiChat   = Test-HttpPost "http://127.0.0.1:8000/chat" @{ message = "ping" }; Write-Host "[API] /chat   :: $apiChat"

  $psLines = @()
  try { $psLines = docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | ForEach-Object { $_ }; $psLines | Select-String "chill_api|chill_ui|redis|qdrant" | ForEach-Object { $_.Line } | % { Write-Host $_ } } catch { Write-Host "[Containers] docker ps error: $_" -ForegroundColor Yellow }
  $hasQdrant = ($psLines -match "qdrant").Count -gt 0

  try { $dockerVer = docker version --format '{{.Server.Version}}' } catch { $dockerVer="n/a" }
  Write-Host "[Docker] Engine :: $dockerVer"

  # CHAT_ECHO single-line check
  $chatEchoState = "Not set (good)"
  try {
    $cfg = docker compose config 2>$null
    $line = ($cfg -split "`r?`n" | Where-Object { $_ -match '^\s*CHAT_ECHO:\s*' } | Select-Object -First 1)
    if ($line) {
      $m = [regex]::Match($line, "^\s*CHAT_ECHO:\s*(?<val>""|''|[^#\r\n]+)")
      $raw = $m.Groups['val'].Value.Trim()
      $norm = $raw.Trim('"', "'").Trim()
      if ([string]::IsNullOrWhiteSpace($norm)) { $chatEchoState = "Not set (good)" } else { $chatEchoState = "Found value '$norm' (warn)" }
    }
  } catch { $chatEchoState = "Unknown (compose config unavailable)" }
  if ($chatEchoState -like "Found*") { Write-Host "[Env] CHAT_ECHO :: $chatEchoState" -ForegroundColor Yellow } else { Write-Host "[Env] CHAT_ECHO :: $chatEchoState" -ForegroundColor Green }

  $redisOK  = Test-Tcp -DstHost "127.0.0.1" -DstPort 6379; Write-Host "[Infra] redis:6379  ::  " + ($(if($redisOK){"OK"}else{"FAIL"}))
  if ($hasQdrant) {
    $qdrantOK = Test-Tcp -DstHost "127.0.0.1" -DstPort 6333; Write-Host "[Infra] qdrant:6333 ::  " + ($(if($qdrantOK){"OK"}else{"FAIL"}))
  } else { Write-Host "[Infra] qdrant:6333 :: SKIPPED (no container)" }

  try { $oll = Invoke-WebRequest -Uri "http://host.docker.internal:11434/api/tags" -TimeoutSec $TimeoutSec; Write-Host "[Ollama] tags :: $($oll.StatusCode)" } catch { Write-Host "[Ollama] tags :: ERROR $($_.Exception.Message)" -ForegroundColor Yellow }
  Write-Host "===== END VALIDATION ====="
}

function IsGreen([string[]]$lines){
  $apiOk       = ($lines -match "^\[API\] /health :: 200").Count -gt 0
  $chatGood    = ($lines -match "^\[API\] /chat\s+:: (200|201|204)").Count -gt 0
  $echoBad     = ($lines -match "^\[Env\] CHAT_ECHO :: Found").Count -gt 0
  $redisBad    = ($lines -match "^\[Infra\] redis:6379\s+::\s+FAIL").Count -gt 0
  $uiUnhealthy = ($lines -match "chill_ui\s+.*unhealthy").Count -gt 0
  $qdrantLine  = ($lines -match "^\[Infra\] qdrant:6333 :: ").Count -gt 0
  $qdrantBad   = $qdrantLine -and (($lines -match "^\[Infra\] qdrant:6333\s+::\s+FAIL").Count -gt 0)
  if (-not $apiOk) { return $false }
  if (-not $chatGood) { return $false }
  if ($echoBad) { return $false }
  if ($redisBad) { return $false }
  if ($qdrantBad) { return $false }
  if ($uiUnhealthy) { return $false }
  return $true
}

# --- MAIN ---
Ensure-EnvFiles
Ensure-UiHealthEndpoint
Apply-OperatorComposeOverride

$pass = 0
do {
  $pass++
  Write-Host "===== BUILD/UP PASS $pass =====" -ForegroundColor Cyan
  Rebuild-Up
  $val = (Validate) | Tee-Object -Variable outLines
  if (IsGreen $outLines) { Write-Host "TRAFFIC LIGHT: GREEN" -ForegroundColor Green; break }
  if ($pass -ge $MaxPasses) { Write-Host "TRAFFIC LIGHT: AMBER/RED (Needs review)" -ForegroundColor Yellow; break }
  Write-Host "Re-attempting..." -ForegroundColor Yellow
} while ($pass -lt $MaxPasses)

Write-Host "`nRCA:"
Write-Host "- Secrets moved to .env.api.local / .env.ui.local (gitignore recommended)."
Write-Host "- Operator override unsets CHAT_ECHO and adds robust UI healthcheck."
Write-Host "- Layered compose preserved; redis/qdrant ports only if services exist."
Write-Host "- Ollama left optional; use -DisableOllama to silence provider at compose."
