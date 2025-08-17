from fastapi import APIRouter, UploadFile, File, HTTPException
from pydantic import BaseModel
from typing import List, Tuple
import os, io, uuid, httpx
from pypdf import PdfReader
import chromadb
from chromadb.config import Settings

OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://ollama:11434")
EMBED_MODEL = os.getenv("OLLAMA_EMBED_MODEL", "nomic-embed-text")
DB_PATH = os.getenv("RAG_DB_PATH", "/data/chroma")

rag_router = APIRouter()

# --- Embeddings -------------------------------------------------------------
async def embed_texts(texts: List[str]) -> List[List[float]]:
    # Ollama embeddings: POST /api/embeddings { model, prompt }
    async with httpx.AsyncClient(timeout=120) as client:
        out = []
        for t in texts:
            r = await client.post(f"{OLLAMA_HOST}/api/embeddings",
                                  json={"model": EMBED_MODEL, "prompt": t})
            if r.status_code != 200:
                raise HTTPException(502, f"Embed upstream error: {r.text[:200]}")
            js = r.json()
            vec = js.get("embedding") or (js.get("data", [{}])[0].get("embedding") if js.get("data") else None)
            if not vec:
                raise HTTPException(502, "No embedding returned")
            out.append(vec)
        return out

# --- Vector store (telemetry disabled) --------------------------------------
_client = chromadb.PersistentClient(
    path=DB_PATH,
    settings=Settings(anonymized_telemetry=False)
)
_collection = _client.get_or_create_collection("docs")

def _chunk(text: str, size: int = 900, overlap: int = 150) -> List[str]:
    text = " ".join(text.split())  # collapse whitespace
    chunks, i = [], 0
    while i < len(text):
        end = min(len(text), i + size)
        chunks.append(text[i:end])
        i = end - overlap
        if i < 0: i = 0
    return [c for c in chunks if c.strip()]

def _read_file_to_text(file: UploadFile) -> Tuple[str, str]:
    name = file.filename or "upload"
    data = file.file.read()
    if name.lower().endswith(".pdf"):
        reader = PdfReader(io.BytesIO(data))
        text = "\n".join((p.extract_text() or "") for p in reader.pages)
    else:
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            text = data.decode("latin-1", errors="ignore")
    return name, text

class RagChatReq(BaseModel):
    query: str
    top_k: int | None = 4
    provider: str | None = None
    model: str | None = None
    temperature: float | None = 0.2

@rag_router.post("/ingest")
async def ingest(file: UploadFile = File(...)):
    name, text = _read_file_to_text(file)
    parts = _chunk(text)
    if not parts:
        raise HTTPException(400, "No text detected in file")

    embs = await embed_texts(parts)
    ids = [str(uuid.uuid4()) for _ in parts]
    metas = [{"filename": name, "chunk": i} for i, _ in enumerate(parts)]
    _collection.upsert(documents=parts, embeddings=embs, metadatas=metas, ids=ids)
    return {"ok": True, "chunks": len(parts), "filename": name}

@rag_router.post("/chat")
async def rag_chat(req: RagChatReq):
    if not req.query.strip():
        raise HTTPException(400, "Empty query")
    qv = (await embed_texts([req.query]))[0]
    res = _collection.query(query_embeddings=[qv], n_results=req.top_k or 4)
    docs = (res.get("documents") or [[]])[0]
    metas = (res.get("metadatas") or [[]])[0]

    context = "\n\n".join(
        f"[{m.get('filename','doc')}#{m.get('chunk',0)}]\n{d}"
        for d, m in zip(docs, metas)
    )
    prompt = f"""Use the context to answer. If unsure, say so.
Context:
{context}

Question: {req.query}
Answer:"""

    from providers import chat_with_fallback
    reply = await chat_with_fallback(
        req.provider or "ollama",
        req.model or "llama3:8b",
        prompt,
        req.temperature or 0.2
    )
    return {"reply": reply}

@rag_router.get("/stats")
def stats():
    try:
        return {"ok": True, "count": _collection.count()}
    except Exception as e:
        raise HTTPException(500, str(e))

@rag_router.post("/reset")
def reset():
    try:
        global _collection
        _client.delete_collection("docs")
        _collection = _client.get_or_create_collection("docs")
        return {"ok": True}
    except Exception as e:
        raise HTTPException(500, str(e))
