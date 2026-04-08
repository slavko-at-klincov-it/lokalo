//
//  EmbeddingModel.swift
//  Lokal
//
//  Catalog of GGUF embedding models that can be used for the RAG knowledge base.
//  These are kept separate from `ModelCatalog` (which holds chat models) so that
//  embedding-specific fields (dimensions, prefix conventions) live where they
//  belong.
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
    let downloadURL: URL
    let filename: String
    /// Some models (nomic-embed) require a task prefix in front of every input.
    let documentPrefix: String?
    let queryPrefix: String?
    let recommendedContextTokens: Int

    var sizeMB: Double { Double(sizeBytes) / 1_048_576.0 }
}

enum EmbeddingModelCatalog {
    static let all: [EmbeddingModelEntry] = [
        EmbeddingModelEntry(
            id: "nomic-embed-text-v1.5-q4km",
            displayName: "Nomic Embed v1.5",
            publisher: "Nomic AI",
            summary: "Multilingual sentence-embedding model. 768-dim, optimized for retrieval.",
            parametersBillion: 0.137,
            dimensions: 768,
            quantization: "Q4_K_M",
            sizeBytes: 84_106_240,
            estimatedRAMBytes: 250_000_000,
            downloadURL: URL(string: "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q4_K_M.gguf")!,
            filename: "nomic-embed-text-v1.5.Q4_K_M.gguf",
            documentPrefix: "search_document: ",
            queryPrefix: "search_query: ",
            recommendedContextTokens: 2048
        )
    ]

    static func entry(id: String) -> EmbeddingModelEntry? {
        all.first { $0.id == id }
    }

    static var defaultEntry: EmbeddingModelEntry { all[0] }
}
