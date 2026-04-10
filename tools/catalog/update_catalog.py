"""
Lokalo catalog generator.

Reads `tools/catalog/watchlist.json` and `tools/catalog/overrides.json`,
fetches per-model metadata + sampling defaults from HuggingFace, and
writes a fresh `Lokal/Resources/models.json`.

Behaviour:
- Skips entries where the GGUF size HEAD request fails (logs warning).
- Bumps `version` only if the catalog content actually changed
  (ignoring `version` and `generatedAt` for the diff check) — this keeps
  the RemoteCatalogService's version-comparison logic happy.
- On any uncaught exception the existing models.json is left untouched.
- Designed to be safe to run on a cron — never throws on transient HF
  outages, never produces an empty/garbled catalog.
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path
from datetime import date

# Allow `python update_catalog.py` from any working directory.
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from fetch_metadata import fetch_gguf_size, resolve_sampling_defaults  # noqa: E402

REPO_ROOT = SCRIPT_DIR.parent.parent
CATALOG_PATH = REPO_ROOT / "Lokal" / "Resources" / "models.json"
WATCHLIST_PATH = SCRIPT_DIR / "watchlist.json"
OVERRIDES_PATH = SCRIPT_DIR / "overrides.json"

# Heuristic — KV cache + activation overhead on top of the on-disk file.
# Conservative for Q4_K_M; matches the values in the existing catalog.
RAM_OVERHEAD_FACTOR = 1.3

MAX_EFFECTIVE_BILLION = 7.0


def load_json(path: Path) -> dict:
    return json.loads(path.read_text())


def build_entry(model: dict, override: dict | None) -> dict | None:
    model_id = model["id"]
    print(f"→ {model_id}")

    download_url = (
        f"https://huggingface.co/{model['ggufRepo']}/resolve/main/{model['ggufFile']}"
    )

    size_bytes = fetch_gguf_size(model["ggufRepo"], model["ggufFile"])
    if size_bytes is None:
        print(f"   ⚠️  failed to fetch GGUF size — skipping entry")
        return None
    print(f"   ✓ size: {size_bytes:_} bytes")

    sampling = resolve_sampling_defaults(model, override)
    print(
        f"   ✓ sampling: temp={sampling.get('temperature')} "
        f"top_p={sampling.get('topP')} top_k={sampling.get('topK')} "
        f"rep_penalty={sampling.get('repetitionPenalty')}"
    )

    estimated_ram = int(size_bytes * RAM_OVERHEAD_FACTOR)

    entry = {
        "id": model_id,
        "displayName": model["displayName"],
        "ollamaTag": model.get("ollamaTag"),
        "publisher": model["publisher"],
        "summary": model["summary"],
        "parametersBillion": model["parametersBillion"],
        "quantization": model["quantization"],
        "sizeBytes": size_bytes,
        "estimatedRAMBytes": estimated_ram,
        "downloadURL": download_url,
        "filename": model["ggufFile"],
        "chatTemplate": model["chatTemplate"],
        "licenseLabel": model["licenseLabel"],
        "maxContextTokens": model["maxContextTokens"],
        "recommendedContextTokens": model["recommendedContextTokens"],
        "recommendedSamplingDefaults": sampling,
    }
    # SHA-256 only carried through if the watchlist entry has it. We don't
    # auto-compute hashes here because that would require a full file
    # download per model on every cron run.
    if "sha256" in model:
        entry["sha256"] = model["sha256"]
    return entry


def serialise_for_diff(catalog: dict) -> str:
    """JSON serialisation that ignores fields that change every run."""
    copy = {k: v for k, v in catalog.items() if k not in ("version", "generatedAt")}
    return json.dumps(copy, sort_keys=True)


def main() -> int:
    print(f"Lokalo catalog refresh — {time.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"watchlist: {WATCHLIST_PATH.relative_to(REPO_ROOT)}")
    print(f"target:    {CATALOG_PATH.relative_to(REPO_ROOT)}")
    print()

    watchlist = load_json(WATCHLIST_PATH)
    overrides = load_json(OVERRIDES_PATH).get("overrides", {})

    entries: list[dict] = []
    for model in watchlist["models"]:
        entry = build_entry(model, overrides.get(model["id"]))
        if entry is not None:
            entries.append(entry)

    if not entries:
        print("\n❌ no entries built — refusing to write empty catalog")
        return 1

    if CATALOG_PATH.exists():
        existing = load_json(CATALOG_PATH)
        old_version = existing.get("version", 0)
    else:
        existing = None
        old_version = 0

    new_catalog = {
        "version": old_version + 1,
        "generatedAt": str(date.today()),
        "maxEffectiveBillion": MAX_EFFECTIVE_BILLION,
        "suggested": [m["id"] for m in watchlist["models"] if m.get("featured", False)],
        "entries": entries,
    }

    # Diff check: if nothing meaningful changed, don't bump the version.
    # The RemoteCatalogService comparison `remote.version <= current.version`
    # would skip the download anyway, but a clean diff in git is nice.
    if existing and serialise_for_diff(existing) == serialise_for_diff(new_catalog):
        print(f"\n✅ no changes — catalog stays at v{old_version}")
        return 0

    CATALOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CATALOG_PATH.write_text(json.dumps(new_catalog, indent=2) + "\n")
    print(f"\n✅ wrote catalog v{new_catalog['version']} with {len(entries)} entries")
    return 0


if __name__ == "__main__":
    sys.exit(main())
