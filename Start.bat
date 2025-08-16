@echo off
REM One-click launcher for ChillChill
REM Usage examples:
REM   Start.bat
REM   Start.bat --PullLatest
REM   Start.bat --NoWarmup

set SCRIPT_DIR=%~dp0
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%start-chillchill.ps1" %*