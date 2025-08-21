import { NextRequest, NextResponse } from "next/server";

const API_URL = process.env.API_URL || "http://api:8000/chat"; // container DNS
const API_KEY = process.env.API_KEY || ""; // server-side only

export async function POST(req: NextRequest) {
  try {
    const body = await req.text(); // pass-through JSON
    const r = await fetch(API_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(API_KEY ? { "x-api-key": API_KEY } : {}),
      },
      body,
      // Keep it simple; rely on default fetch timeout or increase if needed
    });
    const text = await r.text();
    // Preserve status but normalize response shape for the UI
    return new NextResponse(text, { status: r.status, headers: { "content-type": r.headers.get("content-type") ?? "application/json" } });
  } catch (e: any) {
    return NextResponse.json({ answer: "Bridge error. Please try again." }, { status: 200 });
  }
}
