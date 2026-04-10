//
//  EmbeddingModelStore.swift
//  Lokal
//
//  Provides a shared `LlamaEmbeddingEngine` backed by the bundled
//  EmbeddingGemma GGUF. The model is always available — no download
//  or install tracking needed. Loads lazily, caches the engine, and
//  lets callers explicitly tear it down to free RAM.
//

import Foundation
import Observation

@MainActor
@Observable
final class EmbeddingModelStore {

    let entry = EmbeddingModelCatalog.bundled

    var activeEntry: EmbeddingModelEntry? { entry }

    var hasInstalled: Bool { EmbeddingModelCatalog.bundledModelPath != nil }

    /// Hook so IndexingService can invalidate all cached stores when the
    /// embedding model changes (e.g. after an app update ships a new model).
    /// Wired in `LokalApp.task`.
    var onActiveModelChanged: (() -> Void)?

    private var loadedEngine: LlamaEmbeddingEngine?

    func bootstrap() {
        // Bundled model — nothing to scan. Clean up legacy UserDefaults key.
        UserDefaults.standard.removeObject(forKey: "Lokal.activeEmbeddingID")
    }

    /// Returns a (lazy-loaded, cached) embedding engine for the bundled model.
    /// The first call may take a few seconds; subsequent calls are instant.
    func ensureEngine() async throws -> LlamaEmbeddingEngine {
        if let engine = loadedEngine { return engine }
        guard let path = EmbeddingModelCatalog.bundledModelPath else {
            throw EmbeddingError.notInstalled
        }
        let ctx = entry.recommendedContextTokens
        let engine = try await Task.detached(priority: .userInitiated) {
            try LlamaEmbeddingEngine.load(path: path, contextTokens: ctx)
        }.value
        loadedEngine = engine
        return engine
    }

    /// Free the engine and its model — callers should do this after large
    /// indexing batches when the chat LLM needs every byte of RAM.
    func unloadEngine() {
        loadedEngine = nil
    }

    enum EmbeddingError: LocalizedError {
        case notInstalled
        var errorDescription: String? {
            switch self {
            case .notInstalled: return "Embedding-Modell nicht im App-Bundle gefunden."
            }
        }
    }

    // MARK: - Legacy cleanup

    /// Remove old downloaded embedding files from the Documents directory.
    func cleanupLegacyDownloads() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let oldDir = docs.appendingPathComponent("embeddings", isDirectory: true)
        try? FileManager.default.removeItem(at: oldDir)
    }
}
