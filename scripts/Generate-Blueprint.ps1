param([string]$Root="C:\AiProject",[string]$Out="C:\AiProject\docs\blueprint\BLUEPRINT.md")
$ErrorActionPreference="Stop"
$envFile   = Join-Path $Root ".env"
$compose   = Join-Path $Root "docker-compose.yml"
$override  = Join-Path $Root "docker-compose.override.yml"
$blueDir   = Split-Path $Out -Parent
if(-not (Test-Path $blueDir)){ New-Item -ItemType Directory -Path $blueDir -Force | Out-Null }
$envText=(Test-Path $envFile)?(Get-Content $envFile -Raw):""
function GetKV($k){
  $pattern = "^\s*{0}\s*=\s*(.*)$" -f [regex]::Escape($k)
  $m = [regex]::Match($envText, $pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
  if($m.Success){ return $m.Groups[1].Value.Trim() }
  return ""
}
$prov = GetKV "LLM_PROVIDER"; $model = GetKV "LLM_MODEL"; $echo = GetKV "CHAT_ECHO"
$composeCfg=""; try{ Push-Location $Root; $composeCfg=(docker compose config); Pop-Location }catch{}
$autoOrder=""; try{ Push-Location $Root; $logs=(docker compose logs --no-color api --tail=200); Pop-Location; if($logs -match "order\s*=\s*([a-z,]+)"){ $autoOrder=$Matches[1] } }catch{}
$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss K"
$md = ""
$md += "# ChillChill Capsule — Living Blueprint`r`n"
$md += "_Last updated: $ts_`r`n`r`n"
$md += "## Architecture`r`n"
$md += "- UI: Next.js (Docker, port 3000)`r`n"
$md += "- API: FastAPI /chat, /health`r`n"
$md += "- Vector: Qdrant · Cache: Redis`r`n`r`n"
$md += "## Providers & Personas`r`n"
$md += "- LLM_PROVIDER: **$prov**`r`n"
$md += "- LLM_MODEL: **$model**`r`n"
$md += "- Autoswitch order: **$autoOrder**`r`n"
$md += "- Personas: GP→Gemini; Chef→OpenAI; Accountant→Groq (llama3-70b-8192)`r`n`r`n"
$md += "## Runtime Config`r`n"
$md += "- CHAT_ECHO: **$echo**`r`n"
$md += "- docker-compose: $compose`r`n"
$md += "- docker-compose.override: $override`r`n`r`n"
$md += "## Effective docker compose (excerpt)`r`n"
$md += "~~~yaml`r`n"
$md += $composeCfg + "`r`n"
$md += "~~~`r`n"
[System.IO.File]::WriteAllText($Out, $md, [System.Text.UTF8Encoding]::new($false))