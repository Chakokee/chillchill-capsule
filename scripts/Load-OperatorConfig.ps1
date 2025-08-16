param(
  [string]$Json="C:\AiProject\operator\operator.config.json",
  [string]$Yaml="C:\AiProject\operator\operator.config.yaml",
  [string]$Mem ="C:\AiProject\operator\operator.memory.json",
  [string]$Out ="C:\AiProject\mode\dev.fingerprint.json"
)
$ErrorActionPreference="Stop"

function Load-Config {
  param([string]$Json,[string]$Yaml)
  if (Test-Path $Json) {
    return (Get-Content $Json -Raw | ConvertFrom-Json)
  }
  # YAML only if module exists AND file exists
  if ((Get-Module -ListAvailable -Name powershell-yaml) -and (Test-Path $Yaml)) {
    Import-Module powershell-yaml -ErrorAction Stop
    return (Get-Content $Yaml -Raw | ConvertFrom-Yaml)
  }
  throw "No config found. Expected $Json (preferred) or $Yaml (with powershell-yaml)."
}

$cfg = Load-Config -Json $Json -Yaml $Yaml

if ($cfg.schema -ne "operator.v3") { throw "Schema mismatch: $($cfg.schema)" }
if ($cfg.mode -ne "developer")    { throw "Mode must be developer" }
if (-not $cfg.guards.preflight)   { throw "guards.preflight must be true" }

# Load memory (optional)
if (Test-Path $Mem) { $mem = Get-Content $Mem -Raw | ConvertFrom-Json } else { $mem = @{} }

# Emit fingerprint JSON
$fp = [ordered]@{
  schema = "devmode.v3"
  mode = $cfg.mode
  one_step = $cfg.one_step
  risk_meter = $cfg.risk_meter
  paste_ready_code = $cfg.paste_ready_code
  paths = $cfg.paths
  docker = $cfg.docker
  network = $cfg.network
  mem = $mem
  updated_at = (Get-Date).ToString("s")
}
$fp | ConvertTo-Json -Depth 8 | Out-File $Out -Encoding utf8
Write-Host "Operator fingerprint written → $Out"
