#!/bin/bash
set -euo pipefail
echo "=== CortexBuild API Deploy ==="
PROJECT_DIR="/var/www/cortexbuild-ultimate"
CONTAINER_NAME="cortexbuild-api"
IMAGE_NAME="cortexbuild-ultimate-api:latest"
cd "$PROJECT_DIR"

# Ensure API can reach DB/Redis/Ollama on their network
# Docker Compose creates 'cortexbuild-ultimate_cortexbuild' — use that.
COMPOSE_NET="cortexbuild-ultimate_cortexbuild"
FALLBACK_NET="cortexbuild"
if docker network inspect "$COMPOSE_NET" >/dev/null 2>&1; then
  DOCKER_NET="$COMPOSE_NET"
else
  if ! docker network inspect "$FALLBACK_NET" >/dev/null 2>&1; then
    echo "Creating $FALLBACK_NET network..."
    docker network create "$FALLBACK_NET"
  fi
  DOCKER_NET="$FALLBACK_NET"
fi

git pull origin main

docker build -t "$IMAGE_NAME" -f Dockerfile.api .

# Source environment variables after git pull (env file is gitignored, not overwritten)
if [ ! -f "$PROJECT_DIR/.env" ]; then
  echo "FATAL: $PROJECT_DIR/.env not found"
  exit 1
fi
set +u
set -a
source "$PROJECT_DIR/.env"
set +a
set -u

# Validate required secrets are present
if [ -z "${JWT_SECRET:-}" ]; then
  echo "FATAL: JWT_SECRET not set in $PROJECT_DIR/.env"
  exit 1
fi
if [ -z "${SESSION_SECRET:-}" ]; then
  echo "FATAL: SESSION_SECRET not set in $PROJECT_DIR/.env"
  exit 1
fi
if [ -z "${POSTGRES_PASSWORD:-}" ] && [ -z "${DB_PASSWORD:-}" ]; then
  echo "FATAL: Neither POSTGRES_PASSWORD nor DB_PASSWORD set in $PROJECT_DIR/.env"
  exit 1
fi

# Get the DB password
ACTUAL_DB_PASSWORD="${POSTGRES_PASSWORD:-${DB_PASSWORD:-}}"
echo "Deploying with secure credentials from .env"

docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm "$CONTAINER_NAME" 2>/dev/null || true
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart always \
  --network "$DOCKER_NET" \
  -p 127.0.0.1:3001:3001 \
  -e DB_HOST=cortexbuild-db \
  -e DB_PORT=5432 \
  -e DB_NAME=cortexbuild \
  -e DB_USER=cortexbuild \
  -e DB_PASSWORD="$ACTUAL_DB_PASSWORD" \
  -e JWT_SECRET="$JWT_SECRET" \
  -e SESSION_SECRET="$SESSION_SECRET" \
  -e REDIS_HOST=cortexbuild-redis \
  -e PORT=3001 \
  -e NODE_ENV=production \
  -e OLLAMA_HOST=http://cortexbuild-ollama:11434 \
  -e OLLAMA_MODEL=qwen3.5:latest \
  -e CORS_ORIGIN=https://www.cortexbuildpro.com,https://cortexbuildpro.com \
  -e FRONTEND_URL=https://www.cortexbuildpro.com \
  "$IMAGE_NAME"
echo "Waiting for API health..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:3001/api/health >/dev/null 2>&1; then
    echo "API healthy on localhost:3001"
    break
  fi
  sleep 2
done

# Restart nginx to refresh DNS resolution for new container
echo "Restarting nginx..."
systemctl restart nginx || service nginx restart || nginx -s reload || true
sleep 5

# Final check
curl -s http://localhost:3001/api/health >/dev/null 2>&1 && echo "API OK after restart" || echo "API may need manual check"

echo "=== API Deploy Complete ==="
