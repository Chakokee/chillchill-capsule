from router_rag import rag_router
from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn
from retrieve import chat

app = FastAPI()
app.include_router(rag_router)

class Ask(BaseModel):
    thread_id: str
    question: str

@app.post("/ask")
def ask(q: Ask):
    return chat(q.thread_id, q.question)

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8000)



from fastapi import Query as _Q
from pydantic import BaseModel as _BM
class _QA(_BM):
    answer: str
    citations: list[str] = []
@app.get("/query", response_model=_QA)
def query(q: str = _Q(...), k: int = _Q(5, ge=1, le=20)):
    # TODO: replace with router_rag implementation; temporary smoke test
    return _QA(answer=f"Echo: {q} (k={k})", citations=[])

from fastapi import Query as _Q
from pydantic import BaseModel as _BM

class _QA(_BM):
    answer: str
    citations: list[str] = []

@app.get("/query", response_model=_QA)
def _cc_query(q: str = _Q(...), k: int = _Q(5, ge=1, le=20)):
    # TEMP shim; replace with router_rag implementation
    return _QA(answer=f"Echo: {q} (k={k})", citations=[])
