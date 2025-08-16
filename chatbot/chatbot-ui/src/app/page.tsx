"use client";

import React from "react";
import ChatControls from "../../components/ChatControls";

export default function Page() {
  // quick runtime probe so we know this file is actually live:
  if (typeof window !== "undefined") {
    fetch("/api/health").then(r=>r.json()).then(x=>console.log("[page.tsx] /api/health =", x)).catch(console.error);
  }
  return (
    <main className="p-4 space-y-4">
      <h1 className="text-2xl font-bold">ChillChill</h1>
      <ChatControls />
    </main>
  );
}
