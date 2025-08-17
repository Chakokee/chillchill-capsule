# Validate-ChillChill.ps1 (v3)
# End-to-end health & conformance check with RCA + TRAFFIC LIGHT.
param(
  [string]$Root   = "C:\AiProject",
  [string]$ApiUrl = "http://127.0.0.1:8000",
  [string]$UiUrl  = "http://127.0.0.1:3000"
)

$ErrorActionPreference = "Stop"
Set-Location $Root
New-Item -ItemType Directory -Force -Path ".\logs" | Out-Null

# --- Helpers ---
$results = @()
function Add-Check([string]$Name,[string]$Status,[string]$Detail,[int]$Severity){
  $script:results += [pscustomobject]@{ Check=$Name; Status=$Status; Detail=$Detail; Severity=$Severity }
}
function Test-Http([string]$Url,[string]$Method="GET",[string]$Body=$null){
  try{
    if($Body){
      $r = Invoke-WebRequest -Uri $Url -Method $Method -ContentType "application/json" -Body $Body -TimeoutSec 8 -UseBasicParsing
    } else {
      $r = Invoke-WebRequest -Uri $Url -Method $Method -TimeoutSec 8 -UseBasicParsing
    }
    return @{ Ok = ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300); Code = $r.StatusCode; Detail=$r.RawContentLength }
  }catch{
    return @{ Ok = $false; Code = 0; Detail = $_.Exception.Message }
  }
}
function GetApiContainer(){
  try{
    $names = docker ps --format "{{.Names}}"
    $match = $names | Where-Object { $_ -match '(_api$)|(-api$)|(^api$)' } | Select-Object -First 1
    if([string]::IsNullOrWhiteSpace($match)) { return $null } else { return $match }
  }catch{ return $null }
}
function ReadVar($c,$v){
  if(-not $c){ return $null }
  try{ (docker exec $c printenv $v) 2>$null }catch{ $null }
}
function Coalesce($v,$fallback){ if($null -eq $v -or $v -eq ""){ $fallback } else { $v } }

# --- Paths ---
$apiDir = Join-Path $Root "chatbot\agent-api"
$uiDir  = Join-Path $Root "chatbot\chatbot-ui"
if(Test-Path $apiDir){ Add-Check "API dir" "PASS" $apiDir 0 } else { Add-Check "API dir" "FAIL" $apiDir 2 }
if(Test-Path $uiDir ){ Add-Check "UI dir"  "PASS" $uiDir  0 } else { Add-Check "UI dir"  "FAIL" $uiDir  2 }

# --- Runtime ---
$h = Test-Http "$ApiUrl/health"
if($h.Ok){ Add-Check "API /health" "PASS" ("HTTP {0}" -f $h.Code) 0 } else { Add-Check "API /health" "FAIL" ("HTTP {0}" -f $h.Code) 2 }
$c = Test-Http "$ApiUrl/chat" "POST" '{"message":"ok","use_rag":false}'
if($c.Ok){ Add-Check "API /chat (autoswitch)" "PASS" ("HTTP {0}" -f $c.Code) 0 } else { Add-Check "API /chat (autoswitch)" "FAIL" ("HTTP {0}" -f $c.Code) 2 }
$u = Test-Http $UiUrl
if($u.Ok){ Add-Check "UI reachable" "PASS" ("HTTP {0}" -f $u.Code) 0 } else { Add-Check "UI reachable" "FAIL" ("HTTP {0}" -f $u.Code) 2 }

# --- Env from container ---
$apiC  = GetApiContainer
if([string]::IsNullOrEmpty($apiC)){ Add-Check "API container" "WARN" "<none>" 1 } else { Add-Check "API container" "PASS" $apiC 0 }

$prov  = ReadVar $apiC "LLM_PROVIDER"
$model = ReadVar $apiC "LLM_MODEL"
$echo  = ReadVar $apiC "CHAT_ECHO"
$provDetail = "LLM_PROVIDER={0}; LLM_MODEL={1}" -f (Coalesce $prov "<null>"), (Coalesce $model "<null>")
if((-not [string]::IsNullOrEmpty($prov)) -and (-not [string]::IsNullOrEmpty($model))){
  Add-Check "Provider env" "PASS" $provDetail 0
} else {
  Add-Check "Provider env" "WARN" $provDetail 1
}
$echoDetail = "CHAT_ECHO='{0}'" -f (Coalesce $echo "<null>")
if($echo -eq "false"){ Add-Check "CHAT_ECHO disabled" "PASS" $echoDetail 0 } else { Add-Check "CHAT_ECHO disabled" "FAIL" $echoDetail 2 }

# --- NO_PROXY presence across sources (container, host env, .env, override) ---
$noPxU = ReadVar $apiC "NO_PROXY"
$noPxL = ReadVar $apiC "no_proxy"
$hostU = $Env:NO_PROXY
$hostL = $Env:no_proxy

$dotenvU = ""; $dotenvL = ""
if(Test-Path ".env"){
  $dotenv = Get-Content ".env" -Raw
  $m = [regex]::Match($dotenv,'(?m)^\s*NO_PROXY\s*=\s*(.+)\s*$')
  if($m.Success){ $dotenvU = $m.Groups[1].Value.Trim() }
  $m = [regex]::Match($dotenv,'(?m)^\s*no_proxy\s*=\s*(.+)\s*$')
  if($m.Success){ $dotenvL = $m.Groups[1].Value.Trim() }
}

