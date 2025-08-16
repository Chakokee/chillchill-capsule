param(
  [string]$OutDir = "C:\AiProject\diag_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
)
New-Item $OutDir -ItemType Directory -Force | Out-Null
docker version                        *> (Join-Path $OutDir 'docker_version.txt')
docker info                           *> (Join-Path $OutDir 'docker_info.txt')
Set-Location C:\AiProject
docker compose ps                     *> (Join-Path $OutDir 'compose_ps.txt')
docker compose logs -n 400 --no-color *> (Join-Path $OutDir 'compose_logs.txt')
wsl -l -v                              > (Join-Path $OutDir 'wsl_list.txt')
Get-ChildItem Env:\DOCKER_*            > (Join-Path $OutDir 'docker_env.txt')
Compress-Archive -Path ($OutDir+'\*') -DestinationPath ($OutDir+'.zip') -Force
Write-Host "Diagnostics saved to $OutDir.zip" -ForegroundColor Green
