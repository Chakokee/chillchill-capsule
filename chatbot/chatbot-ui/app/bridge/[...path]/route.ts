import { NextRequest } from "next/server";
export async function GET(req: NextRequest, { params }: { params: { path: string[] } }) {
  const tail = (params.path || []).join("/");
  const qs = req.nextUrl.search || "";
  const url = `http://api:8000/${tail}${qs}`;
  try {
    const r = await fetch(url, { cache: "no-store" });
    return new Response(await r.text(), { status: r.status, headers: { "content-type": r.headers.get("content-type") || "text/plain" } });
  } catch {
    return new Response("bridge proxy error", { status: 502 });
  }
}