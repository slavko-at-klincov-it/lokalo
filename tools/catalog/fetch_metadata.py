"""
HuggingFace metadata fetcher for the Lokalo catalog generator.

Each model entry knows its `originalRepo` (gold-source HF repo) and
optionally an `unsloth_fallback_repo` (used when the gold-source is gated
behind Meta/Google authentication). Sampling values come from
`generation_config.json` in either repo; GGUF size comes from a HEAD
request against the bartowski/unsloth mirror.

Failure modes are non-fatal: a 404 on generation_config.json just falls
through to the next layer of the cascade. The caller decides whether a
total failure is fatal (e.g. missing GGUF size aborts that entry but does
not crash the run).
"""
from __future__ import annotations

import requests

from llama_cpp_defaults import LLAMA_CPP_DEFAULTS, LOKALO_DEFAULTS

# HF generation_config.json keys → Lokalo GenerationSettings keys.
# Anything in the HF JSON that isn't in this mapping is silently dropped.
HF_TO_LOKALO_KEYS = {
    "temperature": "temperature",
    "top_p": "topP",
    "top_k": "topK",
    "min_p": "minP",
    "repetition_penalty": "repetitionPenalty",
}

DEFAULT_TIMEOUT = 15
USER_AGENT = "lokalo-catalog-service/1.0 (+https://github.com/slavko-at-klincov-it/lokalo)"


def _session() -> requests.Session:
    s = requests.Session()
    s.headers.update({"User-Agent": USER_AGENT})
    return s


def fetch_generation_config(repo: str, session: requests.Session | None = None) -> dict | None:
    """
    Fetch `generation_config.json` for a HuggingFace repo. Returns the
    parsed dict, or `None` if the file is missing, gated, or malformed.

    URL form: https://huggingface.co/{repo}/raw/main/generation_config.json
    """
    if session is None:
        session = _session()
    url = f"https://huggingface.co/{repo}/raw/main/generation_config.json"
    try:
        r = session.get(url, timeout=DEFAULT_TIMEOUT)
        if r.status_code == 200:
            return r.json()
        return None
    except Exception as e:
        print(f"   ⚠️  fetch_generation_config({repo}) failed: {e}")
        return None


def fetch_gguf_size(repo: str, filename: str, session: requests.Session | None = None) -> int | None:
    """
    HEAD-request the GGUF file on the HF CDN to get its size in bytes.
    Returns `None` on any failure (404, network error, missing
    Content-Length header).
    """
    if session is None:
        session = _session()
    url = f"https://huggingface.co/{repo}/resolve/main/{filename}"
    try:
        r = session.head(url, allow_redirects=True, timeout=DEFAULT_TIMEOUT)
        if r.status_code != 200:
            return None
        size = r.headers.get("Content-Length")
        if size is None:
            return None
        return int(size)
    except Exception as e:
        print(f"   ⚠️  fetch_gguf_size({repo}/{filename}) failed: {e}")
        return None


def normalise_sampling(hf_config: dict) -> dict:
    """
    Project an HF generation_config.json dict into Lokalo's
    GenerationSettings field names. Drops any HF key we don't know about.
    """
    out: dict = {}
    for hf_key, lokalo_key in HF_TO_LOKALO_KEYS.items():
        if hf_key in hf_config:
            value = hf_config[hf_key]
            # Some HF configs use list-of-eos but always single floats for
            # the sampling fields, so a quick type check is enough.
            if isinstance(value, (int, float)):
                out[lokalo_key] = value
    return out


def resolve_sampling_defaults(model: dict, override: dict | None) -> dict:
    """
    Cascade for a single model's sampling defaults:
        1. HF originalRepo generation_config.json
        2. HF unsloth_fallback_repo generation_config.json
        3. llama.cpp defaults (LLAMA_CPP_DEFAULTS)
    Then merge `override` on top, dropping the human-only `note` field.
    Always returns a dict containing the full Lokalo GenerationSettings
    schema (sampling fields + Lokalo-specific Lokalo defaults).
    """
    session = _session()

    hf_config: dict | None = None
    if model.get("originalRepo"):
        hf_config = fetch_generation_config(model["originalRepo"], session)
    if hf_config is None and model.get("unsloth_fallback_repo"):
        hf_config = fetch_generation_config(model["unsloth_fallback_repo"], session)

    sampling: dict = dict(LLAMA_CPP_DEFAULTS)  # base layer
    if hf_config:
        sampling.update(normalise_sampling(hf_config))
    if override:
        sampling.update({k: v for k, v in override.items() if k != "note"})

    # Add Lokalo-specific fields that always need to be present.
    return {**sampling, **LOKALO_DEFAULTS}
