# Install-PrecommitGuard.ps1 (simple)
[CmdletBinding()]
param(
  [string]$RepoRoot   = "C:\AiProject",
  [string]$GateScript = "GuardAndSmoke.ps1"
)
$ErrorActionPreference = 'Stop'
Set-Location $RepoRoot
if (-not (Test-Path ".git")) { git init | Out-Null }

$hookPath = Join-Path ".git\hooks" "pre-commit"
$gateAbs  = Join-Path $RepoRoot $GateScript
$hookBody = @"
#!/usr/bin/env bash
pwsh -NoLogo -NoProfile -File "$gateAbs" -NoPause
exit \$?
"@
[System.IO.File]::WriteAllText($hookPath, $hookBody, [System.Text.Encoding]::UTF8)
Write-Host "Installed pre-commit → $hookPath"
