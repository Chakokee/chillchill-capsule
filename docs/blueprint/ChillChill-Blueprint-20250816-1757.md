# ChillChill Blueprint

- Generated: 2025-08-16 17:57
- Git: tag=v0.2.1-blueprint, sha=fe83b39

## Goals
- Multi-LLM with auto-switch (OpenAI, Groq, Gemini, Ollama)
- RAG: store and retrieve documents (Qdrant)
- Domain profiles: general_prac, accountant, chef
- Private network access (LAN), optional TLS via Caddy
- Living blueprint that maps all changes

## Runtime Topology (docker compose)
_compose config unavailable_

## Providers
| provider | enabled | model |
|---|---:|---|
| openai | 1 | gpt-4o-mini |
| groq | 1 | llama-3.1-70b-versatile |
| gemini | 1 | gemini-1.5-flash-latest |
| ollama | 1 | llama3.1 |

- Order: openai,groq,gemini,ollama

### Provider health (from /health)
| provider | healthy | detail |
|---|---:|---|
| openai | True | ok |
| groq | True | ok |
| gemini | True | ok |
| ollama | True | ok |

## RAG
- Vector host: vector
- Vector port: 6333
- Collection: chill_docs
- Embeddings: OpenAI=text-embedding-3-small; Ollama=nomic-embed-text

## Profiles
- Active profiles: default, general_prac, accountant, chef
- Profile collections: chill_docs_profileName (e.g., chill_docs_general_prac)

## API Surface
- /health
- /chat (provider, use_rag, profile, inventory, diet, time_limit, appliances)
- /rag/ingest, /rag/ingest/profile, /rag/query

## UI → API Bridge
```js
/** @type {import('next').NextConfig} */
const nextConfig = {
  async rewrites() {
    return [
      { source: '/bridge/:path*', destination: 'http://api:8000/:path*' }
    ];
  },
};
module.exports = nextConfig;

```

## Env (secrets masked)
```
OPENAI_API_KEY=sk-s*****************************************************************************************************************************************************************AA
GROQ_API_KEY=gsk_**************************************************aA
GEMINI_API_KEY=AIza*********************************Vw
OPENAI_ENABLED=1
GROQ_ENABLED=1
GEMINI_ENABLED=1
OLLAMA_ENABLED=1
PROVIDER_ORDER=openai,groq,gemini,ollama
LLM_PROVIDER=openai
LLM_MODEL=gpt-4o-mini
GROQ_MODEL=llama-3.1-70b-versatile
GEMINI_MODEL=gemini-1.5-flash-latest
OLLAMA_MODEL=llama3.1
EMBED_MODEL_OPENAI=text-embedding-3-small
OLLAMA_HOST=http://ollama:11434
OLLAMA_EMBED_MODEL=nomic-embed-text
VECTOR_HOST=vector
VECTOR_PORT=6333
RAG_COLLECTION=chill_docs
CHAT_ECHO=false
```

## Change Summary (recent)
```
fe83b39 feat(ollama): fix env updater; ensure ollama up and models present; refresh blueprint
f2ba4b0 chore: add PR template with blueprint checklist
58f11ee policy: block direct pushes to main via pre-push hook
8dddfb0 chore: add CODEOWNERS
84a135f ci: add Blueprint Guard workflow
41e28b1 chore(ollama): point API to host.docker.internal; refresh blueprint
b576caa chore(blueprint): refresh after compose change
63b5980 chore(blueprint): add generator, guard, and initial living blueprint
```

