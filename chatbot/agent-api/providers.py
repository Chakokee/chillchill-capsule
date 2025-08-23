PROVIDER_ORDER = ['ollama','groq','gemini','openai']
OLLAMA_MODEL = 'llama3.2:3b'
GROQ_MODEL = 'llama3-70b-8192'
import os
from typing import List, Callable

class ProviderError(Exception): pass

def _has(var: str) -> bool:
    v = os.getenv(var, "").strip()
    return len(v) > 0

def _enabled(var: str, default: bool=True) -> bool:
    raw = os.getenv(var, "").strip().lower()
    if raw in ("true","1","yes","on"): return True
    if raw in ("false","0","no","off"): return False
    return default

def get_order() -> List[str]:
    s = os.getenv("AUTOSWITCH_ORDER") or os.getenv("PROVIDER_ORDER") or "gemini,groq,ollama,openai"
    return [p.strip().lower() for p in s.split(",") if p.strip()]

def call_gemini(prompt: str) -> str:
    if not _has("GEMINI_API_KEY"):
        raise ProviderError("gemini: missing GEMINI_API_KEY")
    # --- minimal call sketch; actual client code is in your existing implementation ---
    from providers_impl import gemini_chat
    return gemini_chat(prompt)

def call_groq(prompt: str) -> str:
    if not _has("GROQ_API_KEY"):
        raise ProviderError("groq: missing GROQ_API_KEY")
    from providers_impl import groq_chat
    return groq_chat(prompt)

def call_openai(prompt: str) -> str:
    if not _enabled("OPENAI_ENABLED", default=True):
        raise ProviderError("openai: disabled via OPENAI_ENABLED=false")
    if not _has("OPENAI_API_KEY"):
        raise ProviderError("openai: missing OPENAI_API_KEY")
    from providers_impl import openai_chat
    return openai_chat(prompt)

def call_ollama(prompt: str) -> str:
    # Allow ollama even without explicit key, but require host reachability (handled inside impl).
    from providers_impl import ollama_chat
    return ollama_chat(prompt)

_dispatch = {
    "gemini": call_gemini,
    "groq": call_groq,
    "openai": call_openai,
    "ollama": call_ollama,
}

def run_chain(prompt: str) -> str:
    errors = []
    for name in get_order():
        fn: Callable[[str], str] = _dispatch.get(name)
        if not fn:
            errors.append(f"{name}: unknown provider")
            continue
        try:
            out = fn(prompt)
            if out and out.strip():
                return out
            errors.append(f"{name}: empty output")
        except Exception as e:
            errors.append(f"{name}: {e}")
            continue
    raise ProviderError("all providers failed → " + " | ".join(errors))

# --- Ollama provider (added by Fix-ChillChill) ---
import os, requests

class OllamaProvider:
    def __init__(self):
        self.host = os.environ.get("OLLAMA_HOST_DOCKER", "http://host.docker.internal:11434")
        self.model = os.environ.get("OLLAMA_MODEL", "llama3.2:3b")

    def generate(self, prompt: str, stream: bool=False):
        url = f"{self.host}/api/generate"
        payload = {"model": self.model, "prompt": prompt, "stream": False}
        r = requests.post(url, json=payload, timeout=30)
        r.raise_for_status()
        j = r.json()
        return (j.get("response") or j.get("message") or "")

try:
    PROVIDERS  # noqa
except NameError:
    PROVIDERS = {}

# Register if missing
if "ollama" not in PROVIDERS:
    PROVIDERS["ollama"] = OllamaProvider()
# --- end Ollama provider patch ---




False
False
False

# --- OPERATOR: canonical provider plan (appended) ---
# This block is authoritative for autoswitch/personas if referenced by runtime.
PROVIDER_PLAN = {
    'autoswitch': ['gemini','groq','mistral'],
    'personas':   { 'GP': 'gemini', 'Chef': 'groq', 'Accountant': 'mistral' }
}
# --- END OPERATOR BLOCK ---


# === OPERATOR PATCH START ===
import json, os, time, inspect
from typing import Optional

_MANIFEST_CACHE = None
_MANIFEST_MTIME = None

def _load_manifest(path: str = os.path.join(os.getcwd(), 'operator.manifest.json')) -> dict:
    global _MANIFEST_CACHE, _MANIFEST_MTIME
    try:
        st = os.stat(path)
        if _MANIFEST_CACHE is None or _MANIFEST_MTIME != st.st_mtime:
            with open(path, 'r', encoding='utf-8') as f:
                _MANIFEST_CACHE = json.load(f)
            _MANIFEST_MTIME = st.st_mtime
    except Exception:
        _MANIFEST_CACHE = _MANIFEST_CACHE or {
            "autoswitch": ["gemini","groq","mistral"],
            "personas":   { "GP":"gemini","Chef":"groq","Accountant":"groq" }
        }
    return _MANIFEST_CACHE

def _env(key: str) -> Optional[str]:
    v = os.getenv(key, "").strip()
    return v if v else None

def _chat_gemini(msg: str) -> Optional[str]:
    api = _env("GEMINI_API_KEY")
    if not api: return None
    try:
        # Minimal REST call (Generative Language API)
        import requests
        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={api}"
        payload = {"contents":[{"parts":[{"text": msg}]}]}
        r = requests.post(url, json=payload, timeout=20)
        if r.status_code != 200: return None
        data = r.json()
        # Extract first candidate text safely
        return (data.get("candidates") or [{}])[0].get("content",{}).get("parts",[{}])[0].get("text") or None
    except Exception as e:
        print(f"[PROVIDER][gemini] error: {e}")
        return None

def _chat_openai_compat(msg: str, base: str, model: str, header_name: str, key: Optional[str]) -> Optional[str]:
    if not key: return None
    try:
        import requests
        url = f"{base.rstrip('/')}/v1/chat/completions"
        headers = {"Content-Type":"application/json", "Authorization": f"Bearer {key}"}
        payload = { "model": model, "messages": [ {"role":"user","content": msg} ] }
        r = requests.post(url, headers=headers, json=payload, timeout=20)
        if r.status_code != 200: return None
        data = r.json()
        choices = data.get("choices") or []
        if not choices: return None
        return choices[0].get("message",{}).get("content") or None
    except Exception as e:
        print(f"[PROVIDER][{model}] error: {e}")
        return None

def _chat_groq(msg: str) -> Optional[str]:
    # Groq uses OpenAI-compatible API
    key = _env("GROQ_API_KEY")
    base = _env("GROQ_API_BASE") or "https://api.groq.com"
    model = "llama3-70b-8192"
    return _chat_openai_compat(msg, base, model, "Authorization", key)

def _chat_mistral(msg: str) -> Optional[str]:
    # Mistral also exposes OpenAI-compatible endpoint (fallback to official)
    key = _env("MISTRAL_API_KEY")
    base = _env("MISTRAL_API_BASE") or "https://api.mistral.ai"
    model = _env("MISTRAL_MODEL") or "mistral-large-latest"
    # Some deployments use openai-compatible proxy; above should work for vanilla
    return _chat_openai_compat(msg, base, model, "Authorization", key)

def chat_reply(msg: str) -> Optional[str]:
    man = _load_manifest()
    order = man.get("autoswitch") or ["gemini","groq","mistral"]
    reply = None
    for name in order:
        if name == "gemini":
            reply = _chat_gemini(msg)
        elif name == "groq":
            reply = _chat_groq(msg)
        elif name == "mistral":
            reply = _chat_mistral(msg)
        else:
            continue
        if reply:
            print(f"[PROVIDER] selected={name}")
            return reply
    return None
# === OPERATOR PATCH END ===
