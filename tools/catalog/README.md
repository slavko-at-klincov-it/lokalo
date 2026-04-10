# Lokalo Catalog Service

Auto-updating catalog generator for Lokalo's `models.json`. Reads a hand-curated
`watchlist.json`, fetches metadata + sampling defaults from HuggingFace, applies
manual overrides for the few models that don't publish sampling values
upstream, and writes the result to `Lokal/Resources/models.json`.

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

1. Reads `watchlist.json` — the list of models we currently track
2. Fetches each model's official `generation_config.json` from HuggingFace
   (with `unsloth/...` mirror as a fallback for gated repos like Llama and
   Gemma)
3. Falls back to `llama.cpp` defaults when the upstream config is missing
   sampling fields entirely (Phi, SmolLM, TinyLlama)
4. Applies entries from `overrides.json` on top — for the handful of cases
   where the upstream value is wrong, missing, or doesn't fit Lokalo's chat
   UX (e.g. Microsoft recommends `temp=0.0` for Phi but Lokalo overrides for
   chat use)
5. Builds a fresh `Lokal/Resources/models.json`, bumps its `version` field
   if anything actually changed, and (when run via `run.sh`) commits + pushes

## Files

| File | Purpose |
|---|---|
| `watchlist.json` | The source of truth for which models are in the catalog. Hand-edited. |
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

## Adding a new model

1. Open `watchlist.json` and add a new entry with `id`, `displayName`,
   `ggufRepo`, `ggufFile`, `originalRepo`, etc. (see existing entries for
   the full schema).
2. (Optional) If you want the model in the "suggested" list shown in the
   onboarding picker, add `"featured": true`.
3. (Optional) If HF doesn't publish sampling values for this model, add an
   entry in `overrides.json` with the values you want.
4. Run `python update_catalog.py` and inspect the diff in
   `Lokal/Resources/models.json`.
5. Commit + push. The Lokalo app picks it up on the next launch.

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
- A Python venv at `tools/catalog/.venv` with `requests` + `jsonschema`
  installed.
