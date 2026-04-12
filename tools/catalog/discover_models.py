"""
Auto-discovery of new phone-compatible GGUF models on HuggingFace.

Scans known GGUF providers (bartowski, unsloth) for instruction-tuned
models that:
  1. Have a Q4_K_M quantized GGUF file
  2. Are ≤7B effective parameters (phone-class)
  3. Use a commercially-redistributable license

Newly discovered models are appended to `watchlist.json`.  The existing
`update_catalog.py` pipeline then fetches sizes and sampling defaults on
the next run.

Designed to run *before* update_catalog.py in the daily cron (run.sh).
"""
from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path
from typing import Any

import requests

SCRIPT_DIR = Path(__file__).resolve().parent
WATCHLIST_PATH = SCRIPT_DIR / "watchlist.json"

MAX_EFFECTIVE_BILLION = 7.0

# ── HuggingFace API ────────────────────────────────────────────────────

HF_API = "https://huggingface.co/api"
USER_AGENT = "lokalo-catalog-discover/1.0"
TIMEOUT = 15
REQUEST_DELAY = 0.25  # seconds between API calls to avoid rate-limiting

# ── GGUF providers to scan ─────────────────────────────────────────────

PROVIDERS = ["bartowski", "unsloth"]

# When both providers have a GGUF for the same model, prefer this one.
# Key = substring in base-model name (lowercased).
PROVIDER_PREFERENCES: dict[str, str] = {
    "gemma": "unsloth",
}

# ── License allow-list ─────────────────────────────────────────────────

COMMERCIAL_LICENSES: dict[str, str] = {
    # HF license tag (lowercase) → Lokalo display label
    "apache-2.0":   "Apache 2.0",
    "mit":          "MIT",
    "bsd-3-clause": "BSD-3-Clause",
    "llama2":       "Llama 2 Community",
    "llama3":       "Llama 3 Community",
    "llama3.1":     "Llama 3.1 Community",
    "llama3.2":     "Llama 3.2 Community",
    "llama3.3":     "Llama 3.3 Community",
    "llama4":       "Llama 4 Community",
    "gemma":        "Gemma Terms",
    "cc-by-4.0":    "CC BY 4.0",
    "cc-by-sa-4.0": "CC BY-SA 4.0",
}

# ── Chat-template detection ────────────────────────────────────────────

# Ordered list: first match wins.  Pattern is tested against the
# lowercased base-model repo name (org/model).
TEMPLATE_RULES: list[tuple[str, str]] = [
    ("llama-3", "llama3"),
    ("llama-4", "llama3"),
    ("qwen3",   "qwen3"),   # Qwen 3.x (incl. 3.5) uses qwen3 template
    ("qwen2",   "chatml"),  # Qwen 2.x uses ChatML
    ("qwen",    "chatml"),  # Older Qwen fallback
    ("phi-4",   "phi4"),
    ("phi-3",   "phi3"),
    ("gemma-4", "gemma4"),  # Gemma 4 uses <|turn>/<turn|> framing
    ("gemma4",  "gemma4"),
    ("gemma",   "gemma"),   # Gemma 2/3 use <start_of_turn>/<end_of_turn>
    ("smollm",  "chatml"),
    ("mistral", "chatml"),
]

# ── Org-to-publisher mapping ───────────────────────────────────────────

PUBLISHERS: dict[str, str] = {
    "meta-llama":    "Meta",
    "qwen":          "Alibaba",
    "microsoft":     "Microsoft",
    "google":        "Google",
    "huggingfacetb": "HuggingFace",
    "tinyllama":     "TinyLlama",
    "mistralai":     "Mistral",
}

# Fallback: infer HF org from model-name prefix when base_model is
# missing (common for unsloth repos).
NAME_TO_ORG: dict[str, str] = {
    "gemma":   "google",
    "llama":   "meta-llama",
    "qwen":    "Qwen",
    "phi":     "microsoft",
    "smollm":  "HuggingFaceTB",
    "mistral": "mistralai",
}

# Instruct / chat model name patterns (case-insensitive).
INSTRUCT_RE = re.compile(r"(?:instruct|chat|[\-_]it(?:[\-_]|$))", re.IGNORECASE)


# ── Helpers ────────────────────────────────────────────────────────────

def _session() -> requests.Session:
    s = requests.Session()
    s.headers.update({"User-Agent": USER_AGENT})
    return s


def _delay() -> None:
    time.sleep(REQUEST_DELAY)


