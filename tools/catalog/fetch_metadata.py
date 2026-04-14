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

import struct
import tempfile
import time

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
    Retries once after 2s on timeout or 5xx. Returns `None` on failure.
    """
    if session is None:
        session = _session()
    url = f"https://huggingface.co/{repo}/resolve/main/{filename}"
    for attempt in range(2):
        try:
            r = session.head(url, allow_redirects=True, timeout=DEFAULT_TIMEOUT)
            if r.status_code == 200:
                size = r.headers.get("Content-Length")
                return int(size) if size else None
            if r.status_code >= 500 and attempt == 0:
                print(f"   ⚠️  fetch_gguf_size: HTTP {r.status_code}, retrying…")
                time.sleep(2)
                continue
            return None
        except Exception as e:
            if attempt == 0:
                print(f"   ⚠️  fetch_gguf_size({repo}/{filename}): {e}, retrying…")
                time.sleep(2)
                continue
            print(f"   ⚠️  fetch_gguf_size({repo}/{filename}) failed: {e}")
            return None
    return None


def fetch_gguf_context_length(
    repo: str, filename: str, session: requests.Session | None = None
) -> int | None:
    """
    Fetch the first 256 KB of a GGUF file and parse the header to extract
    the context length ({arch}.context_length).  This is the authoritative
    value -- it's exactly what llama.cpp reads when loading the model.
    """
    if session is None:
        session = _session()
    url = f"https://huggingface.co/{repo}/resolve/main/{filename}"
    try:
        r = session.get(
            url, headers={"Range": "bytes=0-262143"}, timeout=DEFAULT_TIMEOUT
        )
        if r.status_code not in (200, 206) or len(r.content) < 24:
            return None
    except Exception:
        return None

    data = r.content
    # GGUF header: magic(4) + version(4) + tensor_count(8) + kv_count(8)
    if data[:4] != b"GGUF":
        return None
    try:
        kv_count = struct.unpack("<Q", data[16:24])[0]
    except struct.error:
        return None

    offset = 24
    for _ in range(kv_count):
        if offset + 12 > len(data):
            break
        # Read key string
        slen = struct.unpack("<Q", data[offset : offset + 8])[0]
        offset += 8
        if offset + slen > len(data):
            break
        key = data[offset : offset + slen].decode("utf-8", errors="replace")
        offset += slen
        if offset + 4 > len(data):
            break
        vtype = struct.unpack("<I", data[offset : offset + 4])[0]
        offset += 4

        # Type 4 = uint32
        if vtype == 4 and offset + 4 <= len(data):
            val = struct.unpack("<I", data[offset : offset + 4])[0]
            offset += 4
            if key.endswith(".context_length"):
                return val
        elif vtype == 5 and offset + 4 <= len(data):  # int32
            offset += 4
        elif vtype == 8:  # string
            if offset + 8 > len(data):
                break
            sl = struct.unpack("<Q", data[offset : offset + 8])[0]
            offset += 8 + sl
        elif vtype == 10 and offset + 4 <= len(data):  # float32
            offset += 4
        elif vtype in (6, 7, 11) and offset + 8 <= len(data):  # u64/i64/f64
            offset += 8
        elif vtype in (0, 1, 12) and offset + 1 <= len(data):  # u8/i8/bool
            offset += 1
        elif vtype in (2, 3) and offset + 2 <= len(data):  # u16/i16
            offset += 2
        elif vtype == 9:  # array
            if offset + 12 > len(data):
                break
            arr_type = struct.unpack("<I", data[offset : offset + 4])[0]
            arr_len = struct.unpack("<Q", data[offset + 4 : offset + 12])[0]
            offset += 12
            elem_sizes = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 8, 7: 8, 10: 4, 11: 8, 12: 1}
            if arr_type in elem_sizes:
                offset += arr_len * elem_sizes[arr_type]
            elif arr_type == 8:  # string array
                for _ in range(arr_len):
                    if offset + 8 > len(data):
                        return None
                    sl = struct.unpack("<Q", data[offset : offset + 8])[0]
                    offset += 8 + sl
            else:
                break
        else:
            break  # unknown type, stop parsing

    return None


def fetch_ollama_params(ollama_tag: str | None, session: requests.Session | None = None) -> dict | None:
    """
    Fetch sampling defaults from the Ollama registry.
    Tag format: "family:size" (e.g. "gemma4:e4b").
    Returns a dict with Lokalo keys (temperature, topP, topK) or None.
    """
    if not ollama_tag or ":" not in ollama_tag:
        return None
    if session is None:
        session = _session()
    family, tag = ollama_tag.split(":", 1)
    manifest_url = f"https://registry.ollama.ai/v2/library/{family}/manifests/{tag}"
    try:
        r = session.get(manifest_url, timeout=DEFAULT_TIMEOUT)
        if r.status_code != 200:
            return None
        manifest = r.json()
        # Find the params blob
        for layer in manifest.get("layers", []):
            if layer.get("mediaType") == "application/vnd.ollama.image.params":
                digest = layer["digest"]
                blob_url = f"https://registry.ollama.ai/v2/library/{family}/blobs/{digest}"
                br = session.get(blob_url, timeout=DEFAULT_TIMEOUT)
                if br.status_code == 200:
                    params = br.json()
                    out: dict = {}
                    if "temperature" in params:
                        out["temperature"] = params["temperature"]
                    if "top_p" in params:
                        out["topP"] = params["top_p"]
                    if "top_k" in params:
                        out["topK"] = params["top_k"]
                    return out if out else None
    except Exception:
        pass
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


def resolve_sampling_defaults(
    model: dict, override: dict | None, *, recommended_context_tokens: int
) -> dict:
    """
    Cascade for a single model's sampling defaults:
        1. HF originalRepo generation_config.json
        2. HF unsloth_fallback_repo generation_config.json
        3. Ollama registry params blob
        4. llama.cpp defaults (LLAMA_CPP_DEFAULTS)
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

    # Ollama params as mid-layer (above llama.cpp defaults, below HF)
    ollama_params = fetch_ollama_params(model.get("ollamaTag"), session)
    if ollama_params:
        sampling.update(ollama_params)

    if hf_config:
        sampling.update(normalise_sampling(hf_config))
    if override:
        sampling.update({k: v for k, v in override.items() if k != "note"})

    # Add Lokalo-specific fields that always need to be present.
    result = {**sampling, **LOKALO_DEFAULTS}
    result["contextTokens"] = recommended_context_tokens
    return result
