FROM node:20-alpine

# Tools for healthcheck
RUN apk add --no-cache curl

WORKDIR /app

# Install deps first (better cache)
COPY package*.json ./
RUN npm ci

# Copy source and build
COPY . .
RUN npm run build

# App networking
ENV PORT=3000 HOST=0.0.0.0
EXPOSE 3000

# Healthcheck (curl, generous warm-up)
HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=12 \
  CMD curl -fsS http://127.0.0.1:3000/ > /dev/null || exit 1

# Start Next.js (no duplicate -p)
CMD ["node","node_modules/next/dist/bin/next","start","-H","0.0.0.0","-p","3000"]
