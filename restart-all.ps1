[CmdletBinding()]
param(
  [string]$Root = "C:\AiProject",
  [switch]$OpenUI
)
pwsh -ExecutionPolicy Bypass -File (Join-Path $Root "stop-all.ps1")
pwsh -ExecutionPolicy Bypass -File (Join-Path $Root "start-all.ps1") -OpenUI:$OpenUI
