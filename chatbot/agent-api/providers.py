import os, requests

TIMEOUT = float(os.getenv("PROVIDER_TIMEOUT", "20"))

def _groq_call(prompt: str):
    key = os.getenv("GROQ_API_KEY")
    if not key: return None
    url = "https://api.groq.com/openai/v1/chat/completions"
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    for model in ("llama3-8b-8192", "llama-3.1-8b-instant"):
        try:
            r = requests.post(url, headers=headers, json={
                "model": model,
                "messages": [{"role":"user","content": prompt}],
                "max_tokens": 256
            }, timeout=TIMEOUT)
            if r.status_code != 200:
                continue
            j = r.json()
            return (j.get("choices",[{}])[0].get("message",{}).get("content") or "").strip() or None
        except Exception:
            continue
    return None

def _gemini_call(prompt: str):
    key = os.getenv("GEMINI_API_KEY")
    if not key: return None
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={key}"
    try:
        r = requests.post(url, json={"contents":[{"parts":[{"text": prompt}]}]}, timeout=TIMEOUT)
        if r.status_code != 200:
            return None
        j = r.json()
        c = j.get("candidates") or []
        if not c: return None
        parts = (c[0].get("content") or {}).get("parts") or []
        if not parts: return None
        return (parts[0].get("text") or "").strip() or None
    except Exception:
        return None

def _mistral_call(prompt: str):
    key = os.getenv("MISTRAL_API_KEY")
    if not key: return None
    url = "https://api.mistral.ai/v1/chat/completions"
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    try:
        r = requests.post(url, headers=headers, json={
            "model":"mistral-small-latest",
            "messages":[{"role":"user","content": prompt}],
            "max_tokens":256
        }, timeout=TIMEOUT)
        if r.status_code != 200:
            return None
        j = r.json()
        return (j.get("choices",[{}])[0].get("message",{}).get("content") or "").strip() or None
    except Exception:
        return None

def chat_reply(prompt: str) -> str | None:
    prompt = (prompt or "").strip() or "Say OK."
    for name, fn in (("groq", _groq_call), ("gemini", _gemini_call), ("mistral", _mistral_call)):
        try:
            print(f"[PROVIDER] selected={name}")
            out = fn(prompt)
            if out:
                return out
        except Exception as e:
            print(f"[PROVIDER] {name} error: {e}")
    return None
