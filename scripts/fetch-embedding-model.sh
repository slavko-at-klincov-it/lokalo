#!/usr/bin/env bash
#
# fetch-embedding-model.sh
#
# Downloads the EmbeddingGemma-300M Q4_0 GGUF into Lokal/Resources/ so
# Xcode bundles it with the app. Idempotent — safe to re-run.
#

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES_DIR="${PROJECT_ROOT}/Lokal/Resources"
TARGET="${RESOURCES_DIR}/embeddinggemma-300M-qat-Q4_0.gguf"
URL="https://huggingface.co/ggml-org/embeddinggemma-300M-qat-q4_0-GGUF/resolve/main/embeddinggemma-300M-qat-Q4_0.gguf"

if [ -f "${TARGET}" ]; then
  SIZE=$(stat -f%z "${TARGET}" 2>/dev/null || stat --printf="%s" "${TARGET}" 2>/dev/null)
  if [ "${SIZE}" -gt 100000000 ]; then
    echo "✓ ${TARGET} already exists (${SIZE} bytes), skipping."
    exit 0
  fi
  echo "⚠ ${TARGET} exists but is suspiciously small (${SIZE} bytes), re-downloading."
fi

mkdir -p "${RESOURCES_DIR}"

echo "→ Downloading EmbeddingGemma-300M Q4_0 (~236 MB)…"
curl -fL --progress-bar -o "${TARGET}" "${URL}"

if [ -f "${TARGET}" ]; then
  SIZE=$(stat -f%z "${TARGET}" 2>/dev/null || stat --printf="%s" "${TARGET}" 2>/dev/null)
  echo "✓ Done. ${TARGET} (${SIZE} bytes)"
else
  echo "✗ Download failed." >&2
  exit 1
fi
