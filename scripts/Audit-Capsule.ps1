param([int]$DaysHistory = 14)

$ErrorActionPreference = "Stop"
$root   = "C:\AiProject"
$apiDir = Join-Path $root "chatbot\agent-api"
$uiDir  = Join-Path $root "chatbot\chatbot-ui"
$logDir = Join-Path $root "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$ts     = Get-Date -Format "yyyyMMdd-HHmm"
$report = Join-Path $logDir "audit-$ts.txt"

function Out-Head([string]$t){
  "`n=== $t ===`n" | Tee-Object -FilePath $report -Append | Out-Host
}
function Out-Line([string]$t){
  $t | Tee-Object -FilePath $report -Append | Out-Host
}

Out-Head "Context"
Out-Line ("Now: {0}" -f (Get-Date))
Out-Line ("Root: {0}" -f $root)
Out-Line ("API Dir: {0} | UI Dir: {1}" -f $apiDir, $uiDir)
Out-Line ("Compose: {0}" -f (Join-Path $root 'docker-compose.yml'))

Out-Head "Path Guard"
@(
  "chatbot\agent-api\main.py",
  "chatbot\chatbot-ui\components\AppClient.tsx",
  "chatbot\chatbot-ui\components\ChatControls.tsx",
  "chatbot\chatbot-ui\.env.local",
  "docker-compose.yml"
) | ForEach-Object {
  $p = Join-Path $root $_
  Out-Line (("{0} -> {1}") -f (Test-Path $p), $p)
}

$todayStart = (Get-Date).Date
$todayStr   = $todayStart.ToString("yyyy-MM-dd")

if (Test-Path (Join-Path $root ".git")) {
  Push-Location $root
  try {
    Out-Head ("Git Baseline (< {0})" -f $todayStr)
    $baseline = (& git log --before="$todayStr 00:00" -n 1 --format="%H|%cd|%s")
    if (-not $baseline) {
      $first = (& git rev-list --max-parents=0 HEAD | Select-Object -First 1)
      $baseline = "$first|(first)|"
    }
    $b = $baseline -split "\|",3
    $bHash,$bDate,$bMsg = $b[0],$b[1],$b[2]
    Out-Line ("Baseline: {0}" -f $bHash)
    Out-Line ("Date: {0}" -f $bDate)
    Out-Line ("Msg:  {0}" -f $bMsg)

    Out-Head ("Git Log (last {0} days)" -f $DaysHistory)
    & git --no-pager log --since="$(Get-Date).AddDays(-$DaysHistory).ToString('yyyy-MM-dd')" --graph --decorate --oneline |
      Tee-Object -FilePath $report -Append | Out-Null

    Out-Head "Diff (baseline..HEAD) - names and status"
    & git --no-pager diff --name-status "$bHash..HEAD" -- `
      "chatbot/agent-api" "chatbot/chatbot-ui" "docker-compose.yml" |
      Tee-Object -FilePath $report -Append | Out-Null

    Out-Head "Diff Stat (baseline..HEAD)"
    & git --no-pager diff --stat "$bHash..HEAD" -- `
      "chatbot/agent-api" "chatbot/chatbot-ui" "docker-compose.yml" |
      Tee-Object -FilePath $report -Append | Out-Null
  }
  finally {
    Pop-Location
  }
}
else {
  Out-Head "Snapshot Mode (no git)"
  $manifest = Join-Path $logDir "manifest-$ts.csv"
  $targets = @($apiDir,$uiDir)
  $exts = '*.ts','*.tsx','*.js','*.py','*.json','*.yml','*.yaml','*.toml','*.md','*.lock','*.config.*'
  $rows = New-Object System.Collections.Generic.List[object]
  foreach ($t in $targets) {
    if (Test-Path $t) {
      Get-ChildItem $t -Recurse -File -Include $exts | ForEach-Object {
        $h = Get-FileHash $_.FullName -Algorithm SHA256
        $rows.Add([PSCustomObject]@{
          Path = $_.FullName.Replace($root+'\','')
          Size = $_.Length
          LastWrite = $_.LastWriteTime
          Hash = $h.Hash
        })
      }
    }
  }
  $rows | Sort-Object Path | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $manifest
  Out-Line ("New manifest: {0}" -f $manifest)
}

Out-Head "Env and Compose"
$uiEnv  = Join-Path $uiDir ".env.local"
$apiEnv = Join-Path $apiDir ".env"
foreach ($e in @($uiEnv,$apiEnv)) {
  if (Test-Path $e) {
    $h = Get-FileHash $e -Algorithm SHA256
    Out-Line ("ENV: {0} (SHA256={1}, LastWrite={2})" -f $e, $h.Hash, (Get-Item $e).LastWriteTime)
  } else {
    Out-Line ("ENV: {0} (missing)" -f $e)
  }
}
Out-Line ""
Out-Line "docker compose ps:"
docker compose ps | Tee-Object -FilePath $report -Append | Out-Null
Out-Line ""
Out-Line "docker compose config (services and ports):"
docker compose config | Tee-Object -FilePath $report -Append | Out-Null

Out-Head "API OpenAPI paths"
try {
  $paths = (Invoke-RestMethod http://localhost:8000/openapi.json).paths.PSObject.Properties.Name
  $paths | Tee-Object -FilePath $report -Append | Out-Null
} catch {
  Out-Line ("Could not fetch OpenAPI: {0}" -f $_.Exception.Message)
}

Out-Head "Done"
Out-Line ("Report: {0}" -f $report)
