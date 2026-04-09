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
    /// Typed license. Decoded from the `licenseLabel` string in `models.json`
    /// via `ModelLicense.init(rawLabel:)`. Drives the commercial-use filter
    /// in `ModelCatalog.phoneCompatible` — entries whose license does not
    /// permit App Store distribution are silently excluded from the catalog.
    let license: ModelLicense
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
        license: ModelLicense,
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
        self.license = license
        self.maxContextTokens = maxContextTokens
        self.recommendedContextTokens = recommendedContextTokens
    }

    // MARK: - Codable
    //
    // Custom decoding so the bundled `models.json` can omit
    // `activeParametersBillion` (defaults to `parametersBillion`) and
    // `isLocalCapable` (defaults to `true`). This keeps the JSON terse
    // for the common case (a dense, on-device model) and only forces
    // those fields when they actually differ.

    private enum CodingKeys: String, CodingKey {
        case id, displayName, ollamaTag, publisher, summary
        case parametersBillion, activeParametersBillion, isLocalCapable
        case quantization, sizeBytes, estimatedRAMBytes
        case downloadURL, filename, chatTemplate
        // The Swift property is `license` (typed) but the JSON key is
        // `licenseLabel` (string) for backwards compatibility with the
        // existing models.json schema. ModelLicense's own Codable
        // conformance handles the string ↔ enum round-trip.
        case license = "licenseLabel"
        case maxContextTokens, recommendedContextTokens
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.ollamaTag = try c.decodeIfPresent(String.self, forKey: .ollamaTag)
        self.publisher = try c.decode(String.self, forKey: .publisher)
        self.summary = try c.decode(String.self, forKey: .summary)
        self.parametersBillion = try c.decode(Double.self, forKey: .parametersBillion)
        self.activeParametersBillion = try c.decodeIfPresent(Double.self, forKey: .activeParametersBillion)
            ?? self.parametersBillion
        self.isLocalCapable = try c.decodeIfPresent(Bool.self, forKey: .isLocalCapable) ?? true
        self.quantization = try c.decode(String.self, forKey: .quantization)
        self.sizeBytes = try c.decode(Int64.self, forKey: .sizeBytes)
        self.estimatedRAMBytes = try c.decode(Int64.self, forKey: .estimatedRAMBytes)
        self.downloadURL = try c.decode(URL.self, forKey: .downloadURL)
        self.filename = try c.decode(String.self, forKey: .filename)
        self.chatTemplate = try c.decode(ChatTemplate.Family.self, forKey: .chatTemplate)
        // ModelLicense's own decoder reads a single string from the JSON
        // and runs it through `init(rawLabel:)`, so unknown labels fall
        // through to `.other(raw)` instead of failing the whole catalog
        // decode. The conservative-default rule then keeps them out of
        // the user-facing catalog at filter time.
        self.license = try c.decode(ModelLicense.self, forKey: .license)
        self.maxContextTokens = try c.decode(Int.self, forKey: .maxContextTokens)
        self.recommendedContextTokens = try c.decode(Int.self, forKey: .recommendedContextTokens)
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
