import os, httpx, asyncio
from typing import Optional

TIMEOUT = 60
OPENAI_KEY  = os.getenv("OPENAI_API_KEY")
GROQ_KEY    = os.getenv("GROQ_API_KEY")
GEMINI_KEY  = os.getenv("GEMINI_API_KEY")
OLLAMA_HOST = os.getenv("OLLAMA_HOST","http://ollama:11434")

class ProviderError(Exception): pass

async def _post_json(url, json, headers=None):
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        r = await client.post(url, json=json, headers=headers)
        if r.status_code >= 400:
            raise ProviderError(f"{r.status_code} {r.text[:300]}")
        return r.json()

async def chat_openai(model, msg, temperature=0.2) -> Optional[str]:
    if not OPENAI_KEY: return None
    data = {"model": model, "messages":[{"role":"user","content":msg}], "temperature":temperature}
    j = await _post_json("https://api.openai.com/v1/chat/completions", data, {"Authorization": f"Bearer {OPENAI_KEY}"})
    return j["choices"][0]["message"]["content"]

async def chat_groq(model, msg, temperature=0.2) -> Optional[str]:
    if not GROQ_KEY: return None
    data = {"model": model, "messages":[{"role":"user","content":msg}], "temperature":temperature}
    j = await _post_json("https://api.groq.com/openai/v1/chat/completions", data, {"Authorization": f"Bearer {GROQ_KEY}"})
    return j["choices"][0]["message"]["content"]

async def chat_gemini(model, msg, temperature=0.2) -> Optional[str]:
    if not GEMINI_KEY: return None
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={GEMINI_KEY}"
    data = {"contents":[{"parts":[{"text": msg}]}], "generationConfig":{"temperature":temperature}}
    j = await _post_json(url, data)
    return j["candidates"][0]["content"]["parts"][0]["text"]

async def chat_ollama(model, msg, temperature=0.2) -> Optional[str]:
    try:
        j = await _post_json(
            f"{OLLAMA_HOST}/api/chat",
            {
                "model": model,
                "messages":[{"role":"user","content": msg}],
                "options":{"temperature":temperature},
                "stream": False
            }
        )
        return (j.get("message") or {}).get("content")
    except Exception:
        return None

async def chat_with_fallback(provider, model, msg, temperature=0.2) -> str:
    if provider == "openai":
        chain = [chat_openai, chat_groq, chat_gemini, chat_ollama]
    elif provider == "groq":
        chain = [chat_groq, chat_openai, chat_gemini, chat_ollama]
    elif provider == "gemini":
        chain = [chat_gemini, chat_openai, chat_groq, chat_ollama]
    else:
        chain = [chat_ollama, chat_groq, chat_openai, chat_gemini]

    last_err = None
    for fn in chain:
        try:
            out = await fn(model, msg, temperature)
            if out: return out
        except Exception as e:
            last_err = e
            await asyncio.sleep(0.8)
    raise ProviderError(str(last_err) if last_err else "No provider available")
