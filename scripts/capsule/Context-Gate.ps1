$manifest = "C:\AiProject\logs\manifest-latest.json"
if (-not (Test-Path $manifest)) { Write-Warning "manifest-latest.json missing. Run Update-Manifest.ps1."; exit 1 }
$m = Get-Content $manifest -Raw | ConvertFrom-Json
$p = [ordered]@{
  timestamp = $m.timestamp
  api_paths = $m.api.openapi_paths
  ui_proxy_ok = [bool]$m.ui.proxy_health
  provider_hint = @{
    has_any_provider_key = ($m.env_masked -match "OPENAI_API_KEY|ANTHROPIC_API_KEY|GROQ_API_KEY|AZURE_OPENAI_KEY")
    llm_provider_set     = ($m.env_masked -match "LLM_PROVIDER=")
    chat_echo_present    = ($m.env_masked -match "CHAT_ECHO=")
  }
}
$p | ConvertTo-Json -Depth 5
