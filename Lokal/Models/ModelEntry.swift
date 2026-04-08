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
    /// Approximate total parameter count in billions ("3.21"). For MoE models
    /// this is the total weight count; use `activeParametersBillion` for the
    /// effective number of params per forward pass.
    let parametersBillion: Double
    /// Effective active parameters per token in billions. For dense models
    /// this equals `parametersBillion`. For MoE models it's the sum of the
    /// always-active params + activated experts × expert size. The 7 B
    /// phone-class cutoff applies to this number, not to `parametersBillion`.
    let activeParametersBillion: Double
    /// True for any model that runs entirely on-device. Online-only or
    /// gated-cloud entries (currently none in the catalog) must set this
    /// to false so the phone-compatible filter excludes them.
    let isLocalCapable: Bool
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

    init(
        id: String,
        displayName: String,
        ollamaTag: String?,
        publisher: String,
        summary: String,
        parametersBillion: Double,
        activeParametersBillion: Double? = nil,
        isLocalCapable: Bool = true,
        quantization: String,
        sizeBytes: Int64,
        estimatedRAMBytes: Int64,
        downloadURL: URL,
        filename: String,
        chatTemplate: ChatTemplate.Family,
        licenseLabel: String,
        maxContextTokens: Int,
        recommendedContextTokens: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.ollamaTag = ollamaTag
        self.publisher = publisher
        self.summary = summary
        self.parametersBillion = parametersBillion
        self.activeParametersBillion = activeParametersBillion ?? parametersBillion
        self.isLocalCapable = isLocalCapable
        self.quantization = quantization
        self.sizeBytes = sizeBytes
        self.estimatedRAMBytes = estimatedRAMBytes
        self.downloadURL = downloadURL
        self.filename = filename
        self.chatTemplate = chatTemplate
        self.licenseLabel = licenseLabel
        self.maxContextTokens = maxContextTokens
        self.recommendedContextTokens = recommendedContextTokens
    }

    var sizeGB: Double { Double(sizeBytes) / 1_073_741_824.0 }
    var ramGB: Double { Double(estimatedRAMBytes) / 1_073_741_824.0 }
    var parametersLabel: String {
        parametersBillion >= 1.0
            ? String(format: "%.1f B", parametersBillion)
            : String(format: "%.0f M", parametersBillion * 1000)
    }
    /// Label that exposes the effective param count when it differs from total.
    var effectiveParametersLabel: String {
        if abs(parametersBillion - activeParametersBillion) < 0.05 {
            return parametersLabel
        }
        let total = parametersBillion >= 1.0
            ? String(format: "%.1f B", parametersBillion)
            : String(format: "%.0f M", parametersBillion * 1000)
        let active = activeParametersBillion >= 1.0
            ? String(format: "%.1f B", activeParametersBillion)
            : String(format: "%.0f M", activeParametersBillion * 1000)
        return "\(active) aktiv · \(total) gesamt"
    }
}
