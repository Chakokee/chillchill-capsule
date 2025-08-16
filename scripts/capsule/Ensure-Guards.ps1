$envPath = "C:\AiProject\.env"
$kv = @{}
if (Test-Path $envPath) {
  (Get-Content $envPath) | ForEach-Object {
    if ($_ -match "^\s*#|^\s*$") { return }
    $k,$v = $_ -split "=",2
    $kv[$k.Trim()] = $v
  }
}
$missing = @(); foreach($k in @("LLM_PROVIDER","LLM_MODEL")){ if (-not $kv.ContainsKey($k)) { $missing += $k } }
$hasKey = ($kv.Keys | Where-Object { $_ -match "OPENAI_API_KEY|ANTHROPIC_API_KEY|GROQ_API_KEY|AZURE_OPENAI_KEY" }) -ne $null
$echoLine = $kv["CHAT_ECHO"]

$report = [ordered]@{
  has_env_file = (Test-Path $envPath);
  missing_vars = $missing;
  has_any_provider_key = $hasKey;
  chat_echo = $echoLine;
}
$report | ConvertTo-Json -Depth 3 | Write-Output
if (-not $hasKey -or $missing.Count -gt 0 -or ($echoLine -match 'true')) {
  Write-Warning "Provider guard: configuration suggests Echo fallback. Set keys and CHAT_ECHO=false."
}
