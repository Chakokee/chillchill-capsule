# Validate-ChillChill.ps1
# End-to-end health & conformance check for ChillChill. Produces RCA + TRAFFIC LIGHT.
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
  # Severity: 0=PASS, 1=WARN, 2=FAIL
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
Add-Check "API dir" ((Test-Path $apiDir) ? "PASS" : "FAIL") $apiDir ((Test-Path $apiDir) ? 0 : 2)
Add-Check "UI dir"  ((Test-Path $uiDir)  ? "PASS" : "FAIL") $uiDir  ((Test-Path $uiDir)  ? 0 : 2)

# --- Runtime ---
$h = Test-Http "$ApiUrl/health"
Add-Check "API /health" ($h.Ok ? "PASS" : "FAIL") ("HTTP {0}" -f $h.Code) (($h.Ok) ? 0 : 2)
$c = Test-Http "$ApiUrl/chat" "POST" '{"message":"ok","use_rag":false}'
Add-Check "API /chat (autoswitch)" ($c.Ok ? "PASS" : "FAIL") ("HTTP {0}" -f $c.Code) (($c.Ok) ? 0 : 2)
$u = Test-Http $UiUrl
Add-Check "UI reachable" ($u.Ok ? "PASS" : "FAIL") ("HTTP {0}" -f $u.Code) (($u.Ok) ? 0 : 2)

# --- Env from container ---
$apiC  = GetApiContainer
$prov  = ReadVar $apiC "LLM_PROVIDER"
$model = ReadVar $apiC "LLM_MODEL"
$echo  = ReadVar $apiC "CHAT_ECHO"
$noPx  = ReadVar $apiC "NO_PROXY"

Add-Check "API container" (([string]::IsNullOrEmpty($apiC)) ? "WARN" : "PASS") (Coalesce $apiC "<none>") (([string]::IsNullOrEmpty($apiC)) ? 1 : 0)
$provDetail = "LLM_PROVIDER={0}; LLM_MODEL={1}" -f (Coalesce $prov "<null>"), (Coalesce $model "<null>")
Add-Check "Provider env" ((-not [string]::IsNullOrEmpty($prov)) -and (-not [string]::IsNullOrEmpty($model)) ? "PASS" : "WARN") $provDetail (((-not [string]::IsNullOrEmpty($prov)) -and (-not [string]::IsNullOrEmpty($model))) ? 0 : 1)
$echoDetail = "CHAT_ECHO='{0}'" -f (Coalesce $echo "<null>")
Add-Check "CHAT_ECHO disabled" (($echo -eq "false") ? "PASS" : "FAIL") $echoDetail (($echo -eq "false") ? 0 : 2)
$noPxDetail = "NO_PROXY='{0}'" -f (Coalesce $noPx "<null>")
Add-Check "NO_PROXY present" ((-not [string]::IsNullOrEmpty($noPx)) ? "PASS" : "WARN") $noPxDetail ((-not [string]::IsNullOrEmpty($noPx)) ? 0 : 1)

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
    Add-Check "Autoswitch order" ($okOrder ? "PASS" : "FAIL") ("order=$order") (($okOrder) ? 0 : 2)
    Add-Check "Personas mapping" ($okPersona ? "PASS" : "FAIL") ("GP=$gp; Chef=$chef; Accountant=$accP/$accM") (($okPersona) ? 0 : 2)
  }catch{
    Add-Check "providers.json parse" "FAIL" $_.Exception.Message 2
  }
}else{
  Add-Check "providers.json present" "FAIL" "$provCfg not found" 2
}

# --- Compose override & repo hygiene ---
$ovr = Join-Path $Root "docker-compose.override.yml"
if(Test-Path $ovr){
  $t = Get-Content $ovr -Raw
  $hasEcho = ($t -match "CHAT_ECHO=false")
  $hasNoPx = (($t -match "NO_PROXY=") -or ($t -match "no_proxy="))
  Add-Check "Override CHAT_ECHO=false" ($hasEcho ? "PASS" : "WARN") ("exists=$hasEcho") ($hasEcho ? 0 : 1)
  Add-Check "Override NO_PROXY" ($hasNoPx ? "PASS" : "WARN") ("exists=$hasNoPx") ($hasNoPx ? 0 : 1)
}else{
  Add-Check "override file" "WARN" "$ovr missing" 1
}
Add-Check ".gitattributes present" ((Test-Path ".gitattributes") ? "PASS" : "WARN") (Test-Path ".gitattributes") ((Test-Path ".gitattributes") ? 0 : 1)
$bp = "docs\blueprint\BLUEPRINT.md"
Add-Check "Blueprint canonical" ((Test-Path $bp) ? "PASS" : "WARN") $bp ((Test-Path $bp) ? 0 : 1)

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
