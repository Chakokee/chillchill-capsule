# === Operator Profile Guard (auto-generated) ===
$ErrorActionPreference = "Stop"
powershell -ExecutionPolicy Bypass -File C:\AiProject\scripts\Load-OperatorConfig.ps1

$fp = Get-Content "C:\AiProject\mode\dev.fingerprint.json" -Raw | ConvertFrom-Json
@($fp.paths.root, $fp.paths.ui, $fp.paths.api, $fp.paths.scripts) | ForEach-Object {
  if (-not (Test-Path $_)) { throw "Missing path from Operator Profile: $_" }
}

# Block open RCAs (simplest rule)
if (Test-Path "C:\AiProject\logs\RCA") {
  $open = Get-ChildItem "C:\AiProject\logs\RCA" -Recurse -Filter "RCA.md" -ErrorAction SilentlyContinue |
          ForEach-Object { Get-Content $_ -Raw } | Select-String "Status:\s*Draft"
  if ($open) { throw "Open RCA found → close/prevent before build." }
}

# Lint/Type gate + API health + next.config.js sanity
Push-Location $fp.paths.ui
if (Test-Path "package.json") {
  npm ci
  if (Test-Path "package.json") { npm run type-check }
  if (Test-Path "package.json") { npm run lint }
}
Pop-Location

try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 http://localhost:8000/health | Out-Null } catch { throw "API /health not responding" }

$cfg = Get-Content (Join-Path $fp.paths.ui "next.config.js") -Raw
if ($cfg -notmatch "api:8000") { throw "next.config.js proxy missing → api:8000" }

Write-Host "Preflight OK"
# === End Guard ===
