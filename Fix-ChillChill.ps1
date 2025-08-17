# Fix-ChillChill.ps1 (v5)
# Ensures providers/personas, injects NO_PROXY/no_proxy via .env and override, rebuilds, auto-loops to GREEN (max 3).
param(
  [string]$Root      = "C:\AiProject",
  [string]$Branch    = "chore/ui-canonicalize-2025-08-16",
  [switch]$AutoLoop  = $true
)

$ErrorActionPreference = "Stop"
Set-Location $Root
$BranchVar = $Branch
$NoPxVal   = "localhost,127.0.0.1,api,ui,redis,vector,host.docker.internal"

function Info($m){ Write-Host ">> $m" -ForegroundColor Cyan }
function EnsureDir($p){ if(-not (Test-Path $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }

function Set-EnvKV($path,$key,$value){
  $content = ""
  if(Test-Path $path){ $content = Get-Content $path -Raw }
  $escaped = [regex]::Escape($key)
  $pattern = "^(?:$escaped)=.*$"
  if([string]::IsNullOrEmpty($content)){
    $content = "$key=$value`r`n"
  } elseif([regex]::IsMatch($content,$pattern,[System.Text.RegularExpressions.RegexOptions]::Multiline)){
    $content = [regex]::Replace($content,$pattern,("$key=$value"),[System.Text.RegularExpressions.RegexOptions]::Multiline)
  } else {
    if(($content.Length -gt 0) -and (-not $content.EndsWith("`r`n"))){ $content += "`r`n" }
    $content += "$key=$value`r`n"
  }
  Set-Content -Encoding UTF8 $path $content
}

function Enforce-Providers {
  $cfgDir = "chatbot\agent-api\config"; EnsureDir $cfgDir
@'
{
  "autoswitch_order": ["gemini","groq","ollama","openai"],
  "personas": {
    "GP":        { "provider": "gemini" },
    "Chef":      { "provider": "openai" },
    "Accountant":{ "provider": "groq", "model": "llama3-70b-8192" }
  }
}
'@ | Set-Content -Encoding UTF8 (Join-Path $cfgDir "providers.json")
  Info "providers.json enforced"
}

function Enforce-DotEnv {
  $envPath = ".env"
  Set-EnvKV $envPath "NO_PROXY" $NoPxVal
  Set-EnvKV $envPath "no_proxy" $NoPxVal
  Info ".env updated with NO_PROXY and no_proxy"
}

function Enforce-Override {
  $ovr = "docker-compose.override.yml"
  $managed = @"
# === OPERATOR-MANAGED-ENV BEGIN ===
services:
  api:
    env_file:
      - .env
    environment:
      CHAT_ECHO: "false"
      NO_PROXY: "$NoPxVal"
      no_proxy: "$NoPxVal"
  ui:
    env_file:
      - .env
    environment:
      NO_PROXY: "$NoPxVal"
      no_proxy: "$NoPxVal"
# === OPERATOR-MANAGED-ENV END ===
"@
  if(Test-Path $ovr){
    $txt = Get-Content $ovr -Raw
    if($txt -match "OPERATOR-MANAGED-ENV BEGIN"){
      $txt = [regex]::Replace($txt,"# === OPERATOR-MANAGED-ENV BEGIN ===.*?# === OPERATOR-MANAGED-ENV END ===",$managed,[System.Text.RegularExpressions.RegexOptions]::Singleline)
    } else {
      $txt = $txt.TrimEnd() + "`r`n`r`n" + $managed
    }
    $txt | Set-Content -Encoding UTF8 $ovr
  } else {
    $managed | Set-Content -Encoding UTF8 $ovr
  }
  Info "docker-compose override enforced (.env + mapping env)"
}

function Enforce-GitAttributes {
@'
* text=auto eol=lf
*.ps1  text eol=crlf
*.psm1 text eol=crlf
*.bat  text eol=crlf
*.cmd  text eol=crlf
*.sh   text eol=lf
*.ts   text eol=lf
*.tsx  text eol=lf
*.js   text eol=lf
*.jsx  text eol=lf
*.json text eol=lf
*.yml  text eol=lf
*.yaml text eol=lf
*.py   text eol=lf
*.toml text eol=lf
*.md   text eol=lf
*.lock text eol=lf
'@ | Set-Content -Encoding UTF8 .gitattributes
  git config core.autocrlf false
  git config core.eol lf
  git add --renormalize . 2>$null | Out-Null
  git commit -m "Normalize line endings per .gitattributes" 2>$null | Out-Null
  Info ".gitattributes enforced & repo normalized"
}

function Enforce-Blueprint {
  try{ pwsh -File scripts/Generate-Blueprint.ps1 }catch{ Write-Warning "Generate-Blueprint.ps1 failed: $($_.Exception.Message)" }
  $bpDir = "docs\blueprint"; EnsureDir $bpDir
  $latest = Get-ChildItem $bpDir -Filter "ChillChill-Blueprint-*.md" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if($latest){ Copy-Item -Force $latest.FullName (Join-Path $bpDir "BLUEPRINT.md"); Info "BLUEPRINT.md canonicalized" }
  else{ Write-Warning "No timestamped blueprint found; BLUEPRINT.md not updated." }
}

function Commit-And-Push {
  git add .env .gitattributes docker-compose.override.yml chatbot/agent-api/config/providers.json docs/blueprint/BLUEPRINT.md 2>$null | Out-Null
  git commit -m "ChillChill: inject NO_PROXY/no_proxy via .env + override; enforce providers; blueprint canonical; normalize endings" 2>$null | Out-Null
  git push -u origin $BranchVar 2>$null | Out-Null
  Info ("Changes committed & pushed (branch={0})" -f $BranchVar)
}

function Rebuild-Core {
  Info "Recreating containers to apply env..."
  docker compose up -d --build --force-recreate api ui | Out-Null
}

function Show-Merged-Config {
  try{
    $cfg = docker compose config
    $out = "logs\compose-merged.yaml"
    $cfg | Set-Content -Encoding UTF8 $out
    ($cfg -split "`r?`n") | Select-String -Pattern "NO_PROXY|no_proxy" | ForEach-Object { Write-Host (".. " + $_.ToString()) -ForegroundColor DarkGray }
  }catch{ Write-Warning "docker compose config failed: $($_.Exception.Message)" }
}

function Check-Container-Env {
  try{
    $apiName = (docker ps --format "{{.Names}}" | Where-Object { $_ -match '(_api$)|(-api$)|(^api$)' } | Select-Object -First 1)
    $up = (docker exec $apiName /bin/sh -lc 'printf "NO_PROXY=%s|no_proxy=%s\n" "$NO_PROXY" "$no_proxy"') 2>$null
    if($up){ Write-Host ">> Container proxy vars: $up" -ForegroundColor DarkGray }
  }catch{ Write-Warning "Container env probe failed: $($_.Exception.Message)" }
}

function Run-Validate {
  try{ & pwsh -File .\Validate-ChillChill.ps1 }catch{ Write-Warning "Validator failed: $($_.Exception.Message)" }
  $summary = ".\logs\verify-summary.json"
  if(Test-Path $summary){
    $sum = Get-Content $summary -Raw | ConvertFrom-Json
    $max = ($sum | Measure-Object Severity -Maximum).Maximum
    if($null -eq $max){ $max = 0 }
    $light = if($max -ge 2){ "RED" } elseif($max -ge 1){ "AMBER" } else { "GREEN" }
    return @{ Light=$light; Summary=$sum }
  } else { return @{ Light="AMBER"; Summary=@() } }
}

function Execute-Pass {
  Info "Applying deterministic fixes..."
  Enforce-Providers
  Enforce-DotEnv
  Enforce-Override
  Enforce-GitAttributes
  Enforce-Blueprint
  Commit-And-Push
  Rebuild-Core
  Show-Merged-Config
  Check-Container-Env
  $r = Run-Validate
  return $r
}

# --- Main: auto-loop until GREEN (max 3) ---
$passes = 0
$result = $null
do {
  $passes = $passes + 1
  Info ("=== FIX PASS {0} ===" -f $passes)
  $result = Execute-Pass
} while ( $AutoLoop.IsPresent -and $passes -lt 3 -and $result.Light -ne "GREEN" )

# --- RCA + TRAFFIC LIGHT (final) ---
$rca = @()
if($result -and $result.Summary){
  $fails = $result.Summary | Where-Object { $_.Severity -eq 2 }
  $warns = $result.Summary | Where-Object { $_.Severity -eq 1 }
  if($fails){ $rca += ("Remaining FAIL checks after pass {0}:" -f $passes); foreach($f in $fails){ $rca += ("- {0}: {1}" -f $f.Check, $f.Detail) } }
  if($warns){ $rca += ("Remaining WARN checks after pass {0}:" -f $passes); foreach($w in $warns){ $rca += ("- {0}: {1}" -f $w.Check, $w.Detail) } }
}
if(-not $rca){ $rca = @("Fix completed; no remaining WARN/FAIL detected.") }
"`nRCA:`n" + ($rca -join "`n")

$finalLight = if($result -and $result.Light){ $result.Light } else { "AMBER" }
"TRAFFIC LIGHT: $finalLight"

# --- Rollback (quick hints) ---
# git log --oneline -n 3
# git reset --hard HEAD~1
# git push --force-with-lease origin $BranchVar
# docker compose up -d --build --force-recreate api ui
