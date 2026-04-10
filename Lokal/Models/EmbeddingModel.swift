//
//  EmbeddingModel.swift
//  Lokal
//
//  The single bundled embedding model used for all RAG knowledge bases.
//  EmbeddingGemma-300M is shipped inside the app bundle — no download
//  required. The struct is kept Codable because KnowledgeBase persists
//  the model ID to detect when re-indexing is needed after an upgrade.
//

import Foundation

struct EmbeddingModelEntry: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let displayName: String
    let publisher: String
    let summary: String
    let parametersBillion: Double
    let dimensions: Int
    let quantization: String
    let sizeBytes: Int64
    let estimatedRAMBytes: Int64
    let filename: String
    /// Some models require a task prefix in front of every input.
    let documentPrefix: String?
    let queryPrefix: String?
    let recommendedContextTokens: Int

    var sizeMB: Double { Double(sizeBytes) / 1_048_576.0 }
}

enum EmbeddingModelCatalog {
    static let bundled = EmbeddingModelEntry(
        id: "embeddinggemma-300m-q4_0",
        displayName: "EmbeddingGemma 300M",
        publisher: "Google",
        summary: "Multilingual sentence-embedding model. 768 dim, 100+ Sprachen, im App enthalten.",
        parametersBillion: 0.3,
        dimensions: 768,
        quantization: "Q4_0",
        sizeBytes: 277_852_192,
        estimatedRAMBytes: 200_000_000,
        filename: "embeddinggemma-300M-qat-Q4_0.gguf",
        documentPrefix: nil,
        queryPrefix: nil,
        recommendedContextTokens: 2048
    )

    /// Path to the GGUF inside the app bundle. `nil` only if the
    /// fetch script was not run before building.
    static var bundledModelPath: String? {
        Bundle.main.path(forResource: "embeddinggemma-300M-qat-Q4_0", ofType: "gguf")
    }

    // MARK: - Legacy compatibility shims

    static let all: [EmbeddingModelEntry] = [bundled]

    static func entry(id: String) -> EmbeddingModelEntry? {
        all.first { $0.id == id }
    }

    static var defaultEntry: EmbeddingModelEntry { bundled }
}
