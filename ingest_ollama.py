# ingest_ollama.py
# LAN-only; zero-cost. Requires: PyPDF2 (pure python), requests.
# Env:
#   OLLAMA_URL (default http://127.0.0.1:11434)
#   OLLAMA_EMBED_MODEL (default nomic-embed-text)
#   QDRANT_URL (default http://127.0.0.1:6333)
#   QDRANT_COLLECTION (default active_pdfs_v1)
#   CI_ENFORCE = off|soft|hard  (default soft)
#   ALLOWLIST_PATH (default C:\\Ops_Repository\\ci_allowlist.txt)
#
# CI line searched in PDFs:
#   "Behaviours governed by CI (see current instructions)."

import os, glob, json, hashlib, fnmatch, time
from pathlib import Path
import requests
from PyPDF2 import PdfReader

OLLAMA_URL = os.getenv("OLLAMA_URL", "http://127.0.0.1:11434")
EMBED_MODEL = os.getenv("OLLAMA_EMBED_MODEL", "nomic-embed-text")
QDRANT_URL  = os.getenv("QDRANT_URL", "http://127.0.0.1:6333")
COLLECTION  = os.getenv("QDRANT_COLLECTION", "active_pdfs_v1")
CI_ENFORCE  = os.getenv("CI_ENFORCE", "soft").lower()
ALLOWLIST_PATH = os.getenv("ALLOWLIST_PATH", r"C:\Ops_Repository\ci_allowlist.txt")
CI_SENTINEL = "Behaviours governed by CI (see current instructions)."

PDF_GLOB = r"C:\Ops_Repository\Active\*.pdf"  # adjust if needed
VECTOR_SIZE = 768  # nomic-embed-text

def _load_allowlist():
    patterns = []
    p = Path(ALLOWLIST_PATH)
    if p.exists():
        for line in p.read_text(encoding="utf-8").splitlines():
            s = line.strip()
            if not s or s.startswith("#"): 
                continue
            patterns.append(s)
    return patterns

def _is_allowed_by_glob(path: str, patterns):
    # if no allowlist file, default allow all
    if not patterns:
        return True
    for pat in patterns:
        if fnmatch.fnmatch(path, pat):
            return True
    return False

def _pdf_has_ci_line(pdf_path: str) -> bool:
    try:
        reader = PdfReader(pdf_path)
        for page in reader.pages:
            text = (page.extract_text() or "").strip()
            if not text:
                continue
            if CI_SENTINEL in text:
                return True
        return False
    except Exception as e:
        print(f"[WARN] CI check failed for {pdf_path}: {e}")
        return False

def _read_pdf_yield_pages(pdf_path: str):
    reader = PdfReader(pdf_path)
    for i, page in enumerate(reader.pages):
        txt = (page.extract_text() or "").strip()
        if txt:
            yield i, txt

def _embed_ollama(text: str):
    # Primary: {"prompt": "..."} (Ollama 0.11.8 nomic-embed-text quirk)
    url = f"{OLLAMA_URL}/api/embeddings"
    headers = {"Content-Type": "application/json"}
    body_primary = {"model": EMBED_MODEL, "prompt": text}
    resp = requests.post(url, headers=headers, data=json.dumps(body_primary), timeout=60)
    if resp.ok:
        out = resp.json()
        vec = out.get("embedding") or out.get("data", [{}])[0].get("embedding")
        if vec:
            return vec
    # Fallback: {"input": "..."}
    body_fallback = {"model": EMBED_MODEL, "input": text}
    resp2 = requests.post(url, headers=headers, data=json.dumps(body_fallback), timeout=60)
    if resp2.ok:
        out2 = resp2.json()
        vec2 = out2.get("embedding") or out2.get("data", [{}])[0].get("embedding")
        if vec2:
            return vec2
    raise RuntimeError(f"Ollama embeddings failed for text len={len(text)}")

def _qdrant_upsert(points):
    url = f"{QDRANT_URL}/collections/{COLLECTION}/points?wait=true"
    payload = {"points": points}
    r = requests.put(url, json=payload, timeout=60)
    if not r.ok:
        raise RuntimeError(f"Qdrant upsert failed: {r.status_code} {r.text}")

def _ensure_collection():
    # create if not exists with expected vector size/cosine
    url_col = f"{QDRANT_URL}/collections/{COLLECTION}"
    r = requests.get(url_col, timeout=10)
    if r.status_code == 200:
        return
    spec = {
        "vectors": {"size": VECTOR_SIZE, "distance": "Cosine"},
        # exact=true avoids HNSW recall surprises for small sets
        "optimizers_config": {"indexing_threshold": 2000}
    }
    rc = requests.put(url_col, json=spec, timeout=30)
    if not rc.ok:
        raise RuntimeError(f"Create collection failed: {rc.status_code} {rc.text}")

def _point_id(pdf_path: str, page_no: int):
    raw = f"{pdf_path}|{page_no}"
    return int(hashlib.md5(raw.encode("utf-8")).hexdigest()[:12], 16)

def main():
    print(f"[INFO] OLLAMA={OLLAMA_URL}  MODEL={EMBED_MODEL}  QDRANT={QDRANT_URL}  COL={COLLECTION}")
    print(f"[INFO] CI_ENFORCE={CI_ENFORCE}  ALLOWLIST={ALLOWLIST_PATH}")
    patterns = _load_allowlist()
    _ensure_collection()

    pdfs = sorted(glob.glob(PDF_GLOB))
    if not pdfs:
        print(f"[WARN] No PDFs found via {PDF_GLOB}")
        return

    batch = []
    total_pages = 0
    ingested_pages = 0
    start = time.time()

    for f in pdfs:
        f_norm = str(Path(f))
        if not _is_allowed_by_glob(f_norm, patterns):
            print(f"[SKIP] Not in allowlist: {f_norm}")
            continue

        has_ci = _pdf_has_ci_line(f_norm)
        if CI_ENFORCE == "hard" and not has_ci:
            print(f"[SKIP] Missing CI sentinel (hard): {f_norm}")
            continue
        if CI_ENFORCE == "soft" and not has_ci:
            print(f"[SOFT] Missing CI sentinel: {f_norm} (ingesting anyway)")

        for page_no, text in _read_pdf_yield_pages(f_norm):
            total_pages += 1
            try:
                vec = _embed_ollama(text)
                if len(vec) != VECTOR_SIZE:
                    raise RuntimeError(f"Vector size mismatch: {len(vec)}")
                pid = _point_id(f_norm, page_no)
                payload = {
                    "id": pid,
                    "vector": vec,
                    "payload": {
                        "path": f_norm,
                        "page": page_no,
                        "ci_ok": has_ci,
                        "ci_mode": CI_ENFORCE,
                        "sha1": hashlib.sha1((text[:2000]).encode("utf-8")).hexdigest()
                    }
                }
                batch.append(payload)
                ingested_pages += 1
                # Upsert in small chunks to keep memory low
                if len(batch) >= 32:
                    _qdrant_upsert(batch)
                    print(f"[UPSERT] {len(batch)} points")
                    batch.clear()
            except Exception as e:
                print(f"[ERR] {f_norm}#p{page_no}: {e}")

    if batch:
        _qdrant_upsert(batch)
        print(f"[UPSERT] {len(batch)} points (final)")

    dur = time.time() - start
    print(f"[DONE] pages_total={total_pages} pages_ingested={ingested_pages} in {dur:.1f}s")

if __name__ == "__main__":
    main()
