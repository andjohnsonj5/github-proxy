#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:7070}"

echo "[1/2] GET info/refs ..."
curl -fsSL -o /dev/null -w "status=%{http_code} bytes=%{size_download}\n" \
  "${BASE_URL}/openai/codex.git/info/refs?service=git-upload-pack"

echo "[2/2] POST upload-pack (dummy) ..."
curl -sS -o /dev/null -w "status=%{http_code}\n" \
  -H "Content-Type: application/x-git-upload-pack-request" \
  --data-binary $'0000' \
  "${BASE_URL}/openai/codex.git/git-upload-pack" || true

echo "Done."
