param([string]$Root="C:\AiProject")
$compose = Join-Path $Root "docker-compose.yml"
if (!(Test-Path $compose)) { Write-Host "No compose at $compose"; exit 0 }
Push-Location $Root
docker compose ps
Write-Host "`nHealth:" -ForegroundColor Cyan
try { (Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8000/health -TimeoutSec 3).Content } catch { "unavailable" }
Write-Host "`nOllama models:" -ForegroundColor Cyan
docker compose exec -T ollama ollama list
Pop-Location
