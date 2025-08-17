@echo off
REM One-click shutdown for ChillChill
REM Usage examples:
REM   Stop.bat
REM   Stop.bat --CleanupVolumes

set SCRIPT_DIR=%~dp0
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%stop-chillchill.ps1" %*
