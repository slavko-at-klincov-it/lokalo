"""
llama.cpp-Default sampling values.

These are the values llama.cpp uses when no per-model recommendation is
available. Match `common/sampling.h` in upstream llama.cpp (as of 2024-2026).
The catalog generator falls back to these whenever HuggingFace's
generation_config.json doesn't ship sampling fields.
"""

# Lokalo's GenerationSettings field names (camelCase to match Swift Codable).
LLAMA_CPP_DEFAULTS = {
    "temperature": 0.8,
    "topP": 0.95,
    "topK": 40,
    "minP": 0.05,
    "repetitionPenalty": 1.0,
    "repetitionPenaltyLastN": 64,
}

# Lokalo-specific fields that aren't part of the upstream sampling defaults
# but always need to be present in a generated GenerationSettings record.
LOKALO_DEFAULTS = {
    "maxNewTokens": 512,
    "contextTokens": 4096,
    "seed": 0xFFFFFFFF,
}
