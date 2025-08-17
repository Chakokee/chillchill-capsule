@echo off
setlocal
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" & exit /b)
set "PROJECT_DIR=C:\AiProject"

for /f "delims=" %%I in ('where pwsh 2^>nul') do (set "PWSH=%%I" & goto :pw)
if not defined PWSH set "PWSH=C:\Program Files\PowerShell\7\pwsh.exe"
:pw
if not exist "%PWSH%" (echo ERROR: PowerShell 7 not found.& pause & exit /b 1)

"%PWSH%" -NoProfile -ExecutionPolicy Bypass -Command "Set-Location '%PROJECT_DIR%'; if (Test-Path .\stop-all.ps1) { .\stop-all.ps1 } else { docker compose down }"
set ERR=%ERRORLEVEL%
echo.& if not "%ERR%"=="0" echo Stop returned %ERR%.
pause
exit /b %ERR%
