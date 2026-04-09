#!/usr/bin/env bash
#
# upload-to-testflight.sh
#
# One-shot TestFlight upload using an App Store Connect API key (.p8).
# This bypasses the recurring xcodebuild "Failed to Use Accounts" bug
# that happens when xcodebuild can't find an Xcode-cached account.
#
# Setup (once):
#   cp scripts/testflight-config.sh.template scripts/testflight-config.sh
#   $EDITOR scripts/testflight-config.sh   # fill in ASC_KEY_PATH/ID/ISSUER_ID
#
# Usage:
#   ./scripts/upload-to-testflight.sh           # archive + upload
#   ./scripts/upload-to-testflight.sh --bump    # auto-bump CFBundleVersion first
#

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${PROJECT_ROOT}/scripts/testflight-config.sh"
BUILD_DIR="${PROJECT_ROOT}/build"
ARCHIVE_PATH="${BUILD_DIR}/Lokal.xcarchive"
EXPORT_OPTIONS="${BUILD_DIR}/ExportOptions.plist"

if [ ! -f "${CONFIG}" ]; then
  echo "✗ Missing ${CONFIG}" >&2
  echo "  Run: cp scripts/testflight-config.sh.template scripts/testflight-config.sh" >&2
  echo "  Then fill in ASC_KEY_PATH / ASC_KEY_ID / ASC_ISSUER_ID." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${CONFIG}"

: "${ASC_KEY_PATH:?ASC_KEY_PATH not set in ${CONFIG}}"
: "${ASC_KEY_ID:?ASC_KEY_ID not set in ${CONFIG}}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID not set in ${CONFIG}}"

if [ ! -f "${ASC_KEY_PATH}" ]; then
  echo "✗ ASC API key not found at ${ASC_KEY_PATH}" >&2
  exit 1
fi

if [ ! -f "${EXPORT_OPTIONS}" ]; then
  echo "✗ Missing ${EXPORT_OPTIONS}" >&2
  echo "  This file describes how to export the archive (method, team, signing)." >&2
  exit 1
fi

# Optional --bump: increment CFBundleVersion + CURRENT_PROJECT_VERSION in
# project.yml before archiving. Apple requires a unique build number per upload.
if [ "${1:-}" = "--bump" ]; then
  CURRENT=$(grep 'CFBundleVersion:' "${PROJECT_ROOT}/project.yml" | head -n1 | sed -E 's/.*"([0-9]+)".*/\1/')
  if [ -z "${CURRENT}" ]; then
    echo "✗ Could not parse CFBundleVersion from project.yml" >&2
    exit 1
  fi
  NEXT=$((CURRENT + 1))
  echo "→ Bumping CFBundleVersion ${CURRENT} → ${NEXT}"
  sed -i '' -E "s/(CFBundleVersion: \")[0-9]+(\")/\1${NEXT}\2/" "${PROJECT_ROOT}/project.yml"
  sed -i '' -E "s/(CURRENT_PROJECT_VERSION: \")[0-9]+(\")/\1${NEXT}\2/" "${PROJECT_ROOT}/project.yml"
fi

cd "${PROJECT_ROOT}"

echo "→ Regenerating Xcode project (xcodegen)…"
xcodegen generate

echo "→ Cleaning previous archive…"
rm -rf "${ARCHIVE_PATH}"
rm -rf "${BUILD_DIR}/export"

echo "→ Archiving Release build (this takes a few minutes)…"
xcodebuild \
  -project Lokal.xcodeproj \
  -scheme Lokal \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "${ARCHIVE_PATH}" \
  archive

echo "→ Exporting + uploading to TestFlight (using ASC API key)…"
xcodebuild \
  -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportOptionsPlist "${EXPORT_OPTIONS}" \
  -exportPath "${BUILD_DIR}/export" \
  -authenticationKeyPath "${ASC_KEY_PATH}" \
  -authenticationKeyID "${ASC_KEY_ID}" \
  -authenticationKeyIssuerID "${ASC_ISSUER_ID}"

echo ""
echo "✓ Upload complete. TestFlight will email you when processing is done"
echo "  (typically 5–15 min). Then the build appears in App Store Connect."
