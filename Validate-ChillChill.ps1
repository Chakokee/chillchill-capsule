# Validate-ChillChill.ps1  (vFinal)
param()

function Test-Tcp {
    param([string]$TcpHost, [int]$Port, [int]$Timeout=3000)
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($TcpHost,$Port,$null,$null)
        if (-not $iar.AsyncWaitHandle.WaitOne($Timeout,$false)) { return $false }
        $client.EndConnect($iar)
        $client.Close()
        return $true
    } catch { return $false }
}

Write-Host "===== VALIDATION START ====="

# API checks
try {
    $apiHealth = (Invoke-WebRequest -Uri "http://127.0.0.1:8000/health" -TimeoutSec 8).StatusCode
    Write-Host "[API] /health :: $apiHealth"
} catch { Write-Host "[API] /health :: FAIL" }

try {
    $apiChat = (Invoke-WebRequest -Uri "http://127.0.0.1:8000/chat" -Method POST -Body '{"message":"ping"}' -ContentType "application/json" -TimeoutSec 8).StatusCode
    Write-Host "[API] /chat (POST) :: $apiChat"
} catch { Write-Host "[API] /chat (POST) :: FAIL" }

# Containers
try {
    $containers = docker compose ps --format json | ConvertFrom-Json
    $containers | ForEach-Object { Write-Host "[Container] $($_.Name) :: $($_.State)" }
} catch { Write-Host "[Container] listing :: FAIL" }

# UI env
try {
    $ui = ($containers | ? { $_.Name -match 'ui' }).Name
    if ($ui) {
        $envCheck = docker exec $ui printenv | Select-String "NEXT_PUBLIC_API_BASE_URL"
        if ($envCheck) { Write-Host ("[ENV] NEXT_PUBLIC_API_BASE_URL :: " + $envCheck.Line) }
        else { Write-Host "[ENV] NEXT_PUBLIC_API_BASE_URL :: WARN (missing/mismatch)" }
    }
} catch { Write-Host "[ENV] NEXT_PUBLIC_API_BASE_URL :: FAIL" }

# Infra ports
$redisOk  = Test-Tcp '127.0.0.1' 6379
$qdrantOk = Test-Tcp '127.0.0.1' 6333
Write-Host "[Infra] Redis:6379 :: $redisOk"
Write-Host "[Infra] Qdrant:6333 :: $qdrantOk"

# --- Ollama checks (prefer local since you confirmed it's reachable)
$OllamaHost  = "http://127.0.0.1:11434"

function Get-Ollama {
    param([string]$Path, [int]$Timeout=10)
    Invoke-WebRequest -Uri ($OllamaHost + $Path) -TimeoutSec $Timeout
}

function Post-Ollama {
    param([string]$Path, [string]$Body, [int]$Timeout=20)
    Invoke-WebRequest -Uri ($OllamaHost + $Path) -Method POST -Body $Body -ContentType "application/json" -TimeoutSec $Timeout
}

try {
    $r = Get-Ollama "/api/tags" -Timeout 10
    Write-Host "[Ollama] /api/tags :: $($r.StatusCode)"
} catch { Write-Host "[Ollama] /api/tags :: FAIL" }

try {
    $b = '{"model":"llama3.2:3b","prompt":"hi"}'
    $g = Post-Ollama "/api/generate" -Body $b -Timeout 20
    Write-Host "[Ollama] /api/generate :: $($g.StatusCode)"
} catch { Write-Host "[Ollama] /api/generate :: FAIL" }

Write-Host "===== VALIDATION END ====="
