param(
  [string]$Root="C:\AiProject",
  [string]$ApiService="api",
  [string]$UiService="ui",
  [int]$TimeoutSec=8
)
$ErrorActionPreference="Stop"

if(!(Test-Path $Root)){ throw "Root not found: $Root" }
if(!(Test-Path "$Root\logs")){ New-Item -ItemType Directory -Path "$Root\logs" | Out-Null }

# Results collector
$results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$Check,[bool]$Ok,[string]$Detail){
  $results.Add([pscustomobject]@{ Check=$Check; Status= if($Ok){"PASS"}else{"FAIL"}; Detail=$Detail })
}

function Get-ComposeCmd {
  $cmd = @("docker","compose")
  try { & $cmd 'version' *> $null; return $cmd } catch {}
  if (Get-Command docker-compose -ErrorAction SilentlyContinue) { return @("docker-compose") }
  throw "Docker Compose is not available on PATH."
}

function Normalize-Host([string]$url){
  try{
    $u = [Uri]$url
    $host = if ($u.Host -eq "0.0.0.0" -or $u.Host -eq "::" -or $u.Host -eq "::0" -or $u.Host -eq "::0.0.0.0") { "localhost" } else { $u.Host }
    return "{0}://{1}{2}" -f $u.Scheme,$host,$u.PathAndQuery
  } catch { return $url }
}

$compose = Get-ComposeCmd

Push-Location $Root
try {
  # Container IDs
  $apiId = (& $compose 'ps' '-q' $ApiService).Trim()
  $uiId  = (& $compose 'ps' '-q' $UiService).Trim()

  if(-not $apiId){ Add-Result "Compose services" $false "API container '$ApiService' not found." }
  if(-not $uiId){ Add-Result "Compose services" $false "UI container '$UiService' not found." }

  if($apiId){
    $apiState = (docker inspect -f '{{.State.Status}}' $apiId 2>$null)
    Add-Result "API container state" ($apiState -match 'running') ("State="+$apiState)

    # Build base URL
    $apiPortLine = (& $compose 'port' $ApiService '8000' 2>$null).Trim()
    $apiBase = if($apiPortLine){ "http://$apiPortLine" } else { "http://localhost:8000" }
    $apiBase = Normalize-Host $apiBase

    # /health
    try{
      $health = Invoke-RestMethod -Uri "$apiBase/health" -TimeoutSec $TimeoutSec
      $ok = ($health -eq 200) -or ($health.status -eq "ok") -or ($health.ok -eq $true)
      Add-Result "API /health" $ok ("Response: " + ($health | ConvertTo-Json -Compress))
    } catch {
      Add-Result "API /health" $false $_.Exception.Message
    }

    # Provider env + CHAT_ECHO check
    try{
      $envJson = (docker inspect --format '{{json .Config.Env }}' $apiId)
      $envMap = @{}
      foreach($kv in (ConvertFrom-Json $envJson)){ if($kv -match '^(.*?)=(.*)$'){ $envMap[$Matches[1]]=$Matches[2] } }
      $prov = $envMap['LLM_PROVIDER']; $model= $envMap['LLM_MODEL']; $echo = $envMap['CHAT_ECHO']
      $echoOff = [string]::IsNullOrWhiteSpace($echo) -or $echo -match '^(0|false|off)$'
      Add-Result "Provider env" ([bool]$prov -and [bool]$model) ("LLM_PROVIDER=$prov; LLM_MODEL=$model")
      Add-Result "CHAT_ECHO disabled" $echoOff ("CHAT_ECHO='"+($echo)+"'")
    } catch {
      Add-Result "Provider env" $false "Failed to read env: $($_.Exception.Message)"
    }

    # Autoswitch probe
    try{
      $body = @{ message="Say ok once."; use_rag=$false } | ConvertTo-Json -Compress
      $resp = Invoke-RestMethod -Uri "$apiBase/chat" -Method Post -ContentType "application/json" -Body $body -TimeoutSec $TimeoutSec
      $ans  = ($resp.answer) -as [string]
      $notEcho = -not ($ans -match '(^|\b)echo(\b|:)', 'IgnoreCase')
      Add-Result "API /chat (autoswitch)" ($ans -ne $null -and $notEcho) ("Answer=" + (if($ans){$ans}else{"<null>"}))
    } catch {
      Add-Result "API /chat (autoswitch)" $false $_.Exception.Message
    }
  }

  if($uiId){
    $uiPortLine = (& $compose 'port' $UiService '3000' 2>$null).Trim()
    $uiBase = if($uiPortLine){ "http://$uiPortLine" } else { "http://localhost:3000" }
    $uiBase = Normalize-Host $uiBase
    try{
      $html = Invoke-WebRequest -Uri $uiBase -TimeoutSec $TimeoutSec
      $ok = ($html.StatusCode -ge 200 -and $html.StatusCode -lt 400)
      Add-Result "UI reachable" $ok ("HTTP " + $html.StatusCode + " at " + $uiBase)
    } catch {
      Add-Result "UI reachable" $false $_.Exception.Message
    }
  }

  foreach($svc in @('redis','vector')){
    try{
      $id = (& $compose 'ps' '-q' $svc 2>$null).Trim()
      if($id){
        $state = (docker inspect -f '{{.State.Health.Status}}' $id 2>$null)
        if(-not $state){ $state = (docker inspect -f '{{.State.Status}}' $id 2>$null) }
        $ok = $state -match 'healthy|running'
        Add-Result "Service $svc" $ok ("State="+$state)
      }
    } catch {}
  }

} finally { Pop-Location }

# === Summary / Exit ===
$results | Sort-Object { if($_.Status -eq 'FAIL'){0}else{1} } | Format-Table -AutoSize
$failCount = ($results | Where-Object { $_.Status -eq 'FAIL' }).Count
$results | ConvertTo-Json -Compress | Out-File -Encoding UTF8 "$Root\logs\verify-results.json"

if($failCount -gt 0){
  Write-Host ""
  Write-Warning ("Failures: " + $failCount + " - investigate above checks.")
  exit 1
} else {
  Write-Host ""
  Write-Host "All checks passed."
  exit 0
}
