# Fix-AddChat.ps1 — add /chat endpoint + CORS; upgrade UI to show replies & auto-speak
[CmdletBinding()] param()
$ErrorActionPreference='Stop'

$root   = 'C:\AiProject'
$apiDir = Join-Path $root 'chatbot\agent-api'
$mainPy = Join-Path $apiDir 'main.py'
$uiDir  = Join-Path $root 'chatbot\chatbot-ui'
$chatTsx= Join-Path $uiDir 'components\ChatControls.tsx'
if (-not (Test-Path $chatTsx)) { $chatTsx = Join-Path $uiDir 'app\components\ChatControls.tsx' }
$validate = Join-Path $root 'Validate-ChillChill.ps1'

function Backup($p){ if(Test-Path $p){ $b="$p.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"; Copy-Item $p $b -Force; Write-Host "Backup: $b" } }

# --- Patch API: add CORS + /chat ---
Backup $mainPy
$py = Get-Content $mainPy -Raw

# Ensure imports
if ($py -notmatch 'from fastapi import') {
  $py = "from fastapi import FastAPI, Response, Body`r`nimport os`r`n" + $py
} elseif ($py -notmatch '\bBody\b') {
  $py = $py -replace 'from fastapi import ([^\r\n]+)', 'from fastapi import $1, Body'
}
if ($py -notmatch '\bResponse\b') {
  $py = $py -replace 'from fastapi import ([^\r\n]+)', 'from fastapi import $1, Response'
}
if ($py -notmatch 'from fastapi\.middleware\.cors import CORSMiddleware') {
  $py = "from fastapi.middleware.cors import CORSMiddleware`r`n" + $py
}
# Add CORS once
if ($py -notmatch 'add_middleware\(CORSMiddleware') {
  $py = $py + @"

# CORS for browser UI
try:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["http://localhost:3000","http://127.0.0.1:3000","*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
except NameError:
    # If 'app' is defined later, this will be ignored; add again after app creation if needed.
    pass
"@
}
# /chat endpoint (idempotent)
if ($py -notmatch '(?m)^@app\.post\("/chat"\)') {
  $py += @"

@app.post("/chat")
async def chat(payload: dict = Body(None)):
    msg = ((payload or {}).get("message") or "").strip()
    if not msg:
        return {"reply": "Say something and I’ll respond."}
    # Minimal friendly bot reply (no external keys/fees)
    reply = f"Hi! You said: {msg}. I’m ChillChill—voice is free and active."
    return {"reply": reply}
"
}

# If app wasn’t yet created when we added CORS above, try again now
if ($py -match '(?m)^app\s*=\s*FastAPI') {
  if ($py -notmatch '(?s)app\.add_middleware\(\s*CORSMiddleware') {
    $py = $py -replace '(?m)^app\s*=\s*FastAPI\((.*?)\)\s*',
      "app = FastAPI(\$1)`r`napp.add_middleware(CORSMiddleware, allow_origins=[\"http://localhost:3000\",\"http://127.0.0.1:3000\",\"*\"], allow_credentials=True, allow_methods=[\"*\"], allow_headers=[\"*\"] )`r`n"
  }
}

Set-Content -Path $mainPy -Value $py -Encoding UTF8
Write-Host "API patched: CORS + /chat added."

# --- Patch UI: transcript UI + auto-speak replies via Piper ---
Backup $chatTsx
$tsx = @'
"use client";

import { useState } from "react";

type Turn = { role: "user" | "assistant"; text: string };

export default function ChatControls() {
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState("");
  const [chat, setChat] = useState<Turn[]>([]);
  const API_BASE = process.env.NEXT_PUBLIC_API_BASE_URL || "http://localhost:8000";

  async function speakText(text: string) {
    try {
      const res = await fetch("/voice/speak", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text })
      });
      if (!res.ok) throw new Error("speak failed");
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      new Audio(url).play();
    } catch (e) { console.error("Speak error", e); }
  }

  async function sendMessage(e?: React.FormEvent) {
    e?.preventDefault();
    const content = msg.trim();
    if (!content) return;
    setBusy(true);
    setChat(prev => [...prev, { role: "user", text: content }]);
    try {
      const res = await fetch(`${API_BASE}/chat`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: content })
      });
      if (!res.ok) throw new Error(`Send failed: ${res.status}`);
      const data = await res.json().catch(() => ({}));
      const reply = (data && (data.reply || data.message || data.text)) || "Okay.";
      setChat(prev => [...prev, { role: "assistant", text: reply }]);
      setMsg("");
      // auto-speak the assistant reply
      speakText(reply);
    } catch (err) {
      console.error(err);
      alert("Send failed. Check API /chat or NEXT_PUBLIC_API_BASE_URL.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center gap-2">
        {/* Voice: speak current message or last assistant reply */}
        <button
          aria-label="Voice"
          type="button"
          onClick={() => speakText(msg || (chat.length ? chat[chat.length-1].text : "Hello from ChillChill."))}
          className="rounded-2xl px-3 py-2 shadow-sm"
        >
          🎙
        </button>
      </div>
      <form onSubmit={sendMessage} className="flex items-center gap-2">
        <input
          name="message"
          value={msg}
          onChange={(e) => setMsg(e.target.value)}
          placeholder="Type and press Enter…"
          className="flex-1 rounded-xl px-3 py-2 bg-transparent border border-neutral-700"
        />
        <button type="submit" disabled={busy} className="rounded-xl px-3 py-2 shadow-sm border border-neutral-700">
          {busy ? "Sending…" : "Send"}
        </button>
      </form>
      <div className="space-y-2 mt-2">
        {chat.map((t, i) => (
          <div key={i} className={`text-sm ${t.role === "user" ? "text-blue-300" : "text-green-300"}`}>
            {t.role === "user" ? "You: " : "ChillChill: "}{t.text}
          </div>
        ))}
      </div>
    </div>
  );
}
'@
Set-Content -Path $chatTsx -Value $tsx -Encoding UTF8
Write-Host "UI patched: transcript + auto-speak reply."

# --- Rebuild & validate ---
Write-Host "`nRebuilding API and UI..."
docker compose --progress=plain build api ui
docker compose up -d api ui

if (Test-Path $validate) {
  pwsh -NoLogo -NoProfile -File $validate
} else {
  Write-Host "Validation script not found; skipping."
}

Write-Host "`nTry it: open http://localhost:3000 → type a message → Send. You’ll see a reply and hear Piper speak it."
