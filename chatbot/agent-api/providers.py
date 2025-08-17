import os
import logging
import requests

OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://host.docker.internal:11434")

async def chat_openai(model, msg, temperature=0.2):
    """
    OpenAI Chat Completions over REST. Needs OPENAI_API_KEY.
    """
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        logging.warning("openai: missing OPENAI_API_KEY")
        return None
    try:
        url = "https://api.openai.com/v1/chat/completions"
        headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
        payload = {
            "model": model or "gpt-3.5-turbo",
            "messages": [{"role": "user", "content": msg}],
            "temperature": temperature,
        }
        r = requests.post(url, headers=headers, json=payload, timeout=30)
        if r.status_code != 200:
            logging.warning("openai HTTP %s: %s", r.status_code, r.text[:500])
            return None
        j = r.json()
        choices = j.get("choices") or []
        return choices[0].get("message", {}).get("content") if choices else None
    except Exception:
        logging.exception("openai call failed")
        return None


async def chat_groq(model, msg, temperature=0.2):
    """
    Groq (OpenAI-compatible endpoint). Needs GROQ_API_KEY.
    """
    key = os.getenv("GROQ_API_KEY")
    if not key:
        logging.info("groq: no key; skipping")
        return None
    try:
        url = "https://api.groq.com/openai/v1/chat/completions"
        headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
        payload = {
            "model": model or "llama3-70b-8192",
            "messages": [{"role": "user", "content": msg}],
            "temperature": temperature,
        }
        r = requests.post(url, headers=headers, json=payload, timeout=30)
        if r.status_code != 200:
            logging.warning("groq HTTP %s: %s", r.status_code, r.text[:500])
            return None
        j = r.json()
        choices = j.get("choices") or []
        return choices[0].get("message", {}).get("content") if choices else None
    except Exception:
        logging.exception("groq call failed")
        return None


async def chat_gemini(model, msg, temperature=0.2):
    """
    Google Gemini (generateContent). Needs GOOGLE_API_KEY.
    """
    key = os.getenv("GOOGLE_API_KEY")
    if not key:
        logging.info("gemini: no key; skipping")
        return None
    try:
        mdl = model or "gemini-1.5-flash-latest"
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{mdl}:generateContent?key={key}"
        payload = {"contents": [{"parts": [{"text": msg}]}]}
        r = requests.post(url, json=payload, timeout=30)
        if r.status_code != 200:
            logging.warning("gemini HTTP %s: %s", r.status_code, r.text[:500])
            return None
        j = r.json()
        cands = j.get("candidates") or []
        if not cands:
            return None
        parts = (cands[0].get("content") or {}).get("parts") or []
        return parts[0].get("text") if parts else None
    except Exception:
        logging.exception("gemini call failed")
        return None


async def chat_ollama(model, msg, temperature=0.2):
    """
    Ollama chat (local). Will return None if host isn't reachable.
    """
    try:
        mdl = model or "llama3.2:3b"
        url = f"{OLLAMA_HOST}/api/chat"
        payload = {
            "model": mdl,
            "messages": [{"role": "user", "content": msg}],
            "options": {"temperature": temperature},
            "stream": False,
        }
        r = requests.post(url, json=payload, timeout=20)
        if r.status_code != 200:
            logging.info("ollama HTTP %s: %s", r.status_code, r.text[:300])
            return None
        j = r.json() or {}
        return ((j.get("message") or {}).get("content")) or None
    except Exception as e:
        logging.info("ollama call failed: %r", e)
        return None


async def chat_with_fallback(provider, model, msg, temperature=0.2) -> str | None:
    prov = (provider or "").lower().strip()
    # Provider search order
    order_map = {
        "openai": ["openai","groq","gemini","ollama"],
        "groq":   ["groq","openai","gemini","ollama"],
        "gemini": ["gemini","openai","groq","ollama"],
        "ollama": ["ollama","groq","openai","gemini"],
        "":       ["openai","groq","gemini","ollama"],
        None:     ["openai","groq","gemini","ollama"],
    }
    # Provider-appropriate default model names
    def_model = {
        "openai": "gpt-3.5-turbo",
        "groq":   "llama3-70b-8192",
        "gemini": "gemini-1.5-flash-latest",
        "ollama": "llama3.2:3b",
    }

    order = order_map.get(prov, order_map[""])
    impl = {
        "openai": chat_openai,
        "groq":   chat_groq,
        "gemini": chat_gemini,
        "ollama": chat_ollama,
    }
    last_err = None
    for name in order:
        fn = impl.get(name)
        if not fn:
            continue
        # If caller passed a model that doesn't belong to this provider, swap to provider default
        chosen_model = model
        if name == "openai" and (chosen_model or "").startswith("llama"): chosen_model = def_model["openai"]
        if name == "groq"   and not (chosen_model or "").startswith("llama"): chosen_model = def_model["groq"]
        if name == "gemini" and not (chosen_model or "").startswith("gemini"): chosen_model = def_model["gemini"]
        if name == "ollama" and ":" not in (chosen_model or ""): chosen_model = def_model["ollama"]

        try:
            out = await fn(chosen_model, msg, temperature)
            if out and isinstance(out, str) and out.strip():
                logging.info("provider %s succeeded with model %s", name, chosen_model)
                return out.strip()
            else:
                logging.info("provider %s returned empty", name)
        except Exception as e:
            logging.warning("provider %s raised: %r", name, e)
            last_err = e
    if last_err:
        logging.warning("all providers failed; last error: %r", last_err)
    return None