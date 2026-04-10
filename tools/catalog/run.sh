#!/usr/bin/env bash
#
# Lokalo catalog refresh wrapper.
# Called daily by launchd (~/Library/LaunchAgents/com.slavkoklincov.lokalo-catalog.plist).
#
# Activates the venv, runs update_catalog.py, validates the result, and
# only commits + pushes when models.json actually changed. All output is
# captured to ~/Library/Logs/lokalo-catalog.log by the launchd plist.

set -euo pipefail

# Resolve repo root from this script's location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CATALOG_PATH="${REPO_ROOT}/Lokal/Resources/models.json"
VENV_DIR="${SCRIPT_DIR}/.venv"

cd "${REPO_ROOT}"

echo "==== $(date '+%Y-%m-%d %H:%M:%S') ===="
echo "repo:   ${REPO_ROOT}"
echo "script: ${SCRIPT_DIR}"

# Make sure we're up to date with origin before generating, otherwise the
# push at the end will reject (someone might have pushed a manual edit).
echo "→ pulling latest main"
git fetch origin main
git merge --ff-only origin/main || {
    echo "❌ cannot fast-forward main — manual intervention needed"
    exit 1
}

# Activate venv (create if missing).
if [ ! -d "${VENV_DIR}" ]; then
    echo "→ creating venv at ${VENV_DIR}"
    python3 -m venv "${VENV_DIR}"
    "${VENV_DIR}/bin/pip" install -q --upgrade pip
    "${VENV_DIR}/bin/pip" install -q -r "${SCRIPT_DIR}/requirements.txt"
fi
source "${VENV_DIR}/bin/activate"

# Generate the new catalog.
python "${SCRIPT_DIR}/update_catalog.py"

# Sanity-check before commit.
python "${SCRIPT_DIR}/validate_catalog.py"

# Only commit if models.json actually changed.
if git diff --quiet -- "${CATALOG_PATH}"; then
    echo "ℹ️  no changes to commit"
    exit 0
fi

echo "→ committing catalog refresh"
git add "${CATALOG_PATH}"
git commit -m "auto: catalog refresh $(date '+%Y-%m-%d')"

echo "→ pushing to origin/main"
git push origin main

echo "✅ catalog refresh complete"
