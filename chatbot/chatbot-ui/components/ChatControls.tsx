"use client";

import { useState } from "react";

export default function ChatControls() {
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState("");
  const API_BASE = process.env.NEXT_PUBLIC_API_BASE_URL || "http://localhost:8000";

  async function handleSpeak() {
    try {
      const u = new SpeechSynthesisUtterance("Hello this is ChillChill, voice activated for free.");
      u.pitch = 1.2; u.rate = 1.0;
      window.speechSynthesis.cancel(); window.speechSynthesis.speak(u);
    } catch (e) { console.error("Browser TTS error", e); }
  }

  async function sendMessage(e?: React.FormEvent) {
    e?.preventDefault();
    if (!msg.trim()) return;
    setBusy(true);
    try {
      const res = await fetch(`${API_BASE}/chat`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: msg })
      });
      if (!res.ok) throw new Error(`Send failed: ${res.status}`);
      await res.json().catch(() => ({}));
      setMsg("");
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
        {/* Voice control (non-negotiable): cheerful female, free tier */}
        <button aria-label="Voice" type="button" onClick={handleSpeak} className="rounded-2xl px-3 py-2 shadow-sm">🎙</button>
      </div>
      <form onSubmit={sendMessage} className="flex items-center gap-2">
        <input
          name="message"
          value={msg}
          onChange={(e) => setMsg(e.target.value)}
          placeholder="Type a message…"
          className="flex-1 rounded-xl px-3 py-2 bg-transparent border border-neutral-700"
        />
        <button type="submit" disabled={busy} className="rounded-xl px-3 py-2 shadow-sm border border-neutral-700">
          {busy ? "Sending…" : "Send"}
        </button>
      </form>
    </div>
  );
}
