import os, json, requests

# --- Gemini minimal REST client ---
# Uses: GEMINI_API_KEY, GEMINI_MODEL (default: gemini-1.5-flash)
def gemini_chat(prompt: str) -> str:
    api_key = os.getenv("GEMINI_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("gemini: missing GEMINI_API_KEY")
    model = os.getenv("GEMINI_MODEL", "gemini-1.5-flash")
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
    payload = {"contents":[{"parts":[{"text": prompt}]}]}
    try:
        r = requests.post(url, data=json.dumps(payload), headers={"Content-Type":"application/json"}, timeout=20)
    except Exception as e:
        raise RuntimeError(f"gemini: request failed: {e}")
    if r.status_code >= 400:
        raise RuntimeError(f"gemini: HTTP {r.status_code}: {r.text[:200]}")
    data = r.json()
    # Extract text safely
    try:
        cands = data.get("candidates", [])
        if not cands: raise KeyError("no candidates")
        parts = cands[0].get("content", {}).get("parts", [])
        if not parts: raise KeyError("no parts")
        text = parts[0].get("text", "").strip()
        if not text: raise KeyError("empty text")
        return text
    except Exception as e:
        raise RuntimeError(f"gemini: bad response shape: {e}; raw={str(data)[:200]}")

# --- Groq stub (raise unless key is present) ---
def groq_chat(prompt: str) -> str:
    key = os.getenv("GROQ_API_KEY","").strip()
    if not key:
        raise RuntimeError("groq: missing GROQ_API_KEY")
    # If you later wire groq, replace this with a real call via requests to Groq API.
    raise RuntimeError("groq: not implemented")

# --- OpenAI stub (disabled by OPENAI_ENABLED=false in .env) ---
def openai_chat(prompt: str) -> str:
    raise RuntimeError("openai: disabled / not implemented in this build")

# --- Ollama minimal REST client ---
# Uses: OLLAMA_HOST (default http://ollama:11434), OLLAMA_MODEL (default llama3.2:3b)
def ollama_chat(prompt: str) -> str:
    host = os.getenv("OLLAMA_HOST","http://ollama:11434").rstrip("/")
    model = os.getenv("OLLAMA_MODEL","llama3.2:3b")
    url = f"{host}/api/generate"
    payload = {"model": model, "prompt": prompt, "stream": False}
    try:
        r = requests.post(url, data=json.dumps(payload), headers={"Content-Type":"application/json"}, timeout=20)
    except Exception as e:
        raise RuntimeError(f"ollama: request failed: {e}")
    if r.status_code >= 400:
        raise RuntimeError(f"ollama: HTTP {r.status_code}: {r.text[:200]}")
    data = r.json()
    out = (data.get("response") or "").strip()
    if not out:
        raise RuntimeError("ollama: empty response")
    return out
