# C:\AiProject\init_vector.py
# Initializes a Qdrant collection with tuned HNSW params and a payload index.
# Requires: Python 3.x on host. Uses only standard lib + requests (bundled with Python on Windows via pip if needed).
# If 'requests' is missing: pip install requests

import json
import os
import sys
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

QDRANT_URL = os.environ.get("QDRANT_URL", "http://localhost:6333")
COLLECTION = os.environ.get("QDRANT_COLLECTION", "chill_docs")
VECTOR_SIZE = int(os.environ.get("EMBED_DIM", "1536"))  # <-- set to your embedding dimension
DISTANCE = "Cosine"

def http(method, path, body=None):
    url = f"{QDRANT_URL}{path}"
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    try:
        with urlopen(req, timeout=10) as resp:
            return resp.getcode(), json.loads(resp.read().decode("utf-8") or "{}")
    except HTTPError as e:
        try:
            detail = e.read().decode("utf-8")
        except Exception:
            detail = str(e)
        return e.code, {"error": detail}
    except URLError as e:
        return 0, {"error": str(e)}

def ensure_collection():
    # Check if collection exists
    code, data = http("GET", f"/collections/{COLLECTION}")
    if code == 200:
        print(f"[OK] Collection '{COLLECTION}' already exists.")
        return True

    if code not in (404, 0):
        print(f"[WARN] Unexpected status checking collection: {code} {data}")
    print(f"[INFO] Creating collection '{COLLECTION}' ...")

    body = {
        "vectors": {
            "size": VECTOR_SIZE,
            "distance": DISTANCE
        },
        "hnsw_config": {
            "m": 32,
            "ef_construct": 256,
            "full_scan_threshold": 10000
        },
        "optimizers_config": {
            "default_segment_number": 2
        },
        "quantization_config": None,  # can enable scalar/product quantization later if needed
        "on_disk_payload": True
    }
    code, data = http("PUT", f"/collections/{COLLECTION}", body)
    if code == 200:
        print(f"[OK] Collection '{COLLECTION}' created.")
        return True
    print(f"[ERR] Failed to create collection: {code} {data}")
    return False

def create_payload_index():
    # Example: create a payload index on "doc_type" (string) and "created_at" (int64)
    # Adjust to your metadata fields as you ingest.
    indexes = [
        {"field_name": "doc_type", "field_schema": "keyword"},
        {"field_name": "created_at", "field_schema": "integer"}
    ]
    for idx in indexes:
        code, data = http("PUT", f"/collections/{COLLECTION}/index", idx)
        if code == 200:
            print(f"[OK] Payload index created for {idx['field_name']}")
        else:
            print(f"[WARN] Could not create index for {idx['field_name']}: {code} {data}")

if __name__ == "__main__":
    if not ensure_collection():
        sys.exit(1)
    create_payload_index()
    print("[DONE] Vector collection is ready.")
