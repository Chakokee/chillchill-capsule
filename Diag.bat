@echo off
setlocal enabledelayedexpansion

net session >nul 2>&1
if %errorlevel% NEQ 0 (
  echo Requesting Administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

set "PROJECT_DIR=C:\AiProject"

set "PWSH="
for /f "delims=" %%I in ('where pwsh 2^>nul') do ( set "PWSH=%%I" & goto :foundpwsh )
if not defined PWSH set "PWSH=C:\Program Files\PowerShell\7\pwsh.exe"
:foundpwsh
if not exist "%PWSH%" (
  echo ERROR: PowerShell 7 (pwsh) not found.
  pause & exit /b 1
)

"%PWSH%" -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ts=Get-Date -Format 'yyyyMMdd_HHmmss'; $out='C:\AiProject\diag_'+$ts; " ^
  "New-Item $out -ItemType Directory -Force | Out-Null; " ^
  "docker version                        *> (Join-Path $out 'docker_version.txt'); " ^
  "docker info                           *> (Join-Path $out 'docker_info.txt'); " ^
  "Set-Location '%PROJECT_DIR%'; docker compose ps *> (Join-Path $out 'compose_ps.txt'); " ^
  "docker compose logs -n 400 --no-color *> (Join-Path $out 'compose_logs.txt'); " ^
  "wsl -l -v                              >  (Join-Path $out 'wsl_list.txt'); " ^
  "Get-ChildItem Env:\DOCKER_*            >  (Join-Path $out 'docker_env.txt'); " ^
  "Compress-Archive -Path ($out+'\*') -DestinationPath ($out+'.zip') -Force; " ^
  "Write-Host ('Diagnostics saved to '+$out+'.zip') -ForegroundColor Green"

echo.
pause
