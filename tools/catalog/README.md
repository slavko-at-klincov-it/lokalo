# Lokalo Catalog Service

Auto-updating catalog generator for Lokalo's `models.json`. Discovers new
phone-compatible GGUF models on HuggingFace, fetches metadata + sampling
defaults, applies manual overrides for the few models that don't publish
sampling values upstream, and writes the result to `Lokal/Resources/models.json`.

The Lokalo iOS app then picks up the updated file via the existing
`RemoteCatalogService` (which polls
`https://raw.githubusercontent.com/slavko-at-klincov-it/lokalo/main/Lokal/Resources/models.json`
on every launch).

## Why this exists

Each model family has its own recommended sampling parameters
(`temperature` / `top_p` / `top_k` / `repetition_penalty`). Hard-coding the
same values for every model gives noticeably worse responses than using the
model author's recommendation. Manually editing the catalog every time a new
model is added doesn't scale.

This service:

1. **Discovers** new models via `discover_models.py` — scans bartowski and
   unsloth on HuggingFace for instruction-tuned GGUF models that are
   ≤7B effective parameters, Q4_K_M quantized, and commercially licensed.
   New models are auto-appended to `watchlist.json`.
2. Reads `watchlist.json` — the full list of models we track (hand-curated
   + auto-discovered)
3. Fetches each model's official `generation_config.json` from HuggingFace
   (with `unsloth/...` mirror as a fallback for gated repos like Llama and
   Gemma)
4. Falls back to `llama.cpp` defaults when the upstream config is missing
   sampling fields entirely (Phi, SmolLM, TinyLlama)
5. Applies entries from `overrides.json` on top — for the handful of cases
   where the upstream value is wrong, missing, or doesn't fit Lokalo's chat
   UX (e.g. Microsoft recommends `temp=0.0` for Phi but Lokalo overrides for
   chat use)
6. Builds a fresh `Lokal/Resources/models.json`, bumps its `version` field
   if anything actually changed, and (when run via `run.sh`) commits + pushes

## Files

| File | Purpose |
|---|---|
| `discover_models.py` | Auto-discovery: scans bartowski/unsloth for new phone-class GGUF models. |
| `watchlist.json` | All tracked models (hand-curated + auto-discovered). |
| `overrides.json` | Manual sampling-defaults overrides keyed by model id. Hand-edited. |
| `fetch_metadata.py` | HuggingFace fetcher (generation_config + GGUF size HEAD request). |
| `update_catalog.py` | Main script: reads watchlist + overrides, fetches HF, writes models.json. |
| `validate_catalog.py` | Sanity-check the generated JSON before commit. |
| `llama_cpp_defaults.py` | Fallback sampling constants when HF has nothing. |
| `requirements.txt` | Python deps (`requests`, `jsonschema`). |
| `run.sh` | Wrapper that runs the update + commits + pushes if there's a diff. |
| `launchd/com.slavkoklincov.lokalo-catalog.plist` | macOS launchd plist for daily 04:00 cron on the M4 Mini. |

## Local development

```bash
cd tools/catalog
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

python update_catalog.py        # writes ../../Lokal/Resources/models.json
python validate_catalog.py      # sanity-check the result
```

The script never throws on individual fetch failures — it logs a warning
and skips that entry. A failed run leaves the existing `models.json`
untouched, so a transient HF outage can never break the catalog.

## How new models get added

**Automatic (daily cron):** `discover_models.py` scans bartowski and unsloth
on HuggingFace for new instruction-tuned GGUF models. It filters for Q4_K_M
quantization, ≤7B effective parameters, and commercial licenses. New models
are auto-appended to `watchlist.json`, then `update_catalog.py` fetches their
sizes and sampling defaults.

**Manual:** Open `watchlist.json` and add a new entry with `id`, `displayName`,
`ggufRepo`, `ggufFile`, `originalRepo`, etc. (see existing entries for the
full schema).

In both cases:
1. (Optional) Add `"featured": true` for the onboarding picker.
2. (Optional) Add an `overrides.json` entry if HF has no sampling values.
3. Run `python update_catalog.py` and inspect the diff.
4. Commit + push. The Lokalo app picks it up on the next launch.

**Note:** Auto-discovered models require a matching `chatTemplate` case in
`Lokal/Models/ChatTemplate.swift`. If a new model family uses an unknown
template, the discovery script skips it and logs a warning. Add the template
to the Swift enum + renderer, then re-run discovery.

## Cron / launchd setup (M4 Mini)

```bash
# One-time setup
cp launchd/com.slavkoklincov.lokalo-catalog.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.slavkoklincov.lokalo-catalog.plist

# Test run immediately:
launchctl start com.slavkoklincov.lokalo-catalog
tail -20 ~/Library/Logs/lokalo-catalog.log
```

The plist runs `tools/catalog/run.sh` daily at 04:00. Logs land in
`~/Library/Logs/lokalo-catalog.log`.

Requires:
- A working SSH key on the M4 Mini that has push access to
  `slavko-at-klincov-it/lokalo` (`git remote -v` should show
  `git@github.com:...`, not `https://...`).
- The repo cloned at `~/lokalo`.
- A Python venv at `tools/catalog/.venv` with `requests` installed.

**Important:** After loading the plist, verify the path matches your repo
location. The plist currently expects `~/lokalo`.
