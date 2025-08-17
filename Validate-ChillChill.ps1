# Save & run: C:\AiProject\Validate-ChillChill.ps1  (full replacement)
param(
  [string]$Root="C:\AiProject",
  [string]$ApiService="api",
  [string]$UiService="ui",
  [int]$TimeoutSec=8
)
$ErrorActionPreference="Stop"
if(!(Test-Path $Root)){ throw "Root not found: " + $Root }
if(!(Test-Path "$Root\logs")){ New-Item -ItemType Directory -Path "$Root\logs" | Out-Null }

# Results collector
$results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$Check,[bool]$Ok,[string]$Detail){
  $results.Add([pscustomobject]@{ Check=$Check; Status= if($Ok){"PASS"}else{"FAIL"}; Detail=$Detail })
}

# Compose command
function Get-ComposeCmd {
  $cmd=@("docker","compose")
  try{ & $cmd 'version' *> $null; return $cmd }catch{}
  if(Get-Command docker-compose -ErrorAction SilentlyContinue){ return @("docker-compose") }
  throw "Docker Compose not available on PATH."
}

# No-proxy HttpClient
function New-NoProxyClient([int]$timeoutSec){
  $h = New-Object System.Net.Http.HttpClientHandler
  $h.UseProxy = $false
  $h.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
  $c = New-Object System.Net.Http.HttpClient($h)
  $c.Timeout = [TimeSpan]::FromSeconds($timeoutSec)
  return $c
}

# Get service container ID
function SafeId($compose,$svc){
  try{
    $raw = & $compose 'ps' '-q' $svc 2>$null
    if($null -eq $raw){ return "" }
    return ("{0}" -f $raw).Trim()
  } catch { return "" }
}

# Publish -> 127.0.0.1:url
function Get-Url($compose,$svc,[int]$port){
  try{
    $raw = & $compose 'port' $svc ("{0}" -f $port) 2>$null
    if([string]::IsNullOrWhiteSpace($raw)){ return "http://127.0.0.1:$port" }
    # docker compose port commonly returns 0.0.0.0:PORT
    $map = ("{0}" -f $raw).Trim() -split "`r?`n" | Select-Object -First 1
    $host,$p = $map -split ":",2
    if([string]::IsNullOrWhiteSpace($p)){ $p=$port }
    return "http://127.0.0.1:{0}" -f $p
  }catch{ return "http://127.0.0.1:$port" }
}

# Simple port probe
function Probe-Port([string]$Target,[int]$Port,[int]$Timeout=10){
  $t0=Get-Date
  while((Get-Date)-$t0 -lt ([TimeSpan]::FromSeconds($Timeout))){
    try{
      $ok = (Test-NetConnection -ComputerName $Target -Port $Port -WarningAction SilentlyContinue).TcpTestSucceeded
      if($ok){ return $true }
    }catch{}
    Start-Sleep -Milliseconds 300
  }
  return $false
}

