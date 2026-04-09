//
//  LicensesView.swift
//  Lokalo
//
//  Required by Llama Community License, Gemma Terms, etc.
//

import SwiftUI

private struct LicenseEntry: Identifiable {
    let id = UUID()
    let title: String
    let kind: String
    let summary: String
    let link: URL?
}

struct LicensesView: View {
    private let entries: [LicenseEntry] = [
        .init(title: "llama.cpp",
              kind: "MIT License",
              summary: "Inference engine. Copyright © 2023-2026 The ggml authors.",
              link: URL(string: "https://github.com/ggml-org/llama.cpp/blob/master/LICENSE")),
        .init(title: "Llama 3.2",
              kind: "Llama 3.2 Community License",
              summary: "Built with Llama. Copyright © Meta Platforms, Inc. Used under the Llama 3.2 Community License Agreement.",
              link: URL(string: "https://www.llama.com/llama3_2/license/")),
        .init(title: "Qwen",
              kind: "Apache 2.0",
              summary: "By Alibaba Cloud. All Qwen variants bundled in Lokalo are Apache 2.0 licensed for unrestricted commercial use.",
              link: URL(string: "https://huggingface.co/Qwen")),
        .init(title: "Gemma 2 / 3",
              kind: "Gemma Terms of Use",
              summary: "By Google. Used under Google's Gemma Terms of Use. Gemma is provided under and subject to the Gemma Terms of Use.",
              link: URL(string: "https://ai.google.dev/gemma/terms")),
        .init(title: "Phi-3.5 / Phi-4 Mini",
              kind: "MIT License",
              summary: "By Microsoft. Distributed under the MIT License.",
              link: URL(string: "https://huggingface.co/microsoft")),
        .init(title: "SmolLM2 / SmolLM3",
              kind: "Apache 2.0",
              summary: "By Hugging Face. Open dataset and weights, Apache 2.0.",
              link: URL(string: "https://huggingface.co/HuggingFaceTB")),
        .init(title: "TinyLlama",
              kind: "Apache 2.0",
              summary: "By the TinyLlama community.",
              link: URL(string: "https://github.com/jzhang38/TinyLlama")),
        .init(title: "GGUF Quantizations",
              kind: "Various",
              summary: "Quantized files mirrored by bartowski / unsloth / TheBloke / ggml-org on Hugging Face. Each preserves the original model's license.",
              link: URL(string: "https://huggingface.co/bartowski"))
    ]

    var body: some View {
        List(entries) { entry in
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(.headline)
                Text(entry.kind)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(entry.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let link = entry.link {
                    Link(destination: link) {
                        Text(link.absoluteString)
                            .font(.caption.monospaced())
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 6)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Lizenzen")
        .navigationBarTitleDisplayMode(.inline)
    }
}
