# C:\AiProject\chatbot\agent-api\Dockerfile
FROM python:3.11-slim

# Prevent Python from buffering stdout/stderr
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# System deps (add build tools only if you need to compile libs)
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    wget curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies first for better layer caching
COPY requirements.txt /app/requirements.txt
RUN python -m pip install --upgrade pip && pip install -r /app/requirements.txt

# Copy application code
COPY . /app

# Expose API port (must match docker-compose -> 8000)
EXPOSE 8000

# Start FastAPI with uvicorn
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