$compose = Get-ComposeCmd
Push-Location $Root
try{
  # Service presence
  $apiId = SafeId $compose $ApiService
  $uiId  = SafeId $compose $UiService
  if([string]::IsNullOrWhiteSpace($apiId)){ Add-Result "Compose services" $false ("API '"+$ApiService+"' not found or stopped") }
  if([string]::IsNullOrWhiteSpace($uiId )){ Add-Result "Compose services" $false ("UI  '"+$UiService+"' not found or stopped") }

  # API state
  if($apiId -ne ""){
    $apiState=(docker inspect -f '{{.State.Status}}' $apiId 2>$null)
    Add-Result "API container state" ($apiState -match 'running') ("State="+$apiState)

    # Env
    try{
      $envJson=(docker inspect --format '{{json .Config.Env }}' $apiId)
      $env=@{}; foreach($kv in (ConvertFrom-Json $envJson)){ if($kv -match '^(.*?)=(.*)$'){ $env[$Matches[1]]=$Matches[2] } }
      $prov=$env['LLM_PROVIDER']; $model=$env['LLM_MODEL']; $echo=$env['CHAT_ECHO']
      $echoOff = [string]::IsNullOrWhiteSpace($echo) -or $echo -match '^(0|false|off)$'
      Add-Result "Provider env" ([bool]$prov -and [bool]$model) ("LLM_PROVIDER="+$prov+"; LLM_MODEL="+$model)
      Add-Result "CHAT_ECHO disabled" $echoOff ("CHAT_ECHO='"+($echo)+"'")
    }catch{ Add-Result "Provider env" $false "Failed to read env" }
  }

  # Redis/vector (optional)
  foreach($svc in @('redis','vector')){
    try{
      $sid = SafeId $compose $svc
      if($sid -ne ""){
        $state=(docker inspect -f '{{.State.Health.Status}}' $sid 2>$null)
        if(-not $state){ $state=(docker inspect -f '{{.State.Status}}' $sid 2>$null) }
        Add-Result "Service $svc" ($state -match 'healthy|running') ("State="+$state)
      }
    }catch{}
  }

  # Build base URLs on 127.0.0.1 explicitly
  $apiBase = Get-Url $compose $ApiService 8000
  $uiBase  = Get-Url $compose $UiService 3000

  # Quick port probes first (stays proxy-free)
  $apiPortNum = [int](([Uri]$apiBase).Port)
  $uiPortNum  = [int](([Uri]$uiBase).Port)
  $apiOpen = Probe-Port -Target "127.0.0.1" -Port $apiPortNum -Timeout 8
  $uiOpen  = Probe-Port -Target "127.0.0.1" -Port $uiPortNum  -Timeout 8

  # Proxy-free HTTP checks via HttpClient
  $client = New-NoProxyClient -timeoutSec $TimeoutSec
  try{
    $r = $client.GetAsync("$apiBase/health").GetAwaiter().GetResult()
    $ok = ([int]$r.StatusCode) -ge 200 -and ([int]$r.StatusCode) -lt 400
    Add-Result "API /health" $ok ("HTTP "+[int]$r.StatusCode+" at "+$apiBase+"/health")
  }catch{ Add-Result "API /health" $false $_.Exception.Message }

  try{
    $body = New-Object System.Net.Http.StringContent('{"message":"Say ok once.","use_rag":false}',[Text.Encoding]::UTF8,"application/json")
    $r2 = $client.PostAsync("$apiBase/chat",$body).GetAwaiter().GetResult()
    $ok2 = ([int]$r2.StatusCode) -ge 200 -and ([int]$r2.StatusCode) -lt 400
    Add-Result "API /chat (autoswitch)" $ok2 ("HTTP "+[int]$r2.StatusCode+" at "+$apiBase+"/chat")
  }catch{ Add-Result "API /chat (autoswitch)" $false $_.Exception.Message }

  try{
    $r3 = $client.GetAsync("$uiBase/").GetAwaiter().GetResult()
    $ok3 = ([int]$r3.StatusCode) -ge 200 -and ([int]$r3.StatusCode) -lt 400
    Add-Result "UI reachable" $ok3 ("HTTP "+[int]$r3.StatusCode+" at "+$uiBase)
  }catch{ Add-Result "UI reachable" $false $_.Exception.Message }

}finally{ Pop-Location }

# Output table
$results | Sort-Object { if($_.Status -eq 'FAIL'){0}else{1} } | Format-Table -AutoSize

# Traffic light + RCA
$fail = @($results | Where-Object Status -eq 'FAIL')
$light = if($fail.Count -gt 0){"RED"} else {"GREEN"}

$rca = @()
if(($results | Where-Object { $_.Check -eq 'Compose services' -and $_.Detail -like 'API*not found*' }).Count -gt 0){ $rca += "API container missing or stopped; compose did not start api." }
if(($results | Where-Object { $_.Check -eq 'Compose services' -and $_.Detail -like 'UI*not found*' }).Count -gt 0){  $rca += "UI container missing or stopped; compose did not start ui." }
if(($results | Where-Object { $_.Check -eq 'API container state' -and $_.Status -eq 'PASS' }).Count -gt 0 -and
   ($results | Where-Object { $_.Check -eq 'API /health' -and $_.Status -eq 'FAIL' }).Count -gt 0){
  $rca += "API running but HTTP failing; check published port and service binding."
}
if(($results | Where-Object { $_.Check -eq 'UI reachable' -and $_.Status -eq 'FAIL' }).Count -gt 0){
  $rca += "UI not reachable; port 3000 not published or UI not started."
}
if(($results | Where-Object { $_.Check -eq 'Provider env' -and $_.Status -eq 'FAIL' }).Count -gt 0){
  $rca += "Provider variables missing; set LLM_PROVIDER and LLM_MODEL."
}
if(($results | Where-Object { $_.Check -eq 'CHAT_ECHO disabled' -and $_.Status -eq 'FAIL' }).Count -gt 0){
  $rca += "CHAT_ECHO still enabled; set to empty or false."
}
if($rca.Count -eq 0){ $rca += "No additional RCA beyond table above." }

$summary = [pscustomobject]@{ light=$light; failures=@($fail.Check); rca=$rca; results=$results }
$summary | ConvertTo-Json -Depth 6 | Out-File -Encoding UTF8 "$Root\logs\verify-summary.json"

Write-Host ""
Write-Host ("TRAFFIC LIGHT: " + $light)
Write-Host ("RCA: " + ($rca -join " | "))
