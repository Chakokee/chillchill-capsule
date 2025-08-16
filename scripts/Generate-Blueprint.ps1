param(
  [string]$Root = (Resolve-Path ".").Path,
  [string]$OutDir = "$((Resolve-Path ".").Path)\docs\blueprint"
)

$ErrorActionPreference = "Stop"

function Mask-Secret($k,$v){
  if ($k -match "KEY|TOKEN|SECRET|PASSWORD|API" -and $v) {
    if ($v.Length -le 8) { return "*" * ($v.Length) }
    return ($v.Substring(0,4) + ("*" * ($v.Length-6)) + $v.Substring($v.Length-2))
  } else { return $v }
}

function Load-DotEnv($path){
  $map = [ordered]@{}
  if (!(Test-Path $path)) { return $map }
  foreach($line in (Get-Content $path -Raw -Encoding UTF8) -split "\r?\n"){
    $l = $line.Trim()
    if (-not $l -or $l.StartsWith("#")) { continue }
    $eq = $l.IndexOf("="); if ($eq -lt 1) { continue }
    $k = $l.Substring(0,$eq).Trim()
    $v = $l.Substring($eq+1).Trim()
    $map[$k] = $v
  }
  return $map
}

function Compose-Json { try { (docker compose config --format json) | ConvertFrom-Json } catch { $null } }
function Try-Health {
  try { $h = curl -s http://localhost:8000/health; if ($h) { return $h | ConvertFrom-Json } } catch {}
  $null
}

# Helper to safely add many lines (coerce to string)
function Add-Lines([System.Collections.Generic.List[string]]$list, $items){
  if ($null -eq $items) { return }
  foreach($x in $items){
    if ($null -ne $x) { $list.Add([string]$x) }
  }
}

# Ensure out dir
New-Item -Force -ItemType Directory $OutDir | Out-Null

$envPath = Join-Path $Root ".env"
$envVars = Load-DotEnv $envPath
$compose = Compose-Json
$health  = Try-Health

# Compose services table
$svcLines = @()
if ($compose) {
  foreach($name in $compose.services.psobject.Properties.Name){
    $svc = $compose.services.$name
    $ports = @(); if ($svc.ports) { $ports = $svc.ports }
    $img = $svc.image
    $build = if ($svc.build) { "$($svc.build.context) (Dockerfile)" } else { $null }
    $svcLines += ("| {0} | {1} | {2} | {3} |" -f $name, $img, $build, (($ports -join ", ") -replace "\|","/"))
  }
}

# Providers table
$providers = @("openai","groq","gemini","ollama")
$provRows = foreach($p in $providers){
  $en = $envVars["$($p.ToUpper())_ENABLED"]
  $model =
    if ($p -eq "openai") { $envVars["LLM_MODEL"] }
    elseif ($p -eq "groq") { $envVars["GROQ_MODEL"] }
    elseif ($p -eq "gemini") { $envVars["GEMINI_MODEL"] }
    else { $envVars["OLLAMA_MODEL"] }
  "| $p | $en | $model |"
}

# Rewrite snippet
$nextCfg = "$Root\chatbot\chatbot-ui\next.config.js"
$rewriteSnippet = (Test-Path $nextCfg) ? (Get-Content $nextCfg -Raw -Encoding UTF8) : ""

# Profiles (safe regex quoting)
$profiles = @("default","general_prac","accountant","chef")
$mainPy = "$Root\chatbot\agent-api\main.py"
if (Test-Path $mainPy) {
  $txt = Get-Content $mainPy -Raw -Encoding UTF8
  $m = [regex]::Match($txt, 'Profile\s*=\s*Literal\[(.*?)\]')
  if ($m.Success) {
    $p = $m.Groups[1].Value -replace '[\s"'' ]',''
    if ($p) { $profiles = $p.Split(",") }
  }
}

# Masked env
$maskedEnvLines = foreach ($kv in $envVars.GetEnumerator()) {
  $k = $kv.Key; $v = $kv.Value
  "$k=" + (Mask-Secret $k $v)
}

# Git info
$tag = (git describe --tags --abbrev=0 2>$null)
$sha = (git rev-parse --short HEAD 2>$null)
$stamp = (Get-Date -Format "yyyy-MM-dd HH:mm")
$runId = (Get-Date -Format "yyyyMMdd-HHmm")

# Health table
$provHealthLines = @()
if ($health -and $health.providers) {
  $provHealthLines += "| provider | healthy | detail |"
  $provHealthLines += "|---|---:|---|"
  foreach($p in $health.providers.PSObject.Properties){
    $provHealthLines += "| $($p.Name) | $($p.Value.healthy) | $($p.Value.detail) |"
  }
}

# Build markdown
$md = New-Object System.Collections.Generic.List[string]
$md.Add('# ChillChill Blueprint')
$md.Add('')
$md.Add("- Generated: $stamp")
$md.Add("- Git: tag=$tag, sha=$sha")
$md.Add('')
$md.Add('## Goals')
$md.Add('- Multi-LLM with auto-switch (OpenAI, Groq, Gemini, Ollama)')
$md.Add('- RAG: store and retrieve documents (Qdrant)')
$md.Add('- Domain profiles: general_prac, accountant, chef')
$md.Add('- Private network access (LAN), optional TLS via Caddy')
$md.Add('- Living blueprint that maps all changes')
$md.Add('')
$md.Add('## Runtime Topology (docker compose)')
if ($svcLines.Count -gt 0) {
  $md.Add('')
  $md.Add('| service | image | build | ports |')
  $md.Add('|---|---|---|---|')
  Add-Lines $md $svcLines
} else {
  $md.Add('_compose config unavailable_')
}
$md.Add('')
$md.Add('## Providers')
$md.Add('| provider | enabled | model |')
$md.Add('|---|---:|---|')
Add-Lines $md $provRows
$md.Add('')
$md.Add('- Order: ' + $envVars["PROVIDER_ORDER"])
if ($provHealthLines.Count -gt 0) {
  $md.Add('')
  $md.Add('### Provider health (from /health)')
  Add-Lines $md $provHealthLines
}
$md.Add('')
$md.Add('## RAG')
$md.Add('- Vector host: ' + $envVars["VECTOR_HOST"])
$md.Add('- Vector port: ' + $envVars["VECTOR_PORT"])
$md.Add('- Collection: ' + $envVars["RAG_COLLECTION"])
$md.Add('- Embeddings: OpenAI=' + $envVars["EMBED_MODEL_OPENAI"] + '; Ollama=' + $envVars["OLLAMA_EMBED_MODEL"])
$md.Add('')
$md.Add('## Profiles')
$md.Add('- Active profiles: ' + ($profiles -join ', '))
$md.Add('- Profile collections: chill_docs_profileName (e.g., chill_docs_general_prac)')
$md.Add('')
$md.Add('## API Surface')
$md.Add('- /health')
$md.Add('- /chat (provider, use_rag, profile, inventory, diet, time_limit, appliances)')
$md.Add('- /rag/ingest, /rag/ingest/profile, /rag/query')
$md.Add('')
$md.Add('## UI → API Bridge')
$md.Add('```js')
Add-Lines $md ($rewriteSnippet -split "\r?\n")
$md.Add('```')
$md.Add('')
$md.Add('## Env (secrets masked)')
$md.Add('```')
Add-Lines $md $maskedEnvLines
$md.Add('```')
$md.Add('')
$md.Add('## Change Summary (recent)')
$md.Add('```')
$log = (git log --oneline -n 20 2>$null) -split "\r?\n"
Add-Lines $md $log
$md.Add('```')

$OutFile = Join-Path $OutDir 'BLUEPRINT.md'
$Snapshot = Join-Path $OutDir ('ChillChill-Blueprint-' + $runId + '.md')

$mdText = [string]::Join([Environment]::NewLine, $md) + [Environment]::NewLine
$mdText | Set-Content -Encoding UTF8 $OutFile
$mdText | Set-Content -Encoding UTF8 $Snapshot

Write-Host ('Blueprint written: ' + $OutFile)
Write-Host ('Snapshot: ' + $Snapshot)
