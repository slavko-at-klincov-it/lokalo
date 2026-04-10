//
//  KnowledgeBaseStore.swift
//  Lokal
//
//  Top-level @Observable that owns all KnowledgeBase / KnowledgeSource state
//  and persists them to a JSON file in Application Support. The actual vector
//  index + chunk DB live next to this JSON, namespaced by KB id.
//

import Foundation
import Observation

@MainActor
@Observable
final class KnowledgeBaseStore {

    private(set) var bases: [KnowledgeBase] = []
    var activeBaseID: UUID?

    var activeBase: KnowledgeBase? {
        guard let id = activeBaseID else { return bases.first }
        return bases.first { $0.id == id } ?? bases.first
    }

    /// Whether RAG is currently enabled for new chat messages.
    var ragEnabled: Bool = true

    func bootstrap() {
        try? FileManager.default.createDirectory(at: Self.rootDirectory(), withIntermediateDirectories: true)
        load()
        if activeBaseID == nil {
            activeBaseID = bases.first?.id
        }
    }

    // MARK: - Mutations

    func createBaseIfNeeded(name: String,
                            embeddingModelID: String,
                            dimensions: Int) -> KnowledgeBase {
        if let existing = bases.first {
            return existing
        }
        let kb = KnowledgeBase(
            name: name,
            embeddingModelID: embeddingModelID,
            dimensions: dimensions
        )
        bases.append(kb)
        activeBaseID = kb.id
        try? persist()
        return kb
    }

    /// Migrate a knowledge base to a new embedding model. Resets all source
    /// statuses to `.idle` so they get re-indexed with the new model.
    func migrateEmbeddingModel(forBase baseID: UUID, modelID: String, dimensions: Int) {
        guard let i = bases.firstIndex(where: { $0.id == baseID }) else { return }
        bases[i].embeddingModelID = modelID
        bases[i].dimensions = dimensions
        for si in bases[i].sources.indices {
            bases[i].sources[si].status = .idle
            bases[i].sources[si].indexedChunks = 0
        }
        try? persist()
    }

    func add(source: KnowledgeSource, toBase baseID: UUID) {
        guard let i = bases.firstIndex(where: { $0.id == baseID }) else { return }
        bases[i].sources.append(source)
        try? persist()
    }

    func update(source: KnowledgeSource) {
        guard let bi = bases.firstIndex(where: { $0.sources.contains(where: { $0.id == source.id }) }),
              let si = bases[bi].sources.firstIndex(where: { $0.id == source.id })
        else { return }
        bases[bi].sources[si] = source
        try? persist()
    }

    /// Optional hook so the IndexingService can drop its cached
    /// VectorStore / ChunkStore for a removed source. Wired in
    /// `LokalApp.task` so this store doesn't need to know about
    /// IndexingService directly.
    var onSourceRemoved: ((UUID) -> Void)?

    /// Fires BEFORE the on-disk files are deleted, so a running indexing
    /// task can be cancelled before its target files disappear.
    var onSourceWillBeRemoved: ((UUID) -> Void)?

    func remove(source: KnowledgeSource) {
        // Cancel any active indexing for this source before touching files.
        onSourceWillBeRemoved?(source.id)
        for bi in bases.indices {
            bases[bi].sources.removeAll { $0.id == source.id }
        }
        // Best-effort cleanup of any on-disk artefacts.
        let idxURL = Self.indexFileURL(for: source.id)
        let dbURL  = Self.chunkDBFileURL(for: source.id)
        let mfURL  = Self.documentManifestURL(for: source.id)
        try? FileManager.default.removeItem(at: idxURL)
        try? FileManager.default.removeItem(at: dbURL)
        try? FileManager.default.removeItem(at: mfURL)
        try? persist()
        onSourceRemoved?(source.id)
    }

    func removeBase(_ id: UUID) {
        guard let kb = bases.first(where: { $0.id == id }) else { return }
        for src in kb.sources {
            onSourceWillBeRemoved?(src.id)
            try? FileManager.default.removeItem(at: Self.indexFileURL(for: src.id))
            try? FileManager.default.removeItem(at: Self.chunkDBFileURL(for: src.id))
            try? FileManager.default.removeItem(at: Self.documentManifestURL(for: src.id))
            onSourceRemoved?(src.id)
        }
        bases.removeAll { $0.id == id }
        if activeBaseID == id { activeBaseID = bases.first?.id }
        try? persist()
    }

    // MARK: - Persistence

    private static func rootDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("LokaloRAG", isDirectory: true)
    }

    private static func manifestURL() -> URL {
        rootDirectory().appendingPathComponent("knowledge-bases.json")
    }

    static func indexFileURL(for sourceID: UUID) -> URL {
        rootDirectory()
            .appendingPathComponent("indexes", isDirectory: true)
            .appendingPathComponent("\(sourceID.uuidString).usearch")
    }

    static func chunkDBFileURL(for sourceID: UUID) -> URL {
        rootDirectory()
            .appendingPathComponent("databases", isDirectory: true)
            .appendingPathComponent("\(sourceID.uuidString).sqlite")
    }

    static func documentManifestURL(for sourceID: UUID) -> URL {
        rootDirectory()
            .appendingPathComponent("manifests", isDirectory: true)
            .appendingPathComponent("\(sourceID.uuidString).json")
    }

    private struct Manifest: Codable {
        var bases: [KnowledgeBase]
        var activeBaseID: UUID?
        var ragEnabled: Bool
    }

    func persist() throws {
        let manifest = Manifest(bases: bases, activeBaseID: activeBaseID, ragEnabled: ragEnabled)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: Self.manifestURL(), options: [.atomic])
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.manifestURL()) else { return }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return }
        self.bases = manifest.bases
        self.activeBaseID = manifest.activeBaseID
        self.ragEnabled = manifest.ragEnabled
    }
}
