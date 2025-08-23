# Validate-ChillChill.ps1
param(
  [switch]$VerboseOut
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Status($name,$ok,$warnMessage=''){
  $state = if ($ok) {'OK'} else {'FAIL'}
  "{0,-28} :: {1}{2}" -f $name, $state, $(if(-not $ok -and $warnMessage){ " — $warnMessage"} )
}

$root = 'C:\AiProject'
$apiDir = Join-Path $root 'chatbot\agent-api'
$composeOverride = Join-Path $root 'docker-compose.override.yml'
$manifestPath = Join-Path $root 'operator.manifest.json'
$envPath = Join-Path $root '.env'

$finds = [ordered]@{}

# 1) Manifest presence & content
$manifestOK = $false
$manifestWhy = ''
if (Test-Path $manifestPath){
  try{
    $m = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $expectOrder = @('gemini','groq','mistral')
    $manifestOK = ($m.autoswitch -join ',') -eq ($expectOrder -join ',')
    if(-not $manifestOK){ $manifestWhy = "autoswitch != gemini,groq,mistral" }
    # personas check (best-effort)
    $p = $m.personas
    if($p){
      $gp = $p.GP; $chef = $p.Chef; $acct = $p.Accountant
      if($manifestOK){
        $manifestOK = $gp -eq 'gemini' -and $chef -eq 'groq' -and $acct -in @('groq','mistral')
        if(-not $manifestOK){ $manifestWhy = "personas mismatch (GP→gemini, Chef→groq, Acct→groq|mistral)" }
      }
    }
  } catch { $manifestWhy = "invalid JSON"; $manifestOK = $false }
}else{
  $manifestWhy = "missing file"
}
$finds['Manifest'] = Status 'Manifest' $manifestOK $manifestWhy

# 2) .env keys present (non-empty)
$envOK = $false
$envWhy = ''
if(Test-Path $envPath){
  $env = Get-Content $envPath | Where-Object {$_ -match '^\s*[^#]'}
  function hasKey($k){ $env -match ("^\s*{0}=" -f [regex]::Escape($k)) }
  $gemi = hasKey 'GEMINI_API_KEY'
  $groq = hasKey 'GROQ_API_KEY'
  $mist = hasKey 'MISTRAL_API_KEY'
  $envOK = $gemi -and $groq -and $mist
  if(-not $envOK){ $envWhy = "missing one of GEMINI_API_KEY/GROQ_API_KEY/MISTRAL_API_KEY" }
}else{
  $envWhy = ".env not found"
}
$finds['EnvKeys'] = Status 'Env Keys' $envOK $envWhy

# 3) Compose override mounts manifest & passes keys; OpenAI/Ollama disabled
$composeOK = $false; $composeWhy = ''
if(Test-Path $composeOverride){
  $y = Get-Content $composeOverride -Raw
  $hasManifestMount = $y -match 'operator\.manifest\.json'
  $passesGemini = $y -match 'GEMINI_API_KEY'
  $passesGroq   = $y -match 'GROQ_API_KEY'
  $passesMistral= $y -match 'MISTRAL_API_KEY'
  $openAIOn     = $y -match 'OPENAI_API_KEY'
  $ollamaOn     = $y -match 'OLLAMA_'
  $composeOK = $hasManifestMount -and $passesGemini -and $passesGroq -and $passesMistral -and (-not $openAIOn) -and (-not $ollamaOn)
  if(-not $composeOK){
    $composeWhy = "need manifest mount + keys; ensure OpenAI/Ollama not passed"
  }
}else{
  $composeWhy = "override missing"
}
$finds['Compose'] = Status 'Compose' $composeOK $composeWhy

# 4) providers.py reflects autoswitch/personas
$provPath = Join-Path $apiDir 'providers.py'
$provOK = $false; $provWhy = ''
if(Test-Path $provPath){
  $txt = Get-Content $provPath -Raw
  $autoOK = $txt -match "'autoswitch'\s*:\s*\[\s*'gemini'\s*,\s*'groq'\s*,\s*'mistral'\s*\]"
  $gpOK   = $txt -match "GP'.*'(gemini)'" 
  $chefOK = $txt -match "Chef'.*'(groq)'" 
  $accOK  = $txt -match "Accountant'.*'(groq|mistral)'"
  $provOK = $autoOK -and $gpOK -and $chefOK -and $accOK
  if(-not $provOK){ $provWhy = "autoswitch/personas not updated in providers.py" }
}else{
  $provWhy = "providers.py missing"
}
$finds['Providers'] = Status 'Providers.py' $provOK $provWhy

# Print results
"===== VALIDATION SUMMARY ====="
$finds.GetEnumerator() | ForEach-Object { $_.Value } | ForEach-Object { $_ }
"===== END VALIDATION ====="

# Traffic Light
$critical = -not ($manifestOK -and $envOK -and $composeOK -and $provOK)
$traffic = if($critical){ 'RED' } else { 'GREEN' }
"RISK METER:`nTraffic Light: $traffic"
if($VerboseOut){ "`nPaths:`n$manifestPath`n$envPath`n$composeOverride`n$provPath" }
