#!/usr/bin/env bash
#
# upload-to-testflight.sh
#
# End-to-end TestFlight upload: archive + export + upload in one call.
#
# Authentication: passes the App Store Connect API key (.p8) directly to
# xcodebuild's export step via -authenticationKey{Path,ID,IssuerID}. This
# is intentionally NOT relying on Xcode's cached Apple ID auth, because
# those credentials live in the macOS login keychain and disappear about
# every other run with the dreaded "Failed to Use Accounts /
# missing Xcode-Username" error — fixing them requires a manual sign-out
# / sign-in dance in Xcode → Settings → Accounts which doesn't work when
# we're driving the upload headless.
#
# History note: an earlier iteration of this script (commit cb8c1d0)
# moved to Xcode auth because the .p8 was tripping a "cloud signing
# permission error" complaining about missing "Cloud Managed Distribution
# Certificates" scope. That block has since been lifted on Apple's side,
# and the .p8 path now works end to end with the same automatic-signing
# ExportOptions.plist. Verified 2026-04-11 with Build 9 after Build 9's
# initial Xcode-auth attempt blew up with the credential cache bug.
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

echo "→ Exporting + uploading to TestFlight (using App Store Connect .p8 API key)…"
# -allowProvisioningUpdates lets xcodebuild refresh/regenerate the
# distribution provisioning profile on the fly if the local copy is
# stale (e.g. after a new Apple Distribution cert was issued). The
# -authenticationKey{Path,ID,IssuerID} trio bypasses Xcode's
# Apple-ID-cache-in-keychain entirely — see the header comment for the
# full story on why this is the safer path.
xcodebuild \
  -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportOptionsPlist "${EXPORT_OPTIONS}" \
  -exportPath "${BUILD_DIR}/export" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "${ASC_KEY_PATH}" \
  -authenticationKeyID "${ASC_KEY_ID}" \
  -authenticationKeyIssuerID "${ASC_ISSUER_ID}"

echo ""
echo "✓ Upload complete. TestFlight will email you when processing is done"
echo "  (typically 5–15 min). Then the build appears in App Store Connect."
