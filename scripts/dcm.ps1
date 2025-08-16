param([ValidateSet("api","ui","redis","vector")][string]$Svc="api")
function Dcm-Logs { param($s=$Svc) docker compose logs --no-color --tail=120 $s }
function Dcm-Rebuild { param($s=$Svc) docker compose build --no-cache $s; docker compose up -d $s }
function Dcm-VerifyApi { powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\Test-Api.ps1" }
function Dcm-CurlApi {
  curl.exe -s -i http://localhost:8000/health
  curl.exe -s -i -H "Content-Type: application/json" -d "{`"message`":`"hello`"}" http://localhost:8000/chat
}
function Dcm-UiUrl { Start-Process "http://localhost:3000" }
Write-Host "DCM ready. Try: Dcm-Logs; Dcm-Rebuild; Dcm-VerifyApi; Dcm-CurlApi; Dcm-UiUrl"
