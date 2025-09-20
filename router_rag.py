import os, json, requests
from fastapi import APIRouter, Query
from pydantic import BaseModel
__all__ = ["router"]
router = APIRouter(prefix="", tags=["rag"])
OLLAMA_URL = os.getenv("OLLAMA_URL","http://127.0.0.1:11434")
EMBED_MODEL = os.getenv("OLLAMA_EMBED_MODEL","nomic-embed-text")
QDRANT_URL  = os.getenv("QDRANT_URL","http://127.0.0.1:6333")
COLLECTION  = os.getenv("QDRANT_COLLECTION","active_pdfs_v1")
def _embed(text:str):
    url=f"{OLLAMA_URL}/api/embeddings"; h={"Content-Type":"application/json"}
    r=requests.post(url,headers=h,data=json.dumps({"model":EMBED_MODEL,"prompt":text}),timeout=60)
    if r.ok:
        j=r.json(); v=j.get("embedding") or (j.get("data") or [{}])[0].get("embedding")
        if v: return v
    r2=requests.post(url,headers=h,data=json.dumps({"model":EMBED_MODEL,"input":text}),timeout=60)
    if r2.ok:
        j2=r2.json(); v2=j2.get("embedding") or (j2.get("data") or [{}])[0].get("embedding")
        if v2: return v2
    raise RuntimeError("Embedding failed")
def _search_qdrant(vec, top_k:int=5):
    url=f"{QDRANT_URL}/collections/{COLLECTION}/points/search"
    payload={"vector":vec,"limit":int(top_k),"with_payload":True,"params":{"exact":True}}
    r=requests.post(url,json=payload,timeout=30)
    if not r.ok: raise RuntimeError(f"Qdrant search failed: {r.status_code} {r.text}")
    return r.json().get("result",[])
class QueryIn(BaseModel):
    q:str; top_k:int=5
@router.get("/query")
def query_get(q:str=Query(...,min_length=1), top_k:int=5):
    vec=_embed(q); hits=_search_qdrant(vec, top_k=top_k)
    return {"mode":"RAG","q":q,"top_k":top_k,"hits":[{"score":h.get("score"),
            "path":h.get("payload",{}).get("path"),"page":h.get("payload",{}).get("page"),
            "ci_ok":h.get("payload",{}).get("ci_ok")} for h in hits]}
@router.post("/query")
def query_post(body:QueryIn):
    vec=_embed(body.q); hits=_search_qdrant(vec, top_k=body.top_k)
    return {"mode":"RAG","q":body.q,"top_k":body.top_k,"hits":[{"score":h.get("score"),
            "path":h.get("payload",{}).get("path"),"page":h.get("payload",{}).get("page"),
            "ci_ok":h.get("payload",{}).get("ci_ok")} for h in hits]}
