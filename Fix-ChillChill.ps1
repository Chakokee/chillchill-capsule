param(
  [string]$Root="C:\AiProject",
  [int]$ApiPort=8000,
  [int]$UiPort=3000,
  [string]$ApiService="api",
  [string]$UiService="ui"
)
$ErrorActionPreference="Stop"

# Paths
$LOGS = Join-Path $Root "logs"
$VAL  = Join-Path $Root "Validate-ChillChill.ps1"
if(!(Test-Path $Root)){ throw "Root not found: " + $Root }
if(!(Test-Path $LOGS)){ New-Item -ItemType Directory -Path $LOGS | Out-Null }

function ComposeCmd {
  $cmd=@("docker","compose")
  try{ & $cmd 'version' *> $null; return $cmd }catch{}
  if(Get-Command docker-compose -ErrorAction SilentlyContinue){ return @("docker-compose") }
  throw "Docker Compose not available on PATH."
}
$compose = ComposeCmd

# Helper: wait for port
function Wait-Port([string]$Target,[int]$Port,[int]$Timeout=45){
  $t0=Get-Date
  while((Get-Date)-$t0 -lt ([TimeSpan]::FromSeconds($Timeout))){
    try{
      $ok = (Test-NetConnection -ComputerName $Target -Port $Port -WarningAction SilentlyContinue).TcpTestSucceeded
      if($ok){ return $true }
    }catch{}
    Start-Sleep -Milliseconds 500
  }
  return $false
}

Push-Location $Root
try{
  # 1) Build+start API/UI and capture logs
  $upOut = Join-Path $LOGS "compose-up.log"
  Remove-Item $upOut -Force -ErrorAction SilentlyContinue | Out-Null
  "`n=== docker compose up -d --build $ApiService $UiService ===`n" | Out-File -FilePath $upOut -Encoding ASCII
  $proc = Start-Process -FilePath "docker" `
    -ArgumentList @("compose","up","-d","--build",$ApiService,$UiService) `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput $upOut -RedirectStandardError $upOut
  $proc.WaitForExit()
  if($proc.ExitCode -ne 0){
    Write-Host "TRAFFIC LIGHT: RED"
    Write-Host ("RCA: docker compose up failed for services '" + $ApiService + "', '" + $UiService + "'. See " + $upOut)
    Get-Content $upOut -Tail 80 | ForEach-Object { Write-Host $_ }
    exit 1
  }

  # 2) Wait for ports to open
  $apiOpen = Wait-Port -Target "localhost" -Port $ApiPort -Timeout 45
  $uiOpen  = Wait-Port -Target "localhost" -Port $UiPort  -Timeout 45
  Write-Host ("API port " + $ApiPort + ": " + ($(if($apiOpen){"OPEN"}else{"CLOSED"})))
  Write-Host ("UI  port " + $UiPort  + ": " + ($(if($uiOpen) {"OPEN"}else{"CLOSED"})))

  # 3) Run validator and echo its summary
  if(Test-Path $VAL){
    & powershell -NoProfile -ExecutionPolicy Bypass -File $VAL -ApiService $ApiService -UiService $UiService
    $sumPath = Join-Path $LOGS "verify-summary.json"
    if(Test-Path $sumPath){
      $sum = Get-Content $sumPath -Raw | ConvertFrom-Json
      Write-Host ""
      Write-Host "=== SUMMARY ==="
      Write-Host ("Traffic Light: " + $sum.light)
      if($sum.failures){ Write-Host ("Failures: " + ($sum.failures -join ", ")) }
      if($sum.rca){ Write-Host ("RCA: " + ($sum.rca -join " | ")) }
      if($sum.light -ne "GREEN"){ exit 1 } else { exit 0 }
    } else {
      Write-Host "TRAFFIC LIGHT: AMBER"
      Write-Host "RCA: Validator summary not found; check services manually."
      exit 1
    }
  } else {
    Write-Host "TRAFFIC LIGHT: AMBER"
    Write-Host "RCA: Validator script not found; rerun Validate-ChillChill.ps1."
    exit 1
  }
}
finally{ Pop-Location }
