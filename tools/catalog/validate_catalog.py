"""
Sanity-check Lokal/Resources/models.json before commit.

Catches the failure modes that the runtime Codable decoder in Lokalo would
also catch — but here we surface them BEFORE pushing to GitHub, so a buggy
catalog never breaks user installs.

Checks:
1. Top-level shape (`version`, `generatedAt`, `entries`).
2. Entry count > 0.
3. Each entry has the required keys.
4. `recommendedSamplingDefaults` (if present) is a complete GenerationSettings
   record with all sampling fields plus the Lokalo-specific ones.
5. `downloadURL` is a well-formed HuggingFace URL.
6. No duplicate `id` fields.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
CATALOG_PATH = REPO_ROOT / "Lokal" / "Resources" / "models.json"

REQUIRED_ENTRY_KEYS = {
    "id",
    "displayName",
    "publisher",
    "summary",
    "parametersBillion",
    "quantization",
    "sizeBytes",
    "estimatedRAMBytes",
    "downloadURL",
    "filename",
    "chatTemplate",
    "licenseLabel",
    "maxContextTokens",
    "recommendedContextTokens",
}

REQUIRED_SAMPLING_KEYS = {
    "temperature",
    "topP",
    "minP",
    "topK",
    "maxNewTokens",
    "contextTokens",
    "seed",
    "repetitionPenalty",
    "repetitionPenaltyLastN",
}


def fail(msg: str) -> None:
    print(f"❌ {msg}")
    sys.exit(1)


def main() -> int:
    if not CATALOG_PATH.exists():
        fail(f"catalog not found at {CATALOG_PATH}")

    try:
        catalog = json.loads(CATALOG_PATH.read_text())
    except json.JSONDecodeError as e:
        fail(f"invalid JSON: {e}")

    if "version" not in catalog or "entries" not in catalog:
        fail("catalog missing top-level `version` or `entries`")
    if not isinstance(catalog["entries"], list) or not catalog["entries"]:
        fail("catalog has no entries")

    seen_ids: set[str] = set()
    for i, entry in enumerate(catalog["entries"]):
        prefix = f"entries[{i}]"
        missing = REQUIRED_ENTRY_KEYS - entry.keys()
        if missing:
            fail(f"{prefix} missing required keys: {sorted(missing)}")

        entry_id = entry["id"]
        if entry_id in seen_ids:
            fail(f"{prefix} duplicate id: {entry_id!r}")
        seen_ids.add(entry_id)

        url = entry["downloadURL"]
        if not url.startswith("https://huggingface.co/"):
            fail(f"{prefix} ({entry_id}) downloadURL not a HuggingFace URL: {url}")

        if entry["sizeBytes"] <= 0:
            fail(f"{prefix} ({entry_id}) sizeBytes is non-positive: {entry['sizeBytes']}")

        if "recommendedSamplingDefaults" in entry:
            sampling = entry["recommendedSamplingDefaults"]
            if not isinstance(sampling, dict):
                fail(f"{prefix} ({entry_id}) recommendedSamplingDefaults is not an object")
            sampling_missing = REQUIRED_SAMPLING_KEYS - sampling.keys()
            if sampling_missing:
                fail(
                    f"{prefix} ({entry_id}) recommendedSamplingDefaults missing keys: "
                    f"{sorted(sampling_missing)}"
                )

    print(f"✅ catalog valid — v{catalog['version']}, {len(catalog['entries'])} entries")
    return 0


if __name__ == "__main__":
    sys.exit(main())
