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
