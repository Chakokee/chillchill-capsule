# FILE: C:\AiProject\chatbot\agent-api\main.py
# PURPOSE: FastAPI app exposing /health, /models, /warmup, and NEW /chat
# SAFE DEFAULT: minimal echo pipeline to restore UI↔API flow; replace with real logic later

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import Optional, Dict, Any
import os, time, uuid

app = FastAPI(title="ChillChill API")

# Allow local UI origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

ENABLE_TRACE = (os.getenv("ENABLE_TRACE", "false").lower() == "true")

@app.get("/health")
def health() -> Dict[str, str]:
    return {"status": "ok"}

@app.get("/models")
def models() -> Dict[str, Any]:
    return {"models": ["gpt-4o-mini", "llama3-8b", "claude-3-haiku"]}

@app.post("/warmup")
def warmup() -> Dict[str, bool]:
    return {"warmed": True}

# NEW Chat endpoint
class ChatIn(BaseModel):
    message: str = Field(..., min_length=1)
    provider: Optional[str] = "auto"
    model: Optional[str] = None
    trace: Optional[bool] = False

class ChatOut(BaseModel):
    answer: str
    trace: Optional[Dict[str, Any]] = None

@app.post("/chat", response_model=ChatOut)
def chat(req: ChatIn) -> ChatOut:
    t0 = time.time()
    trace_id = str(uuid.uuid4())

    # Placeholder — swap with your real pipeline: route -> RAG -> LLM -> postproc
    answer = f"Echo: {req.message}"
    chosen_provider = req.provider or "auto"
    chosen_model = req.model or "default"

    payload: Dict[str, Any] = {"answer": answer}
    if ENABLE_TRACE and req.trace:
        payload["trace"] = {
            "trace_id": trace_id,
            "routing": {"provider": chosen_provider, "model": chosen_model},
            "usage": {"prompt_tokens": 0, "completion_tokens": 0, "cost_est_usd": 0.0},
            "latency_ms": int((time.time() - t0) * 1000),
        }
    return ChatOut(**payload)

@app.exception_handler(Exception)
async def unhandled_exc_handler(_, exc: Exception):
    raise HTTPException(status_code=500, detail=f"Internal error: {type(exc).__name__}")
