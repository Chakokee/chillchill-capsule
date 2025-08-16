$ErrorActionPreference = "Stop"
$ts   = Get-Date -Format "yyyyMMdd_HHmmss"
$logd = "C:\AiProject\logs"
$logf = Join-Path $logd "smoke_nodocker_$ts.log"
New-Item -ItemType Directory -Path $logd -Force | Out-Null
function WL($m){ $l="[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"),$m; $l | Tee-Object -FilePath $logf -Append }
function TPort($h,$p){ $r=Test-NetConnection -ComputerName $h -Port $p; WL ("Port {0}:{1} Tcp={2}" -f $h,$p,$r.TcpTestSucceeded); $r.TcpTestSucceeded }
function GETJ($u){ $sw=[Diagnostics.Stopwatch]::StartNew(); $j=Invoke-RestMethod -Method Get -Uri $u -TimeoutSec 10; $sw.Stop(); WL ("GET {0} {1}ms" -f $u,[int]$sw.Elapsed.TotalMilliseconds); $j }
$ok=$true; WL "=== Smoke (no Docker) start ==="
if (-not (TPort "127.0.0.1" 8000)){$ok=$false;WL "FAIL: API 8000 closed"}
if (-not (TPort "localhost" 3000)) {$ok=$false;WL "FAIL: UI 3000 closed"}
try{ $h=GETJ "http://127.0.0.1:8000/health"; if($h.ok -ne $true){$ok=$false;WL "FAIL: /health not ok:true"} else{WL "PASS: /health ok:true"} }catch{ $ok=$false;WL ("FAIL: /health "+$_.Exception.Message) }
try{ $s=GETJ "http://127.0.0.1:8000/rag/stats"; if($null -eq $s.count -or ($s.count -as [int]) -isnot [int]){$ok=$false;WL "FAIL: /rag/stats.count not numeric"} else{WL ("PASS: /rag/stats.count={0}" -f $s.count)} }catch{ $ok=$false;WL ("FAIL: /rag/stats "+$_.Exception.Message) }
try{ $m=GETJ "http://127.0.0.1:8000/models"; if($m.providers -and $m.providers.Count -ge 1){ WL ("PASS: /models providers="+($m.providers -join ",")) } else{$ok=$false;WL "FAIL: /models providers empty"} }catch{ $ok=$false;WL ("FAIL: /models "+$_.Exception.Message) }
try{ $body=@{provider="auto";messages=@(@{role="user";content="ping"})}|ConvertTo-Json -Depth 4; $sw=[Diagnostics.Stopwatch]::StartNew(); $r=Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/chat" -ContentType "application/json" -Body $body -TimeoutSec 20; $sw.Stop(); if($r.ok -ne $true -or -not $r.reply){$ok=$false;WL "FAIL: /chat no ok:true or empty reply"} else{WL ("PASS: /chat ok {0}ms (provider={1}, model={2})" -f ([int]$sw.Elapsed.TotalMilliseconds),$r.provider,$r.model)} }catch{ $ok=$false;WL ("FAIL: /chat "+$_.Exception.Message) }
try{ $ui=Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:3000/probe.html" -TimeoutSec 10; if($ui.StatusCode -eq 200){WL "PASS: UI probe 200"} else{$ok=$false;WL ("FAIL: UI probe status "+$ui.StatusCode)} }catch{ $ok=$false;WL ("FAIL: UI probe "+$_.Exception.Message) }
WL ("RESULT: "+($(if($ok){"PASS"}else{"FAIL"}))); WL "=== Smoke (no Docker) end ==="; if(-not $ok){ exit 1 }
