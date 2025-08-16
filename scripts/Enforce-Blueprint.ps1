param([string]$Root = (Resolve-Path ".").Path)

$ErrorActionPreference = "Stop"
$bp = Join-Path $Root "docs\blueprint\BLUEPRINT.md"
$changed = git diff --cached --name-only | Out-String
$trigger = $false

$patterns = @(
  "^docker-compose.*\.ya?ml$",
  "^chatbot/agent-api/.*",
  "^chatbot/chatbot-ui/.*",
  "^\.env$",
  "^Caddyfile$",
  "^scripts/.*"
)

foreach($line in ($changed -split "`n")){
  $l = $line.Trim()
  if (-not $l) { continue }
  foreach($p in $patterns){
    if ($l -match $p) { $trigger = $true; break }
  }
  if ($trigger) { break }
}

if (-not $trigger) { exit 0 }

# If triggered, require BP update in index
$staged = git diff --cached --name-only -- "docs/blueprint/BLUEPRINT.md" | Out-String
if (-not $staged.Trim()) {
  Write-Error "Blueprint must be regenerated and staged. Run: pwsh -File scripts/Generate-Blueprint.ps1, then git add docs/blueprint/BLUEPRINT.md"
  exit 1
}
exit 0
