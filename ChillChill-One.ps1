# ChillChill-One.ps1 — SINGLE SCRIPT (Init/Fix + Rebuild + Validate)
[CmdletBinding()]
param(
  [switch]$Init,            # writes env files, UI /api/health route, operator override
  [switch]$Rebuild,         # docker compose up -d --build
  [switch]$IgnoreOllama,    # skip Ollama probe in validation
  [switch]$EnableRAG,       # check Qdrant in validation; if -Init and service exists, ports are published
  [int]$TimeoutSec = 5,     # HTTP probe timeout
  [int]$StartDelaySec = 6   # delay after compose up
)

$ErrorActionPreference = 'Stop'
$root = "C:\AiProject"
Set-Location $root

# ---------------- Helpers ----------------
function Say { param($Msg,[ConsoleColor]$Color='Gray'); Write-Host $Msg -ForegroundColor $Color }
function Write-FileUtf8 { param($Path,$Content)
  $dir = Split-Path $Path -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  if (Test-Path $Path -PathType Leaf) {
    $bak = "$Path.bak"; if (-not (Test-Path $bak)) { Copy-Item $Path $bak -Force }
  }
  [IO.File]::WriteAllText($Path, $Content, [Text.Encoding]::UTF8)
}
function Get-Http { param($Url); try{ (Invoke-WebRequest -Uri $Url -TimeoutSec $TimeoutSec).StatusCode }catch{ $_.Exception.Message } }
function Post-Json { param($Url,$Body); try{ (Invoke-WebRequest -Uri $Url -Method POST -Body ($Body|ConvertTo-Json -Depth 5) -ContentType 'application/json' -TimeoutSec $TimeoutSec).StatusCode }catch{ $_.Exception.Message } }
function TcpOK { param($DstHost,$DstPort); try{ (Test-NetConnection -ComputerName $DstHost -Port $DstPort).TcpTestSucceeded }catch{ $false } }
function Get-DockerVersion { try { docker version --format '{{.Server.Version}}' } catch { 'n/a' } }
function Get-Containers { try { docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' } catch { @() } }
function Get-ComposeConfig { try { docker compose config 2>$null } catch { '' } }
function ComposeFiles {
  $files = @('docker-compose.yml')
  if (Test-Path 'docker-compose.override.yml') { $files += 'docker-compose.override.yml' }
  if (Test-Path 'docker-compose.operator.override.yml') { $files += 'docker-compose.operator.override.yml' }
  if (Test-Path 'docker-compose.ollama.yml') { $files += 'docker-compose.ollama.yml' }
  if (Test-Path 'docker-compose.qdrant.override.yml') { $files += 'docker-compose.qdrant.override.yml' }
  return $files
}
function ComposeUp {
  $files = ComposeFiles
  $args = @(); foreach($f in $files){ $args += @('-f',$f) }; $args += @('up','-d','--build')
  & docker compose @args | Out-Null
  Start-Sleep -Seconds $StartDelaySec
}

# ------------- Init / Fix (idempotent) -------------
if ($Init) {
  # 1) UI health route (Next.js App Router)
  $uiHealth = Join-Path $root 'chatbot\chatbot-ui\app\api\health\route.ts'
  $code = @"
import { NextResponse } from 'next/server';
export async function GET() { return NextResponse.json({ status: 'ok' }, { status: 200 }); }
"@
  Write-FileUtf8 -Path $uiHealth -Content $code

  # 2) Local env files (no secrets printed)
  $apiEnv = Join-Path $root '.env.api.local'
  $uiEnv  = Join-Path $root '.env.ui.local'
  if (-not (Test-Path $apiEnv)) {
    Write-FileUtf8 $apiEnv @"
# API service secrets (paste values; no quotes)
GEMINI_API_KEY=
GROQ_API_KEY=
OPENAI_API_KEY=
GOOGLE_API_KEY=
# Optional toggle
OLLAMA_ENABLED=
"@
  }
  if (-not (Test-Path $uiEnv)) {
    Write-FileUtf8 $uiEnv @"
# UI config (non-secret)
API_URL=http://api:8000/chat
NEXT_PUBLIC_API_BASE_URL=http://127.0.0.1:8000
"@
  }

  # 3) Operator override (augment existing services; unset CHAT_ECHO; robust UI healthcheck)
  $cfg = Get-ComposeConfig
  $hasRedis  = ($cfg -split "`r?`n" | ? { $_ -match '^\s*redis:' }).Count -gt 0
  $hasQdrant = ($cfg -split "`r?`n" | ? { $_ -match '^\s*qdrant:' }).Count -gt 0

  $lines = @(
    'services:',
    '  api:',
    '    env_file:',
    '      - .env.api.local',
    '    environment:',
    '      CHAT_ECHO: null',  # force unset
    '    extra_hosts:',
    '      - "host.docker.internal:host-gateway"',
    '',
    '  ui:',
    '    env_file:',
    '      - .env.ui.local',
    '    environment: {}',
    '    healthcheck:',
    '      test: ["CMD-SHELL", "wget -qO- http://localhost:3000/api/health || curl -fsS http://localhost:3000/api/health || busybox wget -qO- http://localhost:3000/api/health"]',
    '      interval: 15s',
    '      timeout: 5s',
    '      retries: 10',
    '      start_period: 20s'
  )
  if ($hasRedis)  { $lines += @('','  redis:','    ports:','      - "6379:6379"') }
  if ($hasQdrant) { $lines += @('','  qdrant:','    ports:','      - "6333:6333"') }

  Write-FileUtf8 -Path (Join-Path $root 'docker-compose.operator.override.yml') -Content ($lines -join "`n")
}

# ------------- Rebuild (optional) -------------
if ($Rebuild -or $Init) {
  Say 'Bringing stack up (layered compose)...' Cyan
  ComposeUp
}

# ------------- Validate -------------
$dockVer   = Get-DockerVersion
$psLines   = Get-Containers
$hasQdrant = ($psLines -match 'qdrant').Count -gt 0

$apiHealth = Get-Http  'http://127.0.0.1:8000/health'
$apiChat   = Post-Json 'http://127.0.0.1:8000/chat' @{ message='ping' }
$redisOK   = TcpOK '127.0.0.1' 6379
$qdrantOK  = $true
if ($EnableRAG -and $hasQdrant) { $qdrantOK = TcpOK '127.0.0.1' 6333 }

# CHAT_ECHO single-line check
$chatEchoState = 'Not set (good)'
try{
  $cfg2  = docker compose config 2>$null
  $line  = ($cfg2 -split "`r?`n" | ? { $_ -match '^\s*CHAT_ECHO:\s*' } | select -First 1)
  if ($line) {
    $m = [regex]::Match($line, "^\s*CHAT_ECHO:\s*(?<v>""|''|[^#\r\n]+)")
    $raw = $m.Groups['v'].Value.Trim()
    $norm = $raw.Trim('"',"'").Trim()
    if (-not [string]::IsNullOrWhiteSpace($norm)) { $chatEchoState = "Found value '$norm' (warn)" }
  }
} catch { $chatEchoState = 'Unknown (compose config unavailable)' }

# Print
Say '===== VALIDATION SUMMARY =====' Cyan
Say ("[API] /health :: {0}" -f $apiHealth)
Say ("[API] /chat   :: {0}" -f $apiChat)
$psLines | Select-String 'chill_api|chill_ui|redis|qdrant' | % { Say $_.Line }
Say ("[Docker] Engine :: {0}" -f $dockVer)
if ($chatEchoState -like 'Found*') { Say "[Env] CHAT_ECHO :: $chatEchoState" Yellow } else { Say "[Env] CHAT_ECHO :: $chatEchoState" Green }
Say ("[Infra] redis:6379  ::  " + ($(if($redisOK){'OK'}else{'FAIL'})))
if ($EnableRAG) {
  if ($hasQdrant) { Say ("[Infra] qdrant:6333 ::  " + ($(if($qdrantOK){'OK'}else{'FAIL'}))) }
  else { Say '[Infra] qdrant:6333 :: SKIPPED (no container)' DarkYellow }
} else {
  Say '[Infra] qdrant:6333 :: SKIPPED (-EnableRAG not set)' DarkGray
}
if (-not $IgnoreOllama) {
  try {
    $oll = Invoke-WebRequest -Uri 'http://host.docker.internal:11434/api/tags' -TimeoutSec $TimeoutSec
    Say "[Ollama] tags :: $($oll.StatusCode)"
  } catch { Say "[Ollama] tags :: ERROR $($_.Exception.Message)" DarkYellow }
} else {
  Say '[Ollama] probe :: SKIPPED (-IgnoreOllama)' DarkGray
}
Say '===== END VALIDATION ====='

# Decide
$apiOk       = ($apiHealth -eq 200)
$chatOk      = ($apiChat -in 200,201,204)
$echoBad     = ($chatEchoState -like 'Found*')
$uiUnhealthy = ($psLines -match 'chill_ui\s+.*unhealthy').Count -gt 0
$redisBad    = -not $redisOK
$qdrantBad   = ($EnableRAG -and $hasQdrant -and (-not $qdrantOK))

if ($apiOk -and $chatOk -and -not $echoBad -and -not $uiUnhealthy -and -not $redisBad -and -not $qdrantBad) {
  Say 'TRAFFIC LIGHT: GREEN' Green
  Say "`nRCA:"; Say '- API/UI healthy; Redis OK; CHAT_ECHO neutral; Qdrant optional; Ollama non-blocking.'
  exit 0
} else {
  Say 'TRAFFIC LIGHT: AMBER/RED (Needs review)' Yellow
  if (-not $apiOk)      { Say '- API /health not 200' Yellow }
  if (-not $chatOk)     { Say '- API /chat not OK' Yellow }
  if ($echoBad)         { Say '- CHAT_ECHO still set' Yellow }
  if ($uiUnhealthy)     { Say '- UI unhealthy' Yellow }
  if ($redisBad)        { Say '- Redis unreachable' Yellow }
  if ($qdrantBad)       { Say '- Qdrant unreachable' Yellow }
  exit 1
}
