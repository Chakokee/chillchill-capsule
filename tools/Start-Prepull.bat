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

:: Set CHILLCHILL_PREPULL only for this run
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -Command ^
  "$env:CHILLCHILL_PREPULL='1'; Set-Location '%PROJECT_DIR%'; .\start-all.ps1 -OpenUI -Warmup; Remove-Item Env:\CHILLCHILL_PREPULL -ErrorAction SilentlyContinue"

set "ERR=%ERRORLEVEL%"
echo.
pause
exit /b %ERR%
