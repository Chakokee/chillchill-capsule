#!/usr/bin/env bash
set -euo pipefail

echo "==> Building containers (api + ui)..."
docker compose build

echo "==> Starting services..."
docker compose up -d chatbot-api chatbot-ui

# Discover mapped ports (fallback to defaults if not mapped)
API_PORT=$(docker compose port chatbot-api 8000 2>/dev/null | awk -F: '{print $2}')
UI_PORT=$(docker compose port chatbot-ui 3000 2>/dev/null | awk -F: '{print $2}')
API_PORT=${API_PORT:-8000}
UI_PORT=${UI_PORT:-3000}

API_URL="http://localhost:${API_PORT}"
UI_URL="http://localhost:${UI_PORT}"

echo "==> Waiting for API to be ready at ${API_URL} ..."
for i in {1..60}; do
  if curl -fsS "${API_URL}/docs" >/dev/null 2>&1 || curl -fsS "${API_URL}/openapi.json" >/dev/null 2>&1; then
    echo "==> API is up."
    break
  fi
  sleep 1
  if [ "$i" -eq 60 ]; then
    echo "ERROR: API did not become ready in time. Check logs with:"
    echo "  docker compose logs -f chatbot-api"
    exit 1
  fi
done

echo "==> Opening UI at ${UI_URL} ..."
# Try to open a browser, ignore failures
if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "${UI_URL}" || true
elif command -v open >/dev/null 2>&1; then
  open "${UI_URL}" || true
elif command -v start >/dev/null 2>&1; then
  start "" "${UI_URL}" || true
fi

echo "==> Tail logs (Ctrl+C to stop):"
docker compose logs -f --since=1m chatbot-api chatbot-ui
