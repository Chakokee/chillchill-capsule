# C:\ChillChill\app\main.py
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import httpx

# Import your existing RAG router (this provided the working /query earlier)
# router_rag.py should define: router = APIRouter(...) with GET /query
from router_rag import router as rag_router

app = FastAPI(title="ChillChill API", version="2.1")

# --- CORS for local dev ---
origins = [
    "http://localhost:8080",
    "http://127.0.0.1:8080",
    "http://localhost:5678",
    "http://127.0.0.1:5678",
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins + ["*"],  # keep "*" for LAN dev; tighten later
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Health model/route (keep simple) ---
class Health(BaseModel):
    status: str = "ok"

@app.get("/healthz", response_model=Health)
def healthz():
    return {"status": "ok"}

# --- Mount the original RAG routes (restores the real /query) ---
app.include_router(rag_router)

# --- /chat wrapper that reuses the restored /query endpoint ---
class ChatIn(BaseModel):
    q: str
    top_k: int | None = None

@app.post("/chat")
def chat(body: ChatIn):
    params = {"q": body.q}
    if body.top_k:
        params["top_k"] = body.top_k
    # Call the mounted /query (served by router_rag) to avoid duplication
    with httpx.Client(timeout=10.0) as client:
        r = client.get("http://127.0.0.1:8000/query", params=params)
        r.raise_for_status()
        return r.json()
