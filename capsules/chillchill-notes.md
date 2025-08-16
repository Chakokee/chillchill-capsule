# ChillChill Capsule — Notes

## Architecture
- UI: Next.js (App Router), proxy `/api/* -> http://api:8000/*`
- API: FastAPI (`/health`, `/models`, `/warmup`, `/chat`)
- Data: Redis + Qdrant (RAG ready)

## Provider Defaults (expected)
LLM_PROVIDER=<openai|anthropic|...>  |  LLM_MODEL=<model>  |  CHAT_ECHO=false
Provider keys in .env (masked in manifests)

## Decisions
- Use Next.js proxy to avoid CORS.
- Remove `version:` from docker-compose.yml.
- Enforce `"use client"` at file top (guard).

## Open Items
- Expose RAG ingest route in API when ready.
- Keep provider env in .env and rebuild API if changed.
