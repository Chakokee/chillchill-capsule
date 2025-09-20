# -*- coding: utf-8 -*-
import os, sys, glob, hashlib, time
from datetime import datetime, timezone
from pathlib import Path
import requests
from PyPDF2 import PdfReader

ACTIVE_DIR = r"C:\Ops_Repository\Active"
TEI_URL = "http://127.0.0.1:8080"
QDRANT_URL = "http://127.0.0.1:6333"
COLL = "active_pdfs_v1"

def read_pdf(path):
    r = PdfReader(path)
    for i, page in enumerate(r.pages, start=1):
        txt = (page.extract_text() or "").strip()
        yield i, txt

def chunk(text, max_chars=1000, overlap=120):
    text = " ".join(text.split())
    out, i, n = [], 0, len(text)
    while i < n:
        end = min(n, i+max_chars)
        seg = text[i:end]
        if end < n:
            j = seg.rfind(" ")
            if j > 200:
                seg, end = seg[:j], i+j
        if seg.strip():
            out.append(seg)
        i = max(end - overlap, end)
    return out

def tei_embed(texts):
    r = requests.post(f"{TEI_URL}/embeddings", json={"input": texts}, timeout=180)
    r.raise_for_status()
    data = r.json()
    if "data" in data:
        return [d["embedding"] for d in data["data"]]
    return data["embeddings"]

def upsert(points):
    r = requests.put(f"{QDRANT_URL}/collections/{COLL}/points?wait=true", json={"points": points}, timeout=300)
    r.raise_for_status()
    return r.json()

def pid(fname, page, idx):
    s = f"{fname}|{page}|{idx}"
    return int(hashlib.md5(s.encode()).hexdigest()[:16], 16)

def main():
    pdfs = sorted(Path(ACTIVE_DIR).glob("*.pdf"))
    if not pdfs:
        print("No evidence found: Active folder has no PDFs.")
        sys.exit(1)
    total = 0
    for f in pdfs:
        name = f.name
        mtime = datetime.fromtimestamp(f.stat().st_mtime, tz=timezone.utc).isoformat()
        any_text = False
        for page_no, text in read_pdf(str(f)):
            if not text:
                continue
            any_text = True
            parts = chunk(text)
            if not parts:
                continue
            for i in range(0, len(parts), 64):
                segs = parts[i:i+64]
                vecs = tei_embed(segs)
                pts = []
                for j, (seg, vec) in enumerate(zip(segs, vecs)):
                    pts.append({
                        "id": pid(name, page_no, i+j),
                        "vector": vec,
                        "payload": {
                            "doc_id": hashlib.md5(name.encode()).hexdigest(),
                            "filename": name,
                            "path": str(f),
                            "page": page_no,
                            "chunk_idx": i+j,
                            "mtime_iso": mtime,
                            "text": seg[:1000]
                        }
                    })
                upsert(pts)
                total += len(pts)
        if not any_text:
            print(f"Warn: {name} has no extractable text (scanned/secured).")
    if total == 0:
        print("No evidence found: No text indexed from Active PDFs.")
        sys.exit(1)
    print(f"Ingestion complete. Upserted {total} chunks into '{COLL}'.")

if __name__ == "__main__":
    main()
