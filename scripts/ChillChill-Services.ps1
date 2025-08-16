# C:\AiProject\scripts\ChillChill-Services.ps1
[CmdletBinding()]
param(
  [Parameter()][ValidateSet('Start','Stop','Restart','FixEngine')]
  [string]$Action = 'Start',
  [switch]$OpenUI,
  [switch]$ApiDownshift
)

$ErrorActionPreference = 'Stop'

# ---- Config ----
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = 'C:\AiProject' }

$LogDir   = Join-Path $ProjectRoot 'logs'
$ApiBase  = 'http://127.0.0.1:8000'
$UiUrl    = 'http://localhost:3000'

$ServicesBuild = @('agent-api','chatbot-ui')
$ServicesUp    = @('agent-api','chatbot-ui')   # add 'ollama' if you want to manage it here too

# ---------- Helpers ----------

function Rotate-Logs {
  [CmdletBinding()]
  param([string]$Dir, [int]$Days = 30)
  if (Test-Path -LiteralPath $Dir) {
    Get-ChildItem -LiteralPath $Dir -File -ErrorAction SilentlyContinue |
      Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$Days) } |
      Remove-Item -Force -ErrorAction SilentlyContinue
  }
}

function Compose-Run {
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)] [string[]]$Args,   # e.g. @('compose','up','-d','agent-api','chatbot-ui')
    [string]$Tag = 'compose',
    [switch]$Tee   # show console + log; default writes quietly to file
  )

  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker CLI not found in PATH."
  }

  if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
  }

  Rotate-Logs -Dir $LogDir -Days 30

  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $log   = Join-Path $LogDir ("{0}_{1}.log" -f $Tag, $stamp)

  Write-Host "[compose] docker $($Args -join ' ') -> $log"
  if ($Tee) {
    docker @Args 2>&1 | Tee-Object -FilePath $log
  } else {
    docker @Args *>&1 | Out-File -FilePath $log -Encoding UTF8
  }

  if ($LASTEXITCODE -ne 0) { throw "[compose] failed ($LASTEXITCODE). See $log" }
  return $log
}

function Wait-HttpOk {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Url,
    [int]$TimeoutSec = 120,
    [int]$IntervalSec = 2
  )
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  do {
    try {
      Invoke-RestMethod -Method Get -Uri $Url -TimeoutSec 5 > $null
      return $true
    } catch {
      Start-Sleep -Seconds $IntervalSec
    }
  } while ((Get-Date) -lt $deadline)
  throw "Timeout waiting for $Url"
}

function Get-RagStats {
  [CmdletBinding()]
  param([string]$ApiBaseUrl = $script:ApiBase)
  try {
    $resp = Invoke-RestMethod -Method Get -Uri "$ApiBaseUrl/rag/stats" -TimeoutSec 5
    if ($null -ne $resp.count) {
      Write-Host ("[RAG] Document count: {0}" -f $resp.count) -ForegroundColor Green
      return [int]$resp.count
    } else {
      Write-Host "[RAG] /rag/stats returned unexpected schema." -ForegroundColor Yellow
    }
  } catch {
    Write-Host "[RAG] /rag/stats not available (skipping)" -ForegroundColor Yellow
  }
  return $null
}

function Invoke-FixEngine {
  [CmdletBinding()]
  param([int]$WaitSec = 180, [switch]$ApiDownshift)

  Write-Host "[FixEngine] Restarting Docker Desktop + WSL..." -ForegroundColor Cyan

  # Clear any overrides that confuse Desktop
  Remove-Item Env:DOCKER_HOST, Env:DOCKER_API_VERSION -ErrorAction SilentlyContinue
  docker context use desktop-linux | Out-Null

  # Restart Desktop + WSL backend
  & "$Env:ProgramFiles\Docker\Docker\Docker Desktop.exe" --shutdown | Out-Null
  wsl --shutdown | Out-Null
  Start-Sleep -Seconds 3
  Start-Process "$Env:ProgramFiles\Docker\Docker\Docker Desktop.exe" | Out-Null

  # Wait for the Linux engine pipe
  $deadline = (Get-Date).AddSeconds($WaitSec)
  while (-not (Test-Path '\\.\pipe\dockerDesktopLinuxEngine') -and (Get-Date) -lt $deadline) { Start-Sleep 2 }
  if (-not (Test-Path '\\.\pipe\dockerDesktopLinuxEngine')) { throw "[FixEngine] Pipe not available after $WaitSec sec." }

  if ($ApiDownshift) {
    $env:DOCKER_API_VERSION = "1.43"
    Write-Host "[FixEngine] Client API downshift -> 1.43 (session only)" -ForegroundColor Yellow
  }

  # Final sanity (throws on failure)
  docker info -ErrorAction Stop > $null 2>&1

  Write-Host "[FixEngine] Engine healthy." -ForegroundColor Green
  return $true
}

# ---------- Actions ----------

switch ($Action) {
  'FixEngine' {
    Invoke-FixEngine -ApiDownshift:$ApiDownshift | Out-Null
    break
  }

  'Start' {
    Push-Location $ProjectRoot
    try {
      Compose-Run -Args (@('compose','build') + $ServicesBuild) -Tag 'compose_build' | Out-Null
      Compose-Run -Args (@('compose','up','-d') + $ServicesUp) -Tag 'compose_up' | Out-Null

      Write-Host "[health] Waiting for $ApiBase/health..." -ForegroundColor Cyan
      Wait-HttpOk -Url "$ApiBase/health" -TimeoutSec 120 | Out-Null

      Get-RagStats -ApiBaseUrl $ApiBase | Out-Null
      if ($OpenUI) { Start-Process $UiUrl | Out-Null }
    } finally {
      Pop-Location
    }
    break
  }

  'Restart' {
    Push-Location $ProjectRoot
    try {
      Compose-Run -Args @('compose','down','--remove-orphans') -Tag 'compose_down' | Out-Null
      Compose-Run -Args (@('compose','build') + $ServicesBuild) -Tag 'compose_build' | Out-Null
      Compose-Run -Args (@('compose','up','-d') + $ServicesUp) -Tag 'compose_up' | Out-Null

      Write-Host "[health] Waiting for $ApiBase/health..." -ForegroundColor Cyan
      Wait-HttpOk -Url "$ApiBase/health" -TimeoutSec 120 | Out-Null

      Get-RagStats -ApiBaseUrl $ApiBase | Out-Null
      if ($OpenUI) { Start-Process $UiUrl | Out-Null }
    } finally {
      Pop-Location
    }
    break
  }

  'Stop' {
    Push-Location $ProjectRoot
    try {
      Compose-Run -Args @('compose','down','--remove-orphans') -Tag 'compose_down' | Out-Null
    } finally {
      Pop-Location
    }
    break
  }
}