$ovr = Join-Path $Root "docker-compose.override.yml"
$ovrText = ""; if(Test-Path $ovr){ $ovrText = Get-Content $ovr -Raw }
$ovrU = ""; $ovrL = ""
if($ovrText){
  $m = [regex]::Match($ovrText,'(?mi)^\s*NO_PROXY\s*:\s*"?([^"\r\n]+)"?')
  if($m.Success){ $ovrU = $m.Groups[1].Value.Trim() }
  $m = [regex]::Match($ovrText,'(?mi)^\s*no_proxy\s*:\s*"?([^"\r\n]+)"?')
  if($m.Success){ $ovrL = $m.Groups[1].Value.Trim() }
}

$all = @($noPxU,$noPxL,$hostU,$hostL,$dotenvU,$dotenvL,$ovrU,$ovrL) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$npDetail = "container(NO_PROXY='{0}', no_proxy='{1}'); host(NO_PROXY='{2}', no_proxy='{3}'); .env(NO_PROXY='{4}', no_proxy='{5}'); override(NO_PROXY='{6}', no_proxy='{7}')" -f `
  (Coalesce $noPxU "<null>"), (Coalesce $noPxL "<null>"), (Coalesce $hostU "<null>"), (Coalesce $hostL "<null>"), (Coalesce $dotenvU "<null>"), (Coalesce $dotenvL "<null>"), (Coalesce $ovrU "<null>"), (Coalesce $ovrL "<null>")

if($all.Count -gt 0){
  Add-Check "NO_PROXY present" "PASS" $npDetail 0
} else {
  Add-Check "NO_PROXY present" "WARN" $npDetail 1
}

# --- Config conformance ---
$provCfg = Join-Path $apiDir "config\providers.json"
if(Test-Path $provCfg){
  try{
    $cfg = Get-Content $provCfg -Raw | ConvertFrom-Json
    $order = ($cfg.autoswitch_order -join ",")
    $okOrder = ($order -eq "gemini,groq,ollama,openai")
    $gp   = $cfg.personas.GP.provider
    $chef = $cfg.personas.Chef.provider
    $accP = $cfg.personas.Accountant.provider
    $accM = $cfg.personas.Accountant.model
    $okPersona = ($gp -eq "gemini" -and $chef -eq "openai" -and $accP -eq "groq" -and $accM -eq "llama3-70b-8192")
    if($okOrder){ Add-Check "Autoswitch order" "PASS" ("order=$order") 0 } else { Add-Check "Autoswitch order" "FAIL" ("order=$order") 2 }
    if($okPersona){ Add-Check "Personas mapping" "PASS" ("GP=$gp; Chef=$chef; Accountant=$accP/$accM") 0 } else { Add-Check "Personas mapping" "FAIL" ("GP=$gp; Chef=$chef; Accountant=$accP/$accM") 2 }
  }catch{
    Add-Check "providers.json parse" "FAIL" $_.Exception.Message 2
  }
}else{
  Add-Check "providers.json present" "FAIL" "$provCfg not found" 2
}

# --- Compose override presence (defense in depth) ---
if(Test-Path $ovr){
  $t = $ovrText
  $hasEcho = ($t -match "CHAT_ECHO\s*:\s*""?false""?")
  $hasNoPx = (($t -match "(?mi)^\s*NO_PROXY\s*:") -or ($t -match "(?mi)^\s*no_proxy\s*:"))
  if($hasEcho){ Add-Check "Override CHAT_ECHO=false" "PASS" ("exists=$hasEcho") 0 } else { Add-Check "Override CHAT_ECHO=false" "WARN" ("exists=$hasEcho") 1 }
  if($hasNoPx){ Add-Check "Override NO_PROXY" "PASS" ("exists=$hasNoPx") 0 } else { Add-Check "Override NO_PROXY" "WARN" ("exists=$hasNoPx") 1 }
}else{
  Add-Check "override file" "WARN" "$ovr missing" 1
}

if(Test-Path ".gitattributes"){ Add-Check ".gitattributes present" "PASS" "$true" 0 } else { Add-Check ".gitattributes present" "WARN" "$false" 1 }
$bp = "docs\blueprint\BLUEPRINT.md"
if(Test-Path $bp){ Add-Check "Blueprint canonical" "PASS" $bp 0 } else { Add-Check "Blueprint canonical" "WARN" $bp 1 }

# --- Output & Traffic Light ---
$results | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 ".\logs\verify-summary.json"
$results | Sort-Object Severity, Check | Format-Table -AutoSize
$max = ($results | Measure-Object Severity -Maximum).Maximum
if($null -eq $max){ $max = 0 }
$light = if($max -ge 2){ "RED" } elseif($max -ge 1){ "AMBER" } else { "GREEN" }

# RCA + TRAFFIC LIGHT (bottom)
$rca = @("Validation RCA to guide Fix:")
$warnFail = $results | Where-Object { $_.Severity -ge 1 }
if($warnFail){
  foreach($row in $warnFail){ $rca += ("- {0}: {1}" -f $row.Check, $row.Detail) }
}else{
  $rca = @("All checks PASS. No Fix required.")
}
"`nRCA:`n" + ($rca -join "`n")
"TRAFFIC LIGHT: $light"
