[CmdletBinding()]
param(
  [string]$Api = "http://127.0.0.1:8000",
  [string]$Provider = "ollama",
  [string]$Model = "llama3:8b",
  [string]$Msg = "Hello from Wil",
  [double]$Temp = 0.2
)
$body = @{ provider=$Provider; model=$Model; message=$Msg; temperature=$Temp } | ConvertTo-Json
$r = Invoke-RestMethod -Uri "$Api/chat" -Method POST -ContentType 'application/json' -Body $body
$r | Format-List