# ── HuggingFace API helpers ────────────────────────────────────────────

def list_gguf_repos(author: str, session: requests.Session) -> list[dict]:
    """Paginate through an author's GGUF repos (newest first)."""
    all_repos: list[dict] = []
    params: dict[str, Any] = {
        "author": author,
        "search": "GGUF",
        "sort": "lastModified",
        "direction": "-1",
        "limit": 100,
        "full": "true",   # include siblings (file list)
    }
    # HF paginates via Link header, but we just fetch one big batch.
    # 100 most-recently-modified repos is plenty for daily discovery.
    try:
        r = session.get(f"{HF_API}/models", params=params, timeout=TIMEOUT)
        if r.status_code == 200:
            all_repos = r.json()
        else:
            print(f"  ⚠️  listing {author}: HTTP {r.status_code}")
    except Exception as e:
        print(f"  ⚠️  listing {author} failed: {e}")
    return all_repos


def find_q4km_file(siblings: list[dict]) -> str | None:
    """Return the Q4_K_M .gguf filename if present."""
    for f in siblings:
        name = f.get("rfilename", "")
        if name.endswith(".gguf") and "Q4_K_M" in name:
            return name
    return None


def get_base_model(repo_info: dict) -> str | None:
    """Extract the original (source) model repo from a GGUF repo's card."""
    card = repo_info.get("cardData") or {}
    base = card.get("base_model")
    if isinstance(base, str) and "/" in base:
        return base
    if isinstance(base, list):
        for b in base:
            if isinstance(b, str) and "/" in b:
                return b
    return None


def infer_base_model(gguf_repo: str) -> str | None:
    """
    Best-effort fallback when the GGUF repo has no base_model metadata.
    Works by stripping the provider prefix and the -GGUF suffix, then
    trying to map the remaining name to an org/model path.

    Examples:
        unsloth/gemma-4-E2B-it-GGUF  →  google/gemma-4-E2B-it
        bartowski/Qwen_Qwen3.5-0.8B-GGUF  →  Qwen/Qwen3.5-0.8B
    """
    name = gguf_repo.split("/", 1)[-1]            # drop provider
    name = re.sub(r"-GGUF$", "", name, flags=re.IGNORECASE)

    # bartowski uses org_model naming: "Qwen_Qwen3.5-0.8B"
    if "_" in name:
        parts = name.split("_", 1)
        return f"{parts[0]}/{parts[1]}"

    # unsloth uses plain model names: "gemma-4-E2B-it"
    name_lower = name.lower()
    for prefix, org in NAME_TO_ORG.items():
        if name_lower.startswith(prefix):
            return f"{org}/{name}"

    return None


def fetch_model_info(repo: str, session: requests.Session) -> dict | None:
    """GET /api/models/{repo} — full model metadata."""
    try:
        _delay()
        r = session.get(f"{HF_API}/models/{repo}", timeout=TIMEOUT)
        if r.status_code == 200:
            return r.json()
    except Exception:
        pass
    return None


def fetch_config_json(repo: str, session: requests.Session) -> dict | None:
    """Fetch config.json (model architecture) from a repo."""
    url = f"https://huggingface.co/{repo}/raw/main/config.json"
    try:
        _delay()
        r = session.get(url, timeout=TIMEOUT)
        if r.status_code == 200:
            return r.json()
    except Exception:
        pass
    return None


# ── Metadata extraction ────────────────────────────────────────────────

def get_parameter_count(
    model_info: dict, config: dict | None
) -> tuple[float, float] | None:
    """
    Return (total_billion, active_billion).
    active < total for MoE (name *B-A*B) or PLE (name E*B) models.
    Returns None when the count cannot be determined.
    """
    name = (model_info.get("modelId") or "").split("/")[-1]

    # 1. safetensors.total (most reliable)
    safetensors = model_info.get("safetensors") or {}
    if "total" in safetensors:
        total = safetensors["total"] / 1e9
    else:
        # 2. parse from model name
        m = re.search(r"(\d+(?:\.\d+)?)\s*[Bb]", name)
        if m:
            total = float(m.group(1))
        else:
            return None

    active = total  # default: dense model

    # MoE pattern: "35B-A3B" → active = 3
    moe = re.search(r"[\-_]A(\d+(?:\.\d+)?)[Bb]", name)
    if moe:
        active = float(moe.group(1))

    # PLE pattern: "E2B" → active = 2 (Gemma 4 edge models)
    ple = re.search(r"E(\d+(?:\.\d+)?)[Bb]", name)
    if ple:
        active = float(ple.group(1))

    return (round(total, 2), round(active, 2))


