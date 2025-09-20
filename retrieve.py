import numpy as np, requests, psycopg, json
from qdrant_client import QdrantClient
from config import *

def embed_query(q):
    r = requests.post(f"{OLLAMA_URL}/api/embeddings", json={"model": EMBED_MODEL, "prompt": q})
    r.raise_for_status()
    return np.array(r.json()["embedding"], dtype=np.float32)

def mmr(qv, vecs, k=TOP_K, lam=0.5):
    vecs = vecs / (np.linalg.norm(vecs, axis=1, keepdims=True) + 1e-8)
    qv = qv / (np.linalg.norm(qv) + 1e-8)
    sim = vecs @ qv
    sel, rem = [], list(range(len(vecs)))
    while rem and len(sel) < k:
        if not sel:
            i = int(np.argmax(sim[rem])); sel.append(rem.pop(i))
        else:
            div = np.max(vecs[sel] @ vecs[rem].T, axis=0)
            score = lam * sim[rem] - (1-lam) * div
            i = int(np.argmax(score)); sel.append(rem.pop(i))
    return sel

def search(q_text):
    qv = embed_query(q_text)
    qc = QdrantClient(url=QDRANT_URL)
    res = qc.search(collection_name=QDRANT_COLLECTION, query_vector=qv.tolist(),
                    limit=20, with_payload=True, score_threshold=SCORE_THRESHOLD)
    if not res: return []
    v = np.array([np.array(r.vector, dtype=np.float32) for r in res])
    picks = mmr(qv, v, k=TOP_K)
    return [res[i] for i in picks]

def chat(thread_id, user_text):
    hits = search(user_text)
    if not hits:
        return {"answer":"No evidence found in Active PDFs. Please add a compliant PDF to Ops_Repository/Active and re-try.", "citations":[]}
    ctx, cites = [], []
    for h in hits:
        p = h.payload
        ctx.append(f"[{p['file_name']} p.{p['page']}]")
        cites.append({"file": p["file_name"], "page": p["page"]})
    prompt = ("You are an audit-friendly assistant. Answer strictly from the provided sources. "
              "Cite file name and page in-line like [file p.X]. If uncertain, say 'No evidence found.'\n\n"
              f"USER: {user_text}\nSOURCES: {' '.join(ctx)}")
    r = requests.post(f"{OLLAMA_URL}/api/generate", json={"model": CHAT_MODEL, "prompt": prompt, "options":{"temperature":0.2}})
    r.raise_for_status()
    out = r.json().get("response","").strip()
    with psycopg.connect(PG_DSN, autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO messages(thread_id, role, content, citations) VALUES (%s,'user',%s,'[]')", (thread_id, user_text))
            cur.execute("INSERT INTO messages(thread_id, role, content, citations) VALUES (%s,'assistant',%s,%s)", (thread_id, out, json.dumps(cites)))
            cur.execute("UPDATE threads SET last_seen=now() WHERE id=%s", (thread_id,))
    return {"answer": out, "citations": cites}
