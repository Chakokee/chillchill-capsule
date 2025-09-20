OLLAMA_URL = "http://127.0.0.1:11434"
EMBED_MODEL = "nomic-embed-text"
CHAT_MODEL  = "llama3.1:8b-instruct"

ACTIVE_DIR = r"C:\Ops_Repository\Active"
QDRANT_URL = "http://127.0.0.1:6333"
QDRANT_COLLECTION = "chill_docs"

import os
PG_DSN = os.getenv("PG_DSN")

CHUNK_TOKENS = 1000
CHUNK_OVERLAP = 200
TOP_K = 6
SCORE_THRESHOLD = 0.15
