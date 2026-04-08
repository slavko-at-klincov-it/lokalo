//
//  ModelCatalog.swift
//  Lokal
//
//  Curated catalog of GGUF models that fit on iPhone.
//  All URLs verified against bartowski/* / unsloth/* / ggml-org/* HuggingFace mirrors (April 2026).
//  Sizes are exact Content-Length values from the LFS CDN.
//

import Foundation

enum ModelCatalog {
    static let all: [ModelEntry] = [
        // MARK: Llama 3.2 family (Meta, ungated via bartowski)
        ModelEntry(
            id: "llama-3.2-1b-instruct-q4km",
            displayName: "Llama 3.2 1B Instruct",
            ollamaTag: "llama3.2:1b",
            publisher: "Meta",
            summary: "Meta's smallest assistant. Tiny footprint, fast on any iPhone, multilingual, 128K context.",
            parametersBillion: 1.23,
            quantization: "Q4_K_M",
            sizeBytes: 807_694_464,
            estimatedRAMBytes: 1_073_741_824,
            downloadURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf")!,
            filename: "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
            chatTemplate: .llama3,
            licenseLabel: "Llama 3.2 Community",
            maxContextTokens: 131072,
            recommendedContextTokens: 4096
        ),
        ModelEntry(
            id: "llama-3.2-3b-instruct-q4km",
            displayName: "Llama 3.2 3B Instruct",
            ollamaTag: "llama3.2:3b",
            publisher: "Meta",
            summary: "The flagship phone-class assistant. Best chat quality at this size, 128K context.",
            parametersBillion: 3.21,
            quantization: "Q4_K_M",
            sizeBytes: 2_019_377_696,
            estimatedRAMBytes: 2_576_980_377,
            downloadURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf")!,
            filename: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            chatTemplate: .llama3,
            licenseLabel: "Llama 3.2 Community",
            maxContextTokens: 131072,
            recommendedContextTokens: 4096
        ),

        // MARK: Qwen 2.5 family (Alibaba, Apache 2.0)
        ModelEntry(
            id: "qwen-2.5-0.5b-instruct-q4km",
            displayName: "Qwen 2.5 0.5B Instruct",
            ollamaTag: "qwen2.5:0.5b",
            publisher: "Alibaba",
            summary: "Tiny, snappy, multilingual. Great for ultra-low-end devices and quick responses.",
            parametersBillion: 0.49,
            quantization: "Q4_K_M",
            sizeBytes: 397_808_192,
            estimatedRAMBytes: 536_870_912,
            downloadURL: URL(string: "https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf")!,
            filename: "Qwen2.5-0.5B-Instruct-Q4_K_M.gguf",
            chatTemplate: .chatml,
            licenseLabel: "Apache 2.0",
            maxContextTokens: 32768,
            recommendedContextTokens: 4096
        ),
        ModelEntry(
            id: "qwen-2.5-1.5b-instruct-q4km",
            displayName: "Qwen 2.5 1.5B Instruct",
            ollamaTag: "qwen2.5:1.5b",
            publisher: "Alibaba",
            summary: "Excellent quality-per-byte. Strong reasoning and coding for its size, 32K context.",
            parametersBillion: 1.54,
            quantization: "Q4_K_M",
            sizeBytes: 986_048_768,
            estimatedRAMBytes: 1_395_864_371,
            downloadURL: URL(string: "https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf")!,
            filename: "Qwen2.5-1.5B-Instruct-Q4_K_M.gguf",
            chatTemplate: .chatml,
            licenseLabel: "Apache 2.0",
            maxContextTokens: 32768,
            recommendedContextTokens: 4096
        ),
        ModelEntry(
            id: "qwen-2.5-3b-instruct-q4km",
            displayName: "Qwen 2.5 3B Instruct",
            ollamaTag: "qwen2.5:3b",
            publisher: "Alibaba",
            summary: "Best 3B-class for code, math and structured output. Punches above its weight.",
            parametersBillion: 3.09,
            quantization: "Q4_K_M",
            sizeBytes: 1_929_903_264,
            estimatedRAMBytes: 2_576_980_377,
            downloadURL: URL(string: "https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf")!,
            filename: "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
            chatTemplate: .chatml,
            licenseLabel: "Qwen Research",
            maxContextTokens: 32768,
            recommendedContextTokens: 4096
        ),

        // MARK: Phi family (Microsoft, MIT)
        ModelEntry(
            id: "phi-3.5-mini-instruct-q4km",
            displayName: "Phi-3.5 Mini",
            ollamaTag: "phi3.5:3.8b",
            publisher: "Microsoft",
            summary: "Strong reasoning and instruction following, 128K context, MIT license.",
            parametersBillion: 3.82,
            quantization: "Q4_K_M",
            sizeBytes: 2_393_232_672,
            estimatedRAMBytes: 3_006_477_107,
            downloadURL: URL(string: "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf")!,
            filename: "Phi-3.5-mini-instruct-Q4_K_M.gguf",
            chatTemplate: .phi3,
            licenseLabel: "MIT",
            maxContextTokens: 131072,
            recommendedContextTokens: 4096
        ),
        ModelEntry(
            id: "phi-4-mini-instruct-q4km",
            displayName: "Phi-4 Mini",
            ollamaTag: "phi4-mini:3.8b",
            publisher: "Microsoft",
            summary: "Microsoft's best small reasoner. Beats much larger models on math benchmarks.",
            parametersBillion: 3.84,
            quantization: "Q4_K_M",
            sizeBytes: 2_491_874_688,
            estimatedRAMBytes: 3_006_477_107,
            downloadURL: URL(string: "https://huggingface.co/bartowski/microsoft_Phi-4-mini-instruct-GGUF/resolve/main/microsoft_Phi-4-mini-instruct-Q4_K_M.gguf")!,
            filename: "microsoft_Phi-4-mini-instruct-Q4_K_M.gguf",
            chatTemplate: .phi4,
            licenseLabel: "MIT",
            maxContextTokens: 131072,
            recommendedContextTokens: 4096
        ),

        // MARK: Gemma family (Google)
        ModelEntry(
            id: "gemma-2-2b-it-q4km",
            displayName: "Gemma 2 2B",
            ollamaTag: "gemma2:2b",
            publisher: "Google",
            summary: "Polished, friendly assistant tone. Excellent multilingual chat.",
            parametersBillion: 2.61,
            quantization: "Q4_K_M",
            sizeBytes: 1_708_582_752,
            estimatedRAMBytes: 2_147_483_648,
            downloadURL: URL(string: "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf")!,
            filename: "gemma-2-2b-it-Q4_K_M.gguf",
            chatTemplate: .gemma,
            licenseLabel: "Gemma Terms",
            maxContextTokens: 8192,
            recommendedContextTokens: 4096
        ),
        ModelEntry(
            id: "gemma-3-1b-it-q4km",
            displayName: "Gemma 3 1B",
            ollamaTag: "gemma3:1b",
            publisher: "Google",
            summary: "Newest Google small text model, 32K context, QAT-trained checkpoints.",
            parametersBillion: 1.0,
            quantization: "Q4_K_M",
            sizeBytes: 806_058_272,
            estimatedRAMBytes: 1_181_116_006,
            downloadURL: URL(string: "https://huggingface.co/unsloth/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf")!,
            filename: "gemma-3-1b-it-Q4_K_M.gguf",
            chatTemplate: .gemma,
            licenseLabel: "Gemma Terms",
            maxContextTokens: 32768,
            recommendedContextTokens: 4096
        ),
        ModelEntry(
            id: "gemma-3-4b-it-q4km",
            displayName: "Gemma 3 4B",
            ollamaTag: "gemma3:4b",
            publisher: "Google",
            summary: "Best Gemma 3 size that still fits on phone. 128K context (text-only inference).",
            parametersBillion: 4.3,
            quantization: "Q4_K_M",
            sizeBytes: 2_489_894_016,
            estimatedRAMBytes: 3_221_225_472,
            downloadURL: URL(string: "https://huggingface.co/unsloth/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf")!,
            filename: "gemma-3-4b-it-Q4_K_M.gguf",
            chatTemplate: .gemma,
            licenseLabel: "Gemma Terms",
            maxContextTokens: 131072,
            recommendedContextTokens: 4096
        ),

        // MARK: SmolLM family (HuggingFace, Apache 2.0)
        ModelEntry(
            id: "smollm2-1.7b-instruct-q4km",
            displayName: "SmolLM2 1.7B",
            ollamaTag: "smollm2:1.7b",
            publisher: "HuggingFace",
            summary: "Fully-open data and weights. Strong assistant for its size.",
            parametersBillion: 1.71,
            quantization: "Q4_K_M",
            sizeBytes: 1_055_609_824,
            estimatedRAMBytes: 1_503_238_553,
            downloadURL: URL(string: "https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q4_K_M.gguf")!,
            filename: "SmolLM2-1.7B-Instruct-Q4_K_M.gguf",
            chatTemplate: .chatml,
            licenseLabel: "Apache 2.0",
            maxContextTokens: 8192,
            recommendedContextTokens: 4096
        ),
        ModelEntry(
            id: "smollm3-3b-q4km",
            displayName: "SmolLM3 3B",
            ollamaTag: nil,
            publisher: "HuggingFace",
            summary: "Open dataset + weights. Outperforms Llama-3.2-3B at the 3B class.",
            parametersBillion: 3.08,
            quantization: "Q4_K_M",
            sizeBytes: 1_915_305_792,
            estimatedRAMBytes: 2_469_606_195,
            downloadURL: URL(string: "https://huggingface.co/bartowski/HuggingFaceTB_SmolLM3-3B-GGUF/resolve/main/HuggingFaceTB_SmolLM3-3B-Q4_K_M.gguf")!,
            filename: "HuggingFaceTB_SmolLM3-3B-Q4_K_M.gguf",
            chatTemplate: .chatml,
            licenseLabel: "Apache 2.0",
            maxContextTokens: 65536,
            recommendedContextTokens: 4096
        ),

        // MARK: TinyLlama (community, Apache 2.0)
        ModelEntry(
            id: "tinyllama-1.1b-chat-q4km",
            displayName: "TinyLlama 1.1B Chat",
            ollamaTag: "tinyllama:1.1b",
            publisher: "TinyLlama",
            summary: "Smallest Llama-architecture chat model. Useful as a speed baseline.",
            parametersBillion: 1.1,
            quantization: "Q4_K_M",
            sizeBytes: 668_788_096,
            estimatedRAMBytes: 858_993_459,
            downloadURL: URL(string: "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf")!,
            filename: "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
            chatTemplate: .zephyr,
            licenseLabel: "Apache 2.0",
            maxContextTokens: 2048,
            recommendedContextTokens: 2048
        )
    ]

    static func entry(id: String) -> ModelEntry? {
        all.first { $0.id == id }
    }

    /// Curated home-screen highlights, in display order.
    static let suggested: [String] = [
        "llama-3.2-3b-instruct-q4km",
        "llama-3.2-1b-instruct-q4km",
        "qwen-2.5-1.5b-instruct-q4km",
        "phi-4-mini-instruct-q4km",
        "gemma-3-1b-it-q4km",
        "smollm2-1.7b-instruct-q4km"
    ]

    static func suggestedEntries() -> [ModelEntry] {
        suggested.compactMap { entry(id: $0) }
    }
}
