#!/usr/bin/env python3
"""
ingest_docs.py — Unified document ingester for ChillChill

Supports: PDF, DOCX, XLSX, and TXT
- Deterministic UUIDv5 point IDs (stable re-ingest)
- Chunking: 900 chars with 150 char overlap
- Whitespace normalization
- Batch upsert to Qdrant via HTTP with wait=true
- Robust file discovery across patterns: "*.pdf;*.docx;*.xlsx;*.txt"

Env defaults:
  QDRANT_URL=http://localhost:6333
  COLLECTION=chill_docs
  EMBED_DIM=1536
"""

import argparse
import os
import re
import sys
import uuid
from pathlib import Path
from typing import List

import requests

# ----------------------------
# Config & helpers
# ----------------------------

QDRANT_URL = os.getenv("QDRANT_URL", "http://localhost:6333").rstrip("/")
COLLECTION = os.getenv("COLLECTION", "chill_docs")
EMBED_DIM = int(os.getenv("EMBED_DIM", "1536"))

CHUNK_SIZE = 900
CHUNK_OVERLAP = 150

WHITESPACE_RE = re.compile(r"\s+")


def norm_ws(text: str) -> str:
    return WHITESPACE_RE.sub(" ", text).strip()


def chunk_text(text: str, size: int = CHUNK_SIZE, overlap: int = CHUNK_OVERLAP) -> List[str]:
    if not text:
        return []
    chunks = []
    i = 0
    n = len(text)
    step = max(size - overlap, 1)
    while i < n:
        chunks.append(text[i : min(i + size, n)])
        if i + size >= n:
            break
        i += step
    return chunks


def deterministic_id(source: str, chunk_index: int) -> str:
    seed = f"{source}::chunk::{chunk_index}"
    return str(uuid.uuid5(uuid.NAMESPACE_URL, seed))


def ensure_collection(url: str, collection: str, vector_size: int) -> None:
    r = requests.put(f"{url}/collections/{collection}", json={
        "vectors": {"size": vector_size, "distance": "Cosine"}
    })
    # 200/201 OK; 409 = already exists (fine)
    if r.status_code not in (200, 201, 409):
        try:
            data = r.json()
        except Exception:
            data = {"error": r.text}
        print(f"[WARN] ensure_collection: {r.status_code} {data}", file=sys.stderr)


def upsert_batch(url: str, collection: str, points: List[dict]) -> None:
    if not points:
        return
    payload = {"points": points}
    r = requests.put(f"{url}/collections/{collection}/points?wait=true", json=payload, timeout=60)
    if r.status_code not in (200, 202):
        try:
            data = r.json()
        except Exception:
            data = {"error": r.text}
        raise RuntimeError(f"Upsert failed: {r.status_code} {data}")


# ----------------------------
# Readers
# ----------------------------

def read_txt(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="ignore")
    except UnicodeDecodeError:
        return path.read_text(encoding="cp1252", errors="ignore")


def read_pdf(path: Path) -> str:
    try:
        from pypdf import PdfReader
    except Exception:
        print(f"[WARN] pypdf not installed; skipping PDF: {path}", file=sys.stderr)
        return ""
    try:
        reader = PdfReader(str(path))
        return "\n".join((page.extract_text() or "") for page in reader.pages)
    except Exception as e:
        print(f"[WARN] PDF parse failed for {path}: {e}", file=sys.stderr)
        return ""


def read_docx(path: Path) -> str:
    try:
        import docx  # python-docx
    except Exception:
        print(f"[WARN] python-docx not installed; skipping DOCX: {path}", file=sys.stderr)
        return ""
    try:
        d = docx.Document(str(path))
        return "\n".join(p.text for p in d.paragraphs)
    except Exception as e:
        print(f"[WARN] DOCX parse failed for {path}: {e}", file=sys.stderr)
        return ""


def read_xlsx(path: Path) -> str:
    try:
        import pandas as pd  # requires openpyxl
    except Exception:
        print(f"[WARN] pandas/openpyxl not installed; skipping XLSX: {path}", file=sys.stderr)
        return ""
    try:
        xl = pd.ExcelFile(str(path))
        parts = []
        for sheet in xl.sheet_names:
            df = xl.parse(sheet, dtype=str)
            parts.append(df.to_string(index=False, header=True))
        return "\n".join(parts)
    except Exception as e:
        print(f"[WARN] XLSX parse failed for {path}: {e}", file=sys.stderr)
        return ""


EXT_READERS = {
    ".txt": read_txt,
    ".pdf": read_pdf,
    ".docx": read_docx,
    ".xlsx": read_xlsx,
}


# ----------------------------
# Discovery
# ----------------------------

def discover_files(root: Path, patterns: str) -> List[Path]:
    """
    patterns: semicolon-separated globs, e.g. "*.pdf;*.docx;*.xlsx;*.txt"
    """
    files = []
    pats = [p.strip() for p in patterns.split(";") if p.strip()]
    for p in pats:
        files.extend(root.rglob(p))
    unique = sorted({f.resolve() for f in files if f.is_file()})
    return unique


# ----------------------------
# Main ingest
# ----------------------------

def extract_text_for(path: Path) -> str:
    reader = EXT_READERS.get(path.suffix.lower())
    if not reader:
        print(f"[WARN] No reader for extension {path.suffix} — skipping {path}", file=sys.stderr)
        return ""
    return reader(path)


def build_points(text: str, source: str) -> List[dict]:
    text = norm_ws(text)
    chunks = chunk_text(text)
    points = []
    for idx, chunk in enumerate(chunks):
        points.append({
            "id": deterministic_id(source, idx),
            "vector": [0.0] * EMBED_DIM,  # placeholder; fill via embedder later
            "payload": {
                "source": source,
                "chunk_index": idx,
                "text": chunk,
            }
        })
    return points


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, help="Root dir to scan")
    parser.add_argument(
        "--glob",
        default="*.pdf;*.docx;*.xlsx;*.txt",
        help='Semicolon-separated patterns. Default: "*.pdf;*.docx;*.xlsx;*.txt"',
    )
    parser.add_argument("--batch", type=int, default=128, help="Upsert batch size")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    if not root.exists():
        print(f"[ERROR] Root not found: {root}", file=sys.stderr)
        sys.exit(2)

    ensure_collection(QDRANT_URL, COLLECTION, EMBED_DIM)

    files = discover_files(root, args.glob)
    processed = 0
    upserted = 0
    batch_points: List[dict] = []

    for f in files:
        text = extract_text_for(f)
        if not text:
            continue
        pts = build_points(text, source=str(f))
        processed += 1
        for p in pts:
            batch_points.append(p)
            if len(batch_points) >= args.batch:
                upsert_batch(QDRANT_URL, COLLECTION, batch_points)
                upserted += len(batch_points)
                batch_points = []

    if batch_points:
        upsert_batch(QDRANT_URL, COLLECTION, batch_points)
        upserted += len(batch_points)

    print(f"[DONE] Files processed: {processed}, chunks upserted: {upserted} into collection '{COLLECTION}' at {QDRANT_URL}")


if __name__ == "__main__":
    main()
