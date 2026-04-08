//
//  ModelEntry.swift
//  Lokal
//

import Foundation

/// Static description of a downloadable model in the catalog.
struct ModelEntry: Identifiable, Hashable, Codable, Sendable {
    /// Stable identifier (used as filename stem and dictionary key).
    let id: String
    /// Pretty display name shown in the UI ("Llama 3.2 3B Instruct").
    let displayName: String
    /// Short Ollama-style tag ("llama3.2:3b").
    let ollamaTag: String?
    /// Family / publisher ("Meta", "Microsoft", "Google", "Alibaba", "HuggingFace").
    let publisher: String
    /// One-line description shown on the detail screen.
    let summary: String
    /// Approximate parameter count in billions ("3.21").
    let parametersBillion: Double
    /// Quantization label ("Q4_K_M").
    let quantization: String
    /// File size on disk in bytes (matches Content-Length on the HF CDN).
    let sizeBytes: Int64
    /// Estimated peak inference RAM in bytes.
    let estimatedRAMBytes: Int64
    /// HuggingFace download URL (resolve/main form).
    let downloadURL: URL
    /// Filename used on disk inside the app sandbox.
    let filename: String
    /// Chat template family name.
    let chatTemplate: ChatTemplate.Family
    /// License short label.
    let licenseLabel: String
    /// Maximum context window the model supports (informational).
    let maxContextTokens: Int
    /// Default context window the engine should use on phone.
    let recommendedContextTokens: Int

    var sizeGB: Double { Double(sizeBytes) / 1_073_741_824.0 }
    var ramGB: Double { Double(estimatedRAMBytes) / 1_073_741_824.0 }
    var parametersLabel: String {
        parametersBillion >= 1.0
            ? String(format: "%.1f B", parametersBillion)
            : String(format: "%.0f M", parametersBillion * 1000)
    }
}
