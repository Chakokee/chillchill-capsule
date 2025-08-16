param([Parameter(Mandatory=$true)][string]$Message)
$path = "C:\AiProject\logs\capsule-changelog.txt"
"[{0}] {1}" -f (Get-Date -Format s), $Message | Add-Content -Encoding UTF8 $path
Write-Host "[Changelog] appended ->" $Message
