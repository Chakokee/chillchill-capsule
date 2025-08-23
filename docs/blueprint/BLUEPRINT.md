# ChillChill Capsule — Living Blueprint
_Last updated: 

## Architecture
- UI: Next.js (Docker, port 3000)
- API: FastAPI /chat, /health
- Vector: Qdrant · Cache: Redis

## Providers & Personas
- LLM_PROVIDER: ****
- LLM_MODEL: ****
- Autoswitch order: ****
- Personas: GP→Gemini; Chef→OpenAI; Accountant→Groq (llama3-70b-8192)

## Runtime Config
- CHAT_ECHO: ****
- docker-compose: C:\AiProject\docker-compose.yml
- docker-compose.override: C:\AiProject\docker-compose.override.yml

## Effective docker compose (excerpt)
~~~yaml
name: aiproject services:   api:     build:       context: C:\AiProject\chatbot\agent-api       dockerfile: Dockerfile     container_name: chill_api     depends_on:       redis:         condition: service_healthy         required: true       vector:         condition: service_started         required: true     environment:       API_PORT: "8000"       AUTOSWITCH_ENABLED: "true"       GEMINI_API_KEY: AIzaSyDml3AXe4VA6ZQK3kusCyLY2bFh1mxq6Vw       GROQ_API_KEY: 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       GROQ_MODEL: llama3-70b-8192       LLM_MODEL: auto       LLM_PROVIDER: auto       MISTRAL_API_KEY: 7wg9CcJgsa3lIpojUoGgjxea6NsiKywM       OLLAMA_HOST: http://host.docker.internal:11434       OLLAMA_MODEL: llama3.2:3b       PROVIDER_ORDER: gemini,groq,ollama,openai       PYTHONUNBUFFERED: "1"       REDIS_HOST: redis       REDIS_PORT: "6379"       VECTOR_HOST: vector       VECTOR_PORT: "6333"     extra_hosts:       - host.docker.internal=host-gateway     healthcheck:       test:         - CMD         - wget         - -qO-         - http://localhost:8000/health       timeout: 3s       interval: 10s       retries: 6       start_period: 15s     networks:       default: null     ports:       - mode: ingress         target: 8000         published: "8000"         protocol: tcp     restart: unless-stopped   redis:     container_name: chill_redis     healthcheck:       test:         - CMD         - redis-cli         - ping       timeout: 2s       interval: 5s       retries: 30       start_period: 5s     image: redis:alpine     networks:       default: null     ports:       - mode: ingress         target: 6379         published: "6379"         protocol: tcp     restart: unless-stopped   ui:     build:       context: C:\AiProject\chatbot\chatbot-ui       dockerfile: Dockerfile     container_name: chill_ui     depends_on:       api:         condition: service_healthy         required: true     environment:       GEMINI_API_KEY: AIzaSyDml3AXe4VA6ZQK3kusCyLY2bFh1mxq6Vw       GROQ_API_KEY: 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       MISTRAL_API_KEY: 7wg9CcJgsa3lIpojUoGgjxea6NsiKywM       NEXT_PUBLIC_API_BASE_URL: http://localhost:8000       NODE_ENV: production     healthcheck:       test:         - CMD         - wget         - -qO-         - http://localhost:3000/       timeout: 3s       interval: 7s       retries: 30       start_period: 15s     networks:       default: null     ports:       - mode: ingress         target: 3000         published: "3000"         protocol: tcp     restart: unless-stopped   vector:     container_name: chill_vector     image: qdrant/qdrant:latest     networks:       default: null     ports:       - mode: ingress         target: 6333         published: "6333"         protocol: tcp     restart: unless-stopped     volumes:       - type: volume         source: vector_data         target: /qdrant/storage         volume: {} networks:   default:     name: aiproject_default volumes:   vector_data:     name: aiproject_vector_data 
~~~
