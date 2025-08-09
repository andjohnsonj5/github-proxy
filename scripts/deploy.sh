#!/usr/bin/env bash
set -euo pipefail

# One-click deploy: build and run the OpenResty GitHub proxy container.

# Configurable via env vars
NAME=${NAME:-gh-proxy}
PORT=${PORT:-8001}
IMAGE=${IMAGE:-openresty-github-proxy:local}
BUILD=${BUILD:-yes}

echo "[deploy] container name: $NAME"
echo "[deploy] host port: $PORT"
echo "[deploy] image: $IMAGE"
echo "[deploy] build: $BUILD"

if [[ "${BUILD}" == "yes" ]]; then
  echo "[deploy] Building image ..."
  docker build -t "$IMAGE" -f openresty/Dockerfile .
else
  echo "[deploy] Skipping build (BUILD=$BUILD)"
fi

if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "[deploy] Stopping existing container $NAME ..."
  docker rm -f "$NAME" >/dev/null 2>&1 || true
fi

echo "[deploy] Starting container ..."
docker run -d --name "$NAME" -p "$PORT:8001" "$IMAGE" >/dev/null

echo "[deploy] Waiting for service to accept connections ..."
sleep 1

BASE_URL="http://127.0.0.1:${PORT}"
echo "[deploy] Smoke test: GET info/refs"
set +e
curl -fsSL -o /dev/null -w "status=%{http_code} bytes=%{size_download}\n" \
  "${BASE_URL}/openai/codex.git/info/refs?service=git-upload-pack"
RC=$?
set -e

if [[ $RC -ne 0 ]]; then
  echo "[deploy] Smoke test failed (curl exit=$RC). Check logs: docker logs -f $NAME" >&2
  exit $RC
fi

echo "[deploy] Done. Logs: docker logs -f $NAME"