def get_context_length(config: dict | None) -> int:
    """Best-effort context-length detection from config.json."""
    if not config:
        return 4096

    # Direct keys
    for key in ("max_position_embeddings", "max_seq_len", "n_positions",
                "seq_length"):
        val = config.get(key)
        if isinstance(val, int) and val > 0:
            return val

    # Nested in text_config (multimodal models)
    tc = config.get("text_config") or {}
    for key in ("max_position_embeddings", "max_seq_len"):
        val = tc.get(key)
        if isinstance(val, int) and val > 0:
            return val

    return 4096


def get_license_tag(model_info: dict) -> str | None:
    """Return the lowercase HF license tag."""
    card = model_info.get("cardData") or {}
    lic = card.get("license")
    if isinstance(lic, str):
        return lic.strip().lower()
    for tag in model_info.get("tags", []):
        if tag.startswith("license:"):
            return tag.split(":", 1)[1].strip().lower()
    return None


def detect_template(base_model: str) -> str | None:
    """Return the Lokalo ChatTemplate family string, or None."""
    key = base_model.lower()
    for pattern, family in TEMPLATE_RULES:
        if pattern in key:
            return family
    return None


# ── Entry generation ───────────────────────────────────────────────────

def make_display_name(base_model: str) -> str:
    """
    Derive a human-friendly display name from the base model repo.
    e.g.  "Qwen/Qwen3.5-0.8B"  →  "Qwen 3.5 0.8B"
          "google/gemma-4-E2B-it"  →  "Gemma 4 E2B"
    """
    raw = base_model.split("/")[-1]
    # Strip common suffixes
    for suffix in ("-Instruct", "-instruct", "-it", "-chat", "-Chat"):
        if raw.endswith(suffix):
            raw = raw[: -len(suffix)]
    # Replace hyphens/underscores with spaces
    name = re.sub(r"[\-_]", " ", raw)
    # Collapse multiple spaces
    name = re.sub(r"\s+", " ", name).strip()
    return name


def make_summary(publisher: str, display_name: str, ctx: int, license_label: str) -> str:
    """Generate a one-line summary for a new model."""
    ctx_label = f"{ctx // 1024}K" if ctx >= 1024 else str(ctx)
    return f"{publisher} {display_name}. {ctx_label} Kontext, {license_label}-Lizenz."


def make_id(base_model: str) -> str:
    """
    Stable, filesystem-safe catalog id.
    e.g.  "Qwen/Qwen3.5-0.8B"  →  "qwen3.5-0.8b-q4km"
          "google/gemma-4-E2B-it"  →  "gemma-4-e2b-it-q4km"
    """
    raw = base_model.split("/")[-1].lower()
    for suffix in ("-instruct",):
        if raw.endswith(suffix):
            raw = raw[: -len(suffix)]
    raw = re.sub(r"[^a-z0-9.\-]", "-", raw)
    raw = re.sub(r"-+", "-", raw).strip("-")
    return f"{raw}-q4km"


def make_ollama_tag(base_model: str, active_b: float) -> str | None:
    """Best-effort Ollama tag.  Returns None when uncertain."""
    name = base_model.split("/")[-1].lower()
    # e.g. "qwen3.5" prefix + size
    for family in ("qwen3.5", "qwen3", "qwen2.5", "gemma4", "gemma3",
                   "gemma2", "llama3.2", "llama3.1", "phi4", "phi3.5",
                   "smollm2", "smollm3"):
        if family.replace(".", "") in name.replace(".", "").replace("-", ""):
            size = f"{active_b}b" if active_b >= 1 else f"{int(active_b * 1000)}m"
            tag_family = family.replace(".", "")
            # Fix: ollama uses dots for versions, e.g. qwen3.5
            tag_family = family
            return f"{tag_family}:{size}"
    return None


# ── Main discovery logic ───────────────────────────────────────────────

