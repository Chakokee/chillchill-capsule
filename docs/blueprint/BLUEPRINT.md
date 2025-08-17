# ChillChill Blueprint

- Generated: 2025-08-17 17:13
- Git: tag=v0.3.0-checkpoint-20250816, sha=5d08e5f

## Goals
- Multi-LLM with auto-switch (OpenAI, Groq, Gemini, Ollama)
- RAG: store and retrieve documents (Qdrant)
- Domain profiles: general_prac, accountant, chef
- Private network access (LAN), optional TLS via Caddy
- Living blueprint that maps all changes

## Runtime Topology (docker compose)

| service | image | build | ports |
|---|---|---|---|
| api |  | C:\AiProject\chatbot\agent-api (Dockerfile) |  |
| redis | redis:alpine |  |  |
| ui |  | C:\AiProject\chatbot\chatbot-ui (Dockerfile) |  |
| vector | qdrant/qdrant:latest |  |  |

## Providers
| provider | enabled | model |
|---|---:|---|
| openai | 1 | llama3.2:3b |
| groq | 1 | llama3-70b-8192 |
| gemini | 1 | gemini-1.5-flash-latest |
| ollama | 1 | llama3.2:3b |

- Order: ollama,groq,gemini,openai

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
  eslint: { ignoreDuringBuilds: true },
  typescript: { ignoreBuildErrors: true },
  images: { unoptimized: true }
};
module.exports = nextConfig;

```

## Env (secrets masked)
```
EMBED_MODEL_OPENAI=text-embedding-3-small
GROQ_API_KEY=
GOOGLE_API_KEY=
OLLAMA_HOST=http://chill_ollama:11434
GEMINI_API_KEY=AIza*********************************Vw
RAG_COLLECTION=chill_docs
AUTOSWITCH_ENABLED=true
OLLAMA_EMBED_MODEL=nomic-embed-text
GEMINI_MODEL=gemini-1.5-flash-latest
VECTOR_HOST=vector
GROQ_ENABLED=1
PROVIDER_DEBUG=1
OPENAI_ENABLED=1
CHAT_ECHO=false
OLLAMA_MODEL=llama3.2:3b
PROVIDER_ORDER=ollama,groq,gemini,openai
GEMINI_ENABLED=1
LLM_MODEL=llama3.2:3b
OLLAMA_ENABLED=1
LOG_LEVEL=DEBUG
VECTOR_PORT=6333
LLM_PROVIDER=ollama
OPENAI_API_KEY=sk-s*****************************************************************************************************************************************************************AA
GROQ_MODEL=llama3-70b-8192
AUTOSWITCH_ORDER=gemini,groq,ollama,openai
```

## Change Summary (recent)
```
5d08e5f ChillChill: enforce providers/autoswitch; NO_PROXY & CHAT_ECHO; blueprint canonical; normalize endings
0cdd4db Blueprint: enforce canonical BLUEPRINT.md; track .gitattributes
94d3cdd Blueprint: regenerate after provider/persona updates
5143ecb ChillChill: proxy-agnostic validator, stable compose up, UI lint bypass & AppClient placeholder, blueprint regenerated
b3f3509 chore(checkpoint): overlay + autoswitch plan captured in blueprint
18658e8 chore(api): accept 'auto'/*/any as autoswitch; update blueprint
fe83b39 feat(ollama): fix env updater; ensure ollama up and models present; refresh blueprint
f2ba4b0 chore: add PR template with blueprint checklist
58f11ee policy: block direct pushes to main via pre-push hook
8dddfb0 chore: add CODEOWNERS
84a135f ci: add Blueprint Guard workflow
41e28b1 chore(ollama): point API to host.docker.internal; refresh blueprint
b576caa chore(blueprint): refresh after compose change
63b5980 chore(blueprint): add generator, guard, and initial living blueprint
```

