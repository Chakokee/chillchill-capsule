import os, hashlib, fitz
import numpy as np, requests
from qdrant_client import QdrantClient
from qdrant_client.http import models as qm
import psycopg
from psycopg.rows import dict_row
from tqdm import tqdm
from config import *

def sha256_of_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()

def ensure_pg():
    import time
    for i in range(10):
        try:
            with psycopg.connect(PG_DSN, autocommit=True) as conn:
                conn.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto;")
            return
        except Exception as e:
            if i == 9: raise
            time.sleep(1)

def register_source(conn, file_path, file_name, sha, pages):
    with conn.cursor() as cur:
        cur.execute("""
            INSERT INTO sources(file_path,file_name,sha256,pages)
            VALUES (%s,%s,%s,%s)
            ON CONFLICT (file_path) DO UPDATE
            SET sha256=EXCLUDED.sha256, pages=EXCLUDED.pages
            RETURNING id;
        """, (file_path, file_name, sha, pages))
        row = cur.fetchone()
        return row["id"] if isinstance(row, dict) else row[0]


def chunk_text(text, max_len=CHUNK_TOKENS, overlap=CHUNK_OVERLAP):
    step = max_len - overlap
    return [ text[i:i+max_len] for i in range(0, len(text), step) ]

def embed(texts):
    r = requests.post(f"{OLLAMA_URL}/api/embeddings", json={"model": EMBED_MODEL, "prompt": texts})
    r.raise_for_status()
    return [ np.array(e["embedding"], dtype=np.float32) for e in r.json()["embeddings"] ]

def ensure_qdrant(client, dim):
    try:
        client.get_collection(QDRANT_COLLECTION)
    except Exception:
        client.recreate_collection(QDRANT_COLLECTION, qm.VectorParams(size=dim, distance=qm.Distance.COSINE))

def main():
    ensure_pg()
    client = QdrantClient(url=QDRANT_URL)
    all_points = []

    with psycopg.connect(PG_DSN, row_factory=dict_row) as conn:
        pdfs = [os.path.join(ACTIVE_DIR, f) for f in os.listdir(ACTIVE_DIR) if f.lower().endswith(".pdf")]
        for pdf in tqdm(pdfs, desc="PDFs"):
            sha = sha256_of_file(pdf)
            doc = fitz.open(pdf)
            sid = register_source(conn, pdf, os.path.basename(pdf), sha, len(doc))
            for pn in range(len(doc)):
                text = doc[pn].get_text("text")
                chunks = chunk_text(text)
                if not chunks: continue
                vecs = embed(chunks)
                for idx, v in enumerate(vecs):
                    all_points.append(qm.PointStruct(
                        id=f"{sid}_{pn+1}_{idx}",
                        vector=v.tolist(),
                        payload={"file_id": str(sid), "file_name": os.path.basename(pdf), "file_path": pdf,
                                 "page": pn+1, "chunk_index": idx, "sha256": sha}
                    ))
            doc.close()

    if not all_points:
        print("No chunks produced."); return
    dim = len(all_points[0].vector)
    ensure_qdrant(client, dim)

    BATCH=256
    for i in tqdm(range(0, len(all_points), BATCH), desc="Upserting"):
        client.upsert(collection_name=QDRANT_COLLECTION, points=all_points[i:i+BATCH])
    print("Ingestion complete.")

if __name__ == "__main__":
    main()