def discover() -> list[dict]:
    """
    Scan HuggingFace for new phone-compatible GGUF models.
    Returns a list of new watchlist entries (dicts).
    """
    watchlist = json.loads(WATCHLIST_PATH.read_text())
    existing_bases = {
        m.get("originalRepo", "").lower() for m in watchlist["models"]
    }
    existing_ids = {m["id"] for m in watchlist["models"]}

    session = _session()
    new_entries: list[dict] = []
    seen_bases: set[str] = set()

    for provider in PROVIDERS:
        print(f"\n→ Scanning {provider}…")
        repos = list_gguf_repos(provider, session)
        print(f"  {len(repos)} GGUF repos found")

        for repo_info in repos:
            gguf_repo = repo_info["modelId"]
            siblings = repo_info.get("siblings", [])

            q4km = find_q4km_file(siblings)
            if not q4km:
                continue

            base = get_base_model(repo_info) or infer_base_model(gguf_repo)
            if not base:
                continue

            base_lower = base.lower()
            if base_lower in existing_bases or base_lower in seen_bases:
                continue

            if not INSTRUCT_RE.search(base):
                continue

            # Provider preference: skip if a preferred provider exists and
            # this isn't it.  The preferred provider's scan will pick it up.
            preferred = "bartowski"
            for pat, prov in PROVIDER_PREFERENCES.items():
                if pat in base_lower:
                    preferred = prov
                    break
            if provider != preferred:
                continue

            print(f"\n  📋 {gguf_repo}")
            print(f"     base:  {base}")
            print(f"     file:  {q4km}")

            # ── Fetch source metadata ──────────────────────────────────
            source = fetch_model_info(base, session)
            if not source:
                print(f"     ⚠️  cannot fetch source model — skipping")
                continue

            config = fetch_config_json(base, session)

            # Parameter check
            params = get_parameter_count(source, config)
            if params is None:
                print(f"     ⚠️  cannot determine parameters — skipping")
                continue
            total_b, active_b = params
            if active_b > MAX_EFFECTIVE_BILLION:
                print(f"     ⏭  {active_b}B active > {MAX_EFFECTIVE_BILLION}B limit")
                continue

            # License check
            lic_tag = get_license_tag(source)
            if not lic_tag or lic_tag not in COMMERCIAL_LICENSES:
                print(f"     ⏭  license '{lic_tag}' not in allow-list")
                continue
            lic_label = COMMERCIAL_LICENSES[lic_tag]

            # Chat template
            template = detect_template(base)
            if not template:
                print(f"     ⚠️  unknown chat template — skipping")
                continue

            max_ctx = get_context_length(config)
            model_id = make_id(base)
            if model_id in existing_ids:
                continue

            publisher = PUBLISHERS.get(base.split("/")[0].lower(),
                                       base.split("/")[0])
            display = make_display_name(base)
            summary = make_summary(publisher, display, max_ctx, lic_label)

            entry: dict[str, Any] = {
                "id": model_id,
                "displayName": display,
                "ollamaTag": make_ollama_tag(base, active_b),
                "publisher": publisher,
                "summary": summary,
                "parametersBillion": total_b,
                "quantization": "Q4_K_M",
                "ggufRepo": gguf_repo,
                "ggufFile": q4km,
                "originalRepo": base,
                "chatTemplate": template,
                "licenseLabel": lic_label,
                "maxContextTokens": max_ctx,
                "recommendedContextTokens": min(4096, max_ctx),
            }

            if abs(total_b - active_b) > 0.1:
                entry["activeParametersBillion"] = active_b

            # Try to find unsloth fallback for gated repos
            if provider != "unsloth":
                fallback = f"unsloth/{base.split('/')[-1]}"
                entry["unsloth_fallback_repo"] = fallback

            new_entries.append(entry)
            seen_bases.add(base_lower)
            existing_ids.add(model_id)
            print(f"     ✅ NEW: {model_id}  "
                  f"({active_b}B active, {lic_label}, {template})")

    return new_entries


def merge_into_watchlist(new_entries: list[dict]) -> int:
    """Append new entries to watchlist.json. Returns count added."""
    if not new_entries:
        return 0

    watchlist = json.loads(WATCHLIST_PATH.read_text())
    watchlist["models"].extend(new_entries)
    WATCHLIST_PATH.write_text(json.dumps(watchlist, indent=2) + "\n")
    return len(new_entries)


def main() -> int:
    print(f"Lokalo model discovery — {time.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"watchlist: {WATCHLIST_PATH.relative_to(SCRIPT_DIR.parent.parent)}")
    print(f"max effective B: {MAX_EFFECTIVE_BILLION}")

    new = discover()

    if not new:
        print("\nℹ️  no new models discovered")
        return 0

    count = merge_into_watchlist(new)
    print(f"\n✅ added {count} new model(s) to watchlist.json:")
    for e in new:
        print(f"   • {e['id']}  ({e['publisher']}, {e['parametersBillion']}B, {e['chatTemplate']})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
