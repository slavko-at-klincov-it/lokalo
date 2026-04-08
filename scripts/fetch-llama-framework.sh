#!/usr/bin/env bash
#
# fetch-llama-framework.sh
#
# Downloads and extracts the latest llama.xcframework from github.com/ggml-org/llama.cpp
# into Frameworks/llama.xcframework. Idempotent — safe to re-run.
#

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAMEWORKS_DIR="${PROJECT_ROOT}/Frameworks"
TARGET="${FRAMEWORKS_DIR}/llama.xcframework"

if [ -d "${TARGET}" ]; then
  echo "✓ ${TARGET} already exists, skipping (delete it to force re-download)."
  exit 0
fi

mkdir -p "${FRAMEWORKS_DIR}"

# Resolve the latest release tag from the GitHub API.
TAG=$(curl -fsSL https://api.github.com/repos/ggml-org/llama.cpp/releases/latest \
      | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'])")

URL="https://github.com/ggml-org/llama.cpp/releases/download/${TAG}/llama-${TAG}-xcframework.zip"
ZIP="/tmp/llama-${TAG}.zip"

echo "→ Downloading llama.xcframework ${TAG}…"
curl -fL --progress-bar -o "${ZIP}" "${URL}"

echo "→ Unpacking…"
unzip -o -q "${ZIP}" -d "${FRAMEWORKS_DIR}"

# The release zip extracts into Frameworks/build-apple/llama.xcframework
if [ -d "${FRAMEWORKS_DIR}/build-apple/llama.xcframework" ]; then
  mv "${FRAMEWORKS_DIR}/build-apple/llama.xcframework" "${TARGET}"
  rm -rf "${FRAMEWORKS_DIR}/build-apple"
fi

rm -f "${ZIP}"

if [ -d "${TARGET}" ]; then
  echo "✓ Done. ${TARGET} (${TAG})"
else
  echo "✗ Extraction failed — check ${ZIP}" >&2
  exit 1
fi
