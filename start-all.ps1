# --- ChillChill Docker Engine Guard v2.1 ---
# Clear stray host that can break local named-pipe usage
Remove-Item Env:\DOCKER_HOST -ErrorAction SilentlyContinue

function Wait-Docker {
  param([int]$TimeoutSec = 180)
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $apiFallbackSet = $false
  do {
    try {
      docker info | Out-Null
      return
    } catch {
      $msg = $_.Exception.Message
      if ($msg -match 'supports the requested API version' -and -not $apiFallbackSet) {
        # Downshift the API handshake for THIS session only if the engine complains
        $env:DOCKER_API_VERSION = "1.43"
        $apiFallbackSet = $true
      }
      Start-Sleep 3
    }
  } while ((Get-Date) -lt $deadline)
  throw "Docker engine did not become ready within $TimeoutSec seconds."
}

Wait-Docker  # ensure engine is truly ready before compose

# Optional pre-pull on first runs or after updates: set CHILLCHILL_PREPULL=1 before running
if ($env:CHILLCHILL_PREPULL -eq '1') {
  Write-Host ">>> Pre-pulling core images (optional)..." -ForegroundColor Cyan
  docker pull ollama/ollama:latest
  docker pull chromadb/chroma:latest 2>$null
}
# --- end guard ---
