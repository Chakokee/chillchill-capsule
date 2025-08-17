# C:\AiProject\ingest\ingest_docs.py
# Deterministic ingestion for PDF, DOCX, XLSX into Qdrant (http://localhost:6333)
# Usage (PowerShell):  python .\ingest\ingest_docs.py --root "C:\Docs" --glob "*.pdf;*.docx;*.xlsx"
# Env:
#   QDRANT_URL (default http://localhost:6333)
#   QDRANT_COLLECTION (default chill_docs)
#   EMBED_DIM (default 1536) -- placeholder if you later attach vectors

import argparse
import hashlib
import json
import os
import re
import sys
import uuid
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Iterable

# ---- Light dependencies ----
# pip install requests python-docx pandas openpyxl pypdf
import requests
from docx import Document as DocxDocument
import pandas as pd
from pypdf import PdfReader

QDRANT_URL = os.getenv("QDRANT_URL", "http://localhost:6333")
COLLECTION = os.getenv("QDRANT_COLLECTION", "chill_docs")
EMBED_DIM = int(os.getenv("EMBED_DIM", "1536"))

CHUNK_SIZE = 900
CHUNK_OVERLAP = 150
VALID_EXTS = {".pdf", ".docx", ".xlsx"}

def norm_ws(text: str) -> str:
    text = re.sub(r"\r\n?", "\n", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()

def chunk_text(text: str, chunk_size=CHUNK_SIZE, overlap=CHUNK_OVERLAP) -> List[str]:
    if not text:
        return []
    chunks = []
    i = 0
    n = len(text)
    while i < n:
        end = min(i + chunk_size, n)
        chunks.append(text[i:end])
        if end == n:
            break
        i = max(0, end - overlap)
    return chunks

def load_pdf(p: Path) -> str:
    try:
        reader = PdfReader(str(p))
        pages = []
        for page in reader.pages:
            try:
                pages.append(page.extract_text() or "")
            except Exception:
                pages.append("")
        return norm_ws("\n\n".join(pages))
    except Exception as e:
        return f"[PDF_PARSE_ERROR] {e}"

def load_docx(p: Path) -> str:
    try:
        doc = DocxDocument(str(p))
        paras = [para.text for para in doc.paragraphs]
        return norm_ws("\n".join(paras))
    except Exception as e:
        return f"[DOCX_PARSE_ERROR] {e}"

def load_xlsx(p: Path) -> str:
    try:
        xls = pd.ExcelFile(str(p))
        blocks = []
        for name in xls.sheet_names:
            try:
                df = xls.parse(name).fillna("")
                text = df.to_csv(index=False)
                blocks.append(f"### SHEET: {name}\n{text}")
            except Exception as e:
                blocks.append(f"### SHEET: {name}\n[XLSX_SHEET_ERROR] {e}")
        return norm_ws("\n\n".join(blocks))
    except Exception as e:
        return f"[XLSX_PARSE_ERROR] {e}"

def extract_text(p: Path) -> str:
    ext = p.suffix.lower()
    if ext == ".pdf":
        return load_pdf(p)
    if ext == ".docx":
        return load_docx(p)
    if ext == ".xlsx":
        return load_xlsx(p)
    return ""

def iter_files(root: Path, patterns: List[str]) -> Iterable[Path]:
    pats = [pat.strip() for pat in patterns if pat.strip()]
    for pat in pats:
        for path in root.rglob(pat):
            if path.is_file() and path.suffix.lower() in VALID_EXTS:
                yield path

def http_upsert(points: List[Dict]) -> None:
    url = f"{QDRANT_URL}/collections/{COLLECTION}/points?wait=true"
    body = {"points": points}
    r = requests.put(url, json=body, timeout=30)
    if r.status_code != 200:
        raise RuntimeError(f"Qdrant upsert failed: {r.status_code} {r.text}")

def make_point_id(source_path: str, created_at: int, chunk_index: int, chunk_head: str) -> str:
    """
    Deterministic UUIDv5 from a stable string (file path + timestamps + chunk info).
    Qdrant accepts integer or UUID; use UUIDv5 for stability and compliance.
    """
    seed = f"{source_path}|{created_at}|{chunk_index}|{chunk_head}"
    return str(uuid.uuid5(uuid.NAMESPACE_URL, seed))

def build_points(p: Path, text: str) -> List[Dict]:
    stat = p.stat()
    created_at = int(stat.st_mtime)
    base_payload = {
        "source_path": str(p),
        "filename": p.name,
        "ext": p.suffix.lower(),
        "doc_type": p.suffix.lower().lstrip("."),
        "created_at": created_at,
    }
    chunks = chunk_text(text)
    points = []
    for i, ch in enumerate(chunks):
        pid = make_point_id(str(p), created_at, i, ch[:40])
        payload = dict(base_payload)
        payload.update({
            "chunk_index": i,
            "chunk_size": len(ch),
            "content": ch,
        })
        points.append({
            "id": pid,          # UUID string
            "payload": payload  # vectors can be added later in a backfill job
        })
    return points

def main():
    ap = argparse.ArgumentParser(description="Deterministic document ingestion -> Qdrant")
    ap.add_argument("--root", required=True, help="Root directory to scan")
    ap.add_argument("--glob", default="*.pdf;*.docx;*.xlsx", help="Semicolon-separated patterns")
    ap.add_argument("--batch", type=int, default=128, help="Upsert batch size")
    args = ap.parse_args()

    root = Path(args.root).expanduser().resolve()
    if not root.exists():
        print(f"[ERR] Root not found: {root}")
        sys.exit(1)

    patterns = args.glob.split(";")
    total_files = 0
    total_chunks = 0
    batch = []
    for p in iter_files(root, patterns):
        total_files += 1
        text = extract_text(p)
        if text.startswith("[PDF_PARSE_ERROR]") or text.startswith("[DOCX_PARSE_ERROR]") or text.startswith("[XLSX_PARSE_ERROR]"):
            print(f"[WARN] Parse error in {p.name}: {text[:120]}")
            continue
        pts = build_points(p, text)
        total_chunks += len(pts)
        for pt in pts:
            batch.append(pt)
            if len(batch) >= args.batch:
                http_upsert(batch)
                batch.clear()

    if batch:
        http_upsert(batch)

    print(f"[DONE] Files processed: {total_files}, chunks upserted: {total_chunks} into collection '{COLLECTION}' at {QDRANT_URL}")

if __name__ == "__main__":
    main()
