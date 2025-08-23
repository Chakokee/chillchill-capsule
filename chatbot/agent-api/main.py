from fastapi import FastAPI, Response, Body
from fastapi.middleware.cors import CORSMiddleware
import os

app = FastAPI(title="ChillChill API")

# CORS for the browser UI
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000", "*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
async def health():
    return {"ok": True}

@app.get("/voice/health")
async def voice_health():
    # lightweight liveness; we don't ping Piper here to keep it fast
    return {"voice": "ok"}

@app.post("/chat")
async def chat(payload: dict = Body(None)):
    msg = ((payload or {}).get("message") or "").strip()
    if not msg:
        return {"reply": "Say something and I’ll respond."}
    reply = f"assistant reply: {msg}. I’m ChillChill—voice is free and active."
    return {"reply": reply}

# --- Piper (Wyoming) TTS ---
async def _piper_synthesize(text: str, host: str, port: int) -> bytes:
    # Import inside function to avoid import errors at startup if package missing
    import anyio
    from wyoming.client import Client
    from wyoming.audio import AudioFormat
    from wyoming.tts import Synthesize, AudioChunk, SynthesizeResponse

    async with await Client.connect(host, port) as client:
        fmt = AudioFormat(encoding="wav", rate=24000, width=2, channels=1)
        await client.write_event(Synthesize(text=text, audio_format=fmt).event())
        chunks = bytearray()
        while True:
            event = await client.read_event()
            if event is None:
                break
            if AudioChunk.is_type(event.type):
                ac = AudioChunk.from_event(event)
                chunks.extend(ac.audio)
            elif SynthesizeResponse.is_type(event.type):
                resp = SynthesizeResponse.from_event(event)
                if getattr(resp, "error", None):
                    raise RuntimeError(f"Piper synth error: {resp.error}")
                break
    return bytes(chunks)

@app.post("/voice/speak")
async def voice_speak(payload: dict = Body(None)):
    text = (payload or {}).get("text") or "Hello from ChillChill. Voice is active and free."
    host = os.getenv("PIPER_HOST", "piper")
    port = int(os.getenv("PIPER_PORT", "10200"))
    try:
        audio = await _piper_synthesize(text, host, port)
        return Response(content=audio, media_type="audio/wav")
    except Exception as e:
        # Return 503 with short explanation; UI already handles failures gracefully
        return Response(content=f"TTS error: {e}".encode("utf-8"), media_type="text/plain", status_code=503)


