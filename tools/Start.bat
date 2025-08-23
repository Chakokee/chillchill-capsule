@echo off
setlocal enabledelayedexpansion

:: === Admin check (self-elevate) ===
net session >nul 2>&1
if %errorlevel% NEQ 0 (
  echo Requesting Administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

:: === Config ===
set "PROJECT_DIR=C:\AiProject"

:: === Find PowerShell 7 (pwsh) ===
set "PWSH="
for /f "delims=" %%I in ('where pwsh 2^>nul') do ( set "PWSH=%%I" & goto :foundpwsh )
if not defined PWSH set "PWSH=C:\Program Files\PowerShell\7\pwsh.exe"
:foundpwsh
if not exist "%PWSH%" (
  echo ERROR: PowerShell 7 (pwsh) not found. Install from https://aka.ms/powershell
  pause
  exit /b 1
)

:: === Run start-all.ps1 ===
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -Command ^
  "Set-Location '%PROJECT_DIR%'; .\start-all.ps1 -OpenUI -Warmup"

set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" (
  echo.
  echo Start script returned errorlevel %ERR%.
  echo Check Docker Desktop and logs: docker compose logs -n 200
)
echo.
pause
exit /b %ERR%
