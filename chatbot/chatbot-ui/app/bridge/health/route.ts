export async function GET() {
  try {
    const r = await fetch('http://api:8000/health', { cache: 'no-store' });
    return new Response(await r.text(), { status: r.status, headers: { 'content-type': r.headers.get('content-type') || 'text/plain' } });
  } catch {
    return new Response('bridge health proxy error', { status: 502 });
  }
}
