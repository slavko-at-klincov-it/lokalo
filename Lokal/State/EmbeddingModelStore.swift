//
//  EmbeddingModelStore.swift
//  Lokal
//
//  Tracks which embedding GGUF files are installed and provides a shared
//  `LlamaEmbeddingEngine` instance on demand. Loads lazily, caches the most
//  recent engine, and lets callers explicitly tear it down to free RAM.
//

import Foundation
import Observation

@MainActor
@Observable
final class EmbeddingModelStore {

    private(set) var installedIDs: Set<String> = []
    var activeID: String?

    var activeEntry: EmbeddingModelEntry? {
        if let id = activeID { return EmbeddingModelCatalog.entry(id: id) }
        return EmbeddingModelCatalog.defaultEntry
    }

    var hasInstalled: Bool { !installedIDs.isEmpty }

    private var loadedEngine: LlamaEmbeddingEngine?
    private var loadedEngineEntryID: String?

    func bootstrap() {
        let dir = Self.modelsDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var found: Set<String> = []
        for entry in EmbeddingModelCatalog.all {
            let url = Self.fileURL(for: entry)
            if FileManager.default.fileExists(atPath: url.path) {
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                if size >= entry.sizeBytes / 2 { // accept partial-tolerance, exact size is from HF
                    found.insert(entry.id)
                }
            }
        }
        installedIDs = found
        if let saved = UserDefaults.standard.string(forKey: "Lokal.activeEmbeddingID"),
           found.contains(saved) {
            activeID = saved
        } else if let first = found.sorted().first {
            activeID = first
        }
    }

    func markInstalled(_ id: String) {
        installedIDs.insert(id)
        if activeID == nil {
            activeID = id
            UserDefaults.standard.set(id, forKey: "Lokal.activeEmbeddingID")
        }
    }

    func setActive(_ id: String) {
        guard installedIDs.contains(id) else { return }
        activeID = id
        UserDefaults.standard.set(id, forKey: "Lokal.activeEmbeddingID")
        // Drop any cached engine — it might belong to a different model.
        loadedEngine = nil
        loadedEngineEntryID = nil
    }

    func remove(_ id: String) {
        guard let entry = EmbeddingModelCatalog.entry(id: id) else { return }
        try? FileManager.default.removeItem(at: Self.fileURL(for: entry))
        installedIDs.remove(id)
        if loadedEngineEntryID == id {
            loadedEngine = nil
            loadedEngineEntryID = nil
        }
        if activeID == id {
            activeID = installedIDs.first
        }
    }

    /// Returns a (lazy-loaded, cached) embedding engine for the active model.
    /// The first call may take a few seconds; subsequent calls are instant.
    func ensureEngine() async throws -> LlamaEmbeddingEngine {
        guard let entry = activeEntry, installedIDs.contains(entry.id) else {
            throw EmbeddingError.notInstalled
        }
        if let engine = loadedEngine, loadedEngineEntryID == entry.id {
            return engine
        }
        let path = Self.fileURL(for: entry).path
        let ctx = entry.recommendedContextTokens
        let engine = try await Task.detached(priority: .userInitiated) {
            try LlamaEmbeddingEngine.load(path: path, contextTokens: ctx)
        }.value
        loadedEngine = engine
        loadedEngineEntryID = entry.id
        return engine
    }

    /// Free the engine and its model — callers should do this after large
    /// indexing batches when the chat LLM needs every byte of RAM.
    func unloadEngine() {
        loadedEngine = nil
        loadedEngineEntryID = nil
    }

    func isInstalled(_ id: String) -> Bool { installedIDs.contains(id) }

    enum EmbeddingError: LocalizedError {
        case notInstalled
        var errorDescription: String? {
            switch self {
            case .notInstalled: return "No embedding model installed"
            }
        }
    }

    // MARK: - Filesystem

    nonisolated static func modelsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("embeddings", isDirectory: true)
    }

    nonisolated static func fileURL(for entry: EmbeddingModelEntry) -> URL {
        modelsDirectory().appendingPathComponent(entry.filename)
    }

    nonisolated static func partialFileURL(for entry: EmbeddingModelEntry) -> URL {
        modelsDirectory().appendingPathComponent(entry.filename + ".partial")
    }
}
