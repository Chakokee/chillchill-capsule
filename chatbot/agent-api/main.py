# FILE: main.py — Operator clean version
# Purpose: FastAPI with real /chat routed to providers.chat_with_fallback

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import logging
from typing import Optional
import os

app = FastAPI(title="ChillChill API")

# CORS for local UI
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Models ---
class ChatReq(BaseModel):
    message: str = Field(..., description="User message")
    provider: Optional[str] = None
    model: Optional[str] = None
    use_rag: Optional[bool] = False
    temperature: Optional[float] = 0.2

# --- Config defaults ---
DEF_PROVIDER = os.getenv("LLM_PROVIDER", "openai").lower()
DEF_MODEL    = os.getenv("LLM_MODEL", "gpt-4o-mini")
ECHO_MODE    = os.getenv("CHAT_ECHO", "false").lower() in ("1","true","yes","on")

# --- Health & misc ---
@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/models")
def models():
    # Reflect common models; could be made dynamic
    return {"models": [DEF_MODEL or "gpt-4o-mini", "llama3-8b", "claude-3-haiku"]}

@app.post("/warmup")
def warmup():
    return {"warmed": True}

# --- Chat routed to providers ---
@app.post("/chat")
async def chat(req: ChatReq):
    if ECHO_MODE:
        return {"answer": f"Echo: {req.message}"}

    # Choose provider/model from request or env defaults
    provider = (req.provider or DEF_PROVIDER or "openai").lower()
    model    = (req.model or DEF_MODEL or "gpt-4o-mini")

    try:
        from providers import chat_with_fallback
        out = await chat_with_fallback(provider, model, req.message, req.temperature or 0.2)
        if not out:
            raise RuntimeError("Provider chain returned no output")
        return {"answer": out}
    except Exception as e:
        # Surface real failure so we don't silently echo
        logging.exception("chat failure"); raise HTTPException(status_code=502, detail=str(e))