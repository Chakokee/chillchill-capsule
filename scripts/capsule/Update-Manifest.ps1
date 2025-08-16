param([string]$OutDir = "C:\AiProject\logs")
function Mask($s){ if([string]::IsNullOrEmpty($s)){"<none>"} else{$s -replace "([A-Za-z0-9]{4})[A-Za-z0-9\-_=]{8,}","`$1********"} }
$dt = Get-Date -Format "yyyyMMdd-HHmmss"
$dest   = Join-Path $OutDir "manifest-$dt.json"
$latest = Join-Path $OutDir "manifest-latest.json"
$root = "C:\AiProject"; $ui = Join-Path $root "chatbot\chatbot-ui"

# Files snapshot (no node_modules/.git/logs/.next)
$tree = Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch "\\node_modules\\|\\.git\\|\\logs\\|\\\.next\\" } |
  Select-Object FullName, Length, LastWriteTime

# .env (masked + parsed)
$envPath = Join-Path $root ".env"
$envRaw = (Test-Path $envPath) ? (Get-Content $envPath -Raw) : ""
$envMasked = ($envRaw -split "`r?`n") | ForEach-Object {
  if ($_ -match "KEY|SECRET|TOKEN") { ($_ -split "=",2)[0] + "=" + (Mask (($_ -split "=",2)[1])) } else { $_ }
} | Out-String
# Parse kv (simple)
$kv=@{}; foreach($line in ($envRaw -split "`r?`n")) {
  if ($line -match "^\s*#|^\s*$") { continue }
  $k,$v = $line -split "=",2; if ($k) { $kv[$k.Trim()] = $v }
}

# HTTP helpers
function TryGet($url){ try{ Invoke-RestMethod -Uri $url -TimeoutSec 5 } catch { $null } }
$compose = docker compose ps --format json 2>$null | ConvertFrom-Json
$apiBase = "http://localhost:8000"
$health  = TryGet "$apiBase/health"
$openapi = TryGet "$apiBase/openapi.json"
$models  = TryGet "$apiBase/models"
$warm    = TryGet "$apiBase/warmup"
$qdrant  = TryGet "http://localhost:6333/collections"
$envLocal = Join-Path $ui ".env.local"
$uiEnv = (Test-Path $envLocal) ? (Get-Content $envLocal -Raw) : ""
$proxyHealth = TryGet "http://localhost:3000/api/health"

# Expected provider posture (locked to OpenAI defaults)
$expected = [ordered]@{
  provider   = "openai"
  model      = "gpt-4o-mini"
  chat_echo  = "false"
  key_needed = "OPENAI_API_KEY"
}
$actual = [ordered]@{
  provider   = ($kv["LLM_PROVIDER"])
  model      = ($kv["LLM_MODEL"])
  chat_echo  = ($kv["CHAT_ECHO"])
  has_key    = [bool]($kv.ContainsKey("OPENAI_API_KEY") -and ($kv["OPENAI_API_KEY"].Trim() -ne ""))
}
$compliant = ($actual.provider -eq $expected.provider) -and
             ($actual.model -eq $expected.model) -and
             ($actual.chat_echo -match '^(false|0)?$') -and
             ($actual.has_key)

$result = [ordered]@{
  timestamp = (Get-Date)
  projectRoot = $root
  compose = $compose
  api = @{
    health=$health; models=$models; warmup=$warm; openapi_paths=($openapi?.paths?.psobject?.Properties?.Name)
  }
  ui = @{ env_local=$uiEnv; proxy_health=$proxyHealth }
  qdrant = $qdrant
  env_masked = $envMasked.TrimEnd()
  provider = @{
    expected  = $expected
    actual    = $actual
    compliant = $compliant
  }
  files = $tree
}
$result | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $dest
Copy-Item $dest $latest -Force
Write-Host "[Manifest] Wrote:" $dest
