"use client";

import { useState } from "react";

export default function AppClient() {
  const [message, setMessage] = useState("");
  const [reply, setReply] = useState<string>("(no response yet)");
  const [busy, setBusy] = useState(false);
  const [ping, setPing] = useState<string>("");

  async function sendMessage() {
    if (!message.trim()) return;
    setBusy(true);
    setReply("…");
    try {
      const res = await fetch("/bridge/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message }),
      });
      const data = await res.json();
      const text = typeof data?.answer === "string" ? data.answer : JSON.stringify(data);
      setReply(text);
    } catch (err) {
      setReply("Error: " + String(err));
    } finally {
      setBusy(false);
    }
  }

  async function doPing() {
    try {
      const r = await fetch("/api/health");
      setPing(`health: ${r.status}`);
    } catch (e) {
      setPing("health: error");
    }
  }

  return (
    <div className="p-4 space-y-3">
      <h1 className="text-3xl font-bold">ChillChill</h1>

      <div className="flex gap-2 items-center">
        <input
          className="border p-2 text-black flex-grow"
          placeholder="Type a message..."
          value={message}
          onChange={(e) => setMessage(e.target.value)}
        />
        <button
          className="bg-blue-600 text-white px-4 py-2 rounded disabled:opacity-50"
          onClick={sendMessage}
          disabled={busy}
        >
          {busy ? "Sending…" : "Send"}
        </button>
        <button className="px-3 py-2 rounded bg-gray-700" onClick={doPing}>Ping</button>
        <span className="text-xs opacity-80">{ping}</span>
      </div>

      <div className="bg-neutral-900 text-white p-4 rounded min-h-[3rem] whitespace-pre-wrap">
        {reply}
      </div>
    </div>
  );
}
