$manifest = "C:\AiProject\logs\manifest-latest.json"
if (-not (Test-Path $manifest)) {
  Write-Error "manifest-latest.json missing. Run Update-Manifest.ps1 first."; exit 2
}
$m = Get-Content $manifest -Raw | ConvertFrom-Json
if (-not $m.provider.compliant) {
  Write-Error ("Provider non-compliant. expected={0}/{1} echo={2} key={3} actual={4}/{5} echo={6} key={7}" -f
    $m.provider.expected.provider, $m.provider.expected.model, $m.provider.expected.chat_echo, $m.provider.expected.key_needed,
    $m.provider.actual.provider,   $m.provider.actual.model,   $m.provider.actual.chat_echo,   $m.provider.actual.has_key)
  exit 3
}
Write-Host "[Validate] Provider posture compliant."
