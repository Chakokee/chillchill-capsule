[CmdletBinding()]
param([string]$Root = "C:\AiProject")

function Write-Info($msg){ Write-Host ">>> $msg" -ForegroundColor Cyan }
$compose = Join-Path $Root "docker-compose.yml"
if (!(Test-Path $compose)) { Write-Host "No compose file at $compose"; exit 0 }

Push-Location $Root
Write-Info "Stopping and removing project containers (volumes preserved)..."
docker compose down --remove-orphans
Write-Info "Done."
Pop-Location
