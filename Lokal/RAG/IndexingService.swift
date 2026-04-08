//
//  IndexingService.swift
//  Lokal
//
//  The pipeline that takes a KnowledgeSource (folder, repo, drive) and
//  walks every supported file → extracts text → chunks → embeds → writes
//  to the VectorStore + ChunkStore. Reports progress to the UI via @Observable.
//

import Foundation
import Observation

@MainActor
@Observable
final class IndexingService {

    struct Progress: Equatable {
        var sourceID: UUID
        var sourceName: String
        var totalFiles: Int
        var processedFiles: Int
        var indexedChunks: Int
        var status: String
    }

    var current: Progress?
    var lastError: String?

    private weak var kbStore: KnowledgeBaseStore?
    private weak var embeddingStore: EmbeddingModelStore?
    private weak var connectionStore: ConnectionStore?
    private var task: Task<Void, Never>?

    func attach(kbStore: KnowledgeBaseStore,
                embeddingStore: EmbeddingModelStore,
                connectionStore: ConnectionStore?) {
        self.kbStore = kbStore
        self.embeddingStore = embeddingStore
        self.connectionStore = connectionStore
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Index a single source from scratch (drops any previous chunks for it).
    func indexSource(_ source: KnowledgeSource, in baseID: UUID) {
        guard let kbStore, let embeddingStore else { return }
        guard let entry = embeddingStore.activeEntry,
              embeddingStore.isInstalled(entry.id) else {
            lastError = "Bitte zuerst ein Embedding-Modell laden."
            return
        }
        cancel()
        var working = source
        working.status = .indexing
        working.statusMessage = nil
        kbStore.update(source: working)

        current = Progress(
            sourceID: source.id,
            sourceName: source.displayName,
            totalFiles: 0,
            processedFiles: 0,
            indexedChunks: 0,
            status: "Vorbereitung…"
        )
        lastError = nil

        let connectionStore = self.connectionStore
        let kbStoreRef = kbStore
        let embeddingStoreRef = embeddingStore

        task = Task { [weak self] in
            do {
                // Resolve the file URLs that need to be processed.
                let urls: [URL]
                let scopedURL: URL?
                switch source.kind {
                case .localFolder:
                    let resolved = try Self.resolveFolderURL(from: source)
                    scopedURL = resolved
                    let started = resolved.startAccessingSecurityScopedResource()
                    defer {
                        if started { resolved.stopAccessingSecurityScopedResource() }
                    }
                    urls = Self.collectSupportedFiles(rootURL: resolved)
                    try await self?.runIndexingPipeline(
                        urls: urls,
                        rootURL: resolved,
                        source: source,
                        baseID: baseID,
                        entry: entry,
                        embeddingStore: embeddingStoreRef,
                        kbStore: kbStoreRef
                    )
                case .githubRepo, .googleDriveFolder, .onedriveFolder:
                    // Remote sources go through the connection-specific fetcher.
                    guard let connectionStore else {
                        await MainActor.run { self?.lastError = "Keine Verbindungen verfügbar." }
                        return
                    }
                    let temp = try Self.makeTempDirectory()
                    defer { try? FileManager.default.removeItem(at: temp) }
                    try await connectionStore.fetchAllFiles(
                        for: source,
                        into: temp
                    )
                    scopedURL = nil
                    urls = Self.collectSupportedFiles(rootURL: temp)
                    try await self?.runIndexingPipeline(
                        urls: urls,
                        rootURL: temp,
                        source: source,
                        baseID: baseID,
                        entry: entry,
                        embeddingStore: embeddingStoreRef,
                        kbStore: kbStoreRef
                    )
                }
                _ = scopedURL
            } catch {
                await MainActor.run {
                    self?.lastError = error.lokaloMessage
                    var failed = source
                    failed.status = .error
                    failed.statusMessage = error.lokaloMessage
                    self?.kbStore?.update(source: failed)
                    self?.current = nil
                }
            }
        }
    }

    private func runIndexingPipeline(urls: [URL],
                                     rootURL: URL,
                                     source: KnowledgeSource,
                                     baseID: UUID,
                                     entry: EmbeddingModelEntry,
                                     embeddingStore: EmbeddingModelStore,
                                     kbStore: KnowledgeBaseStore) async throws {
        await MainActor.run {
            self.current?.totalFiles = urls.count
            self.current?.status = "Indiziere \(urls.count) Dateien…"
        }

        // Reset the existing index and metadata for this source.
        let chunkStore = try ChunkStore(url: KnowledgeBaseStore.chunkDBFileURL(for: source.id))
        _ = try chunkStore.deleteAll(forSource: source.id)
        try? FileManager.default.removeItem(at: KnowledgeBaseStore.indexFileURL(for: source.id))
        let vectorStore = try VectorStore(
            dimensions: entry.dimensions,
            storeURL: KnowledgeBaseStore.indexFileURL(for: source.id)
        )

        let embedder = try await embeddingStore.ensureEngine()

        var processed = 0
        var totalChunks = 0
        var indexedDocuments = 0

        for url in urls {
            if Task.isCancelled { break }
            do {
                let doc = try DocumentExtractor.extract(from: url)
                if doc.isEmpty {
                    processed += 1
                    await MainActor.run { self.current?.processedFiles = processed }
                    continue
                }
                let chunks = Chunker.chunk(doc, targetTokens: 384, overlapTokens: 64)
                for chunk in chunks {
                    if Task.isCancelled { break }
                    let textWithPrefix = (entry.documentPrefix ?? "") + chunk.text
                    let vec = try await embedder.embed(textWithPrefix)
                    let key = UInt64.random(in: 1...UInt64.max)
                    try await vectorStore.upsert(key: key, embedding: vec)
                    try chunkStore.insert(
                        key: key,
                        sourceID: source.id,
                        documentPath: url.path,
                        documentName: url.lastPathComponent,
                        pageIndex: chunk.pageIndex,
                        charStart: chunk.charStart,
                        charEnd: chunk.charEnd,
                        text: chunk.text
                    )
                    totalChunks += 1
                }
                indexedDocuments += 1
            } catch {
                // Skip individual file errors; keep indexing.
                #if DEBUG
                print("Index error for \(url.lastPathComponent): \(error.lokaloMessage)")
                #endif
            }
            processed += 1
            let snapshotProcessed = processed
            let snapshotChunks = totalChunks
            await MainActor.run {
                self.current?.processedFiles = snapshotProcessed
                self.current?.indexedChunks = snapshotChunks
            }
        }

        try await vectorStore.persist()

        var done = source
        done.status = Task.isCancelled ? .idle : .ready
        done.lastIndexedAt = .now
        done.indexedDocuments = indexedDocuments
        done.indexedChunks = totalChunks
        done.statusMessage = nil
        await MainActor.run {
            kbStore.update(source: done)
            self.current = nil
        }
    }

    /// Run a query against an active KnowledgeBase and return the top-K hits.
    func query(_ text: String, baseID: UUID, topK: Int = 5) async throws -> [RetrievalHit] {
        guard let kbStore = self.kbStore,
              let embeddingStore = self.embeddingStore,
              let kb = kbStore.bases.first(where: { $0.id == baseID }) else {
            return []
        }
        guard let entry = embeddingStore.activeEntry,
              embeddingStore.isInstalled(entry.id) else { return [] }

        let embedder = try await embeddingStore.ensureEngine()
        let queryText = (entry.queryPrefix ?? "") + text
        let queryVec = try await embedder.embed(queryText)

        var allHits: [RetrievalHit] = []
        for source in kb.sources where source.status == .ready {
            do {
                let store = try await VectorStore(
                    dimensions: entry.dimensions,
                    storeURL: KnowledgeBaseStore.indexFileURL(for: source.id)
                )
                let raw = try await store.search(query: queryVec, topK: topK)
                let chunkStore = try ChunkStore(url: KnowledgeBaseStore.chunkDBFileURL(for: source.id))
                let chunks = try chunkStore.chunks(for: raw.map { $0.key })
                let chunkByKey = Dictionary(uniqueKeysWithValues: chunks.map { ($0.key, $0) })
                for hit in raw {
                    if let chunk = chunkByKey[hit.key] {
                        allHits.append(RetrievalHit(chunk: chunk, distance: hit.distance))
                    }
                }
            } catch {
                #if DEBUG
                print("Query error for source \(source.id): \(error.lokaloMessage)")
                #endif
            }
        }

        // Sort by distance ascending (lower = closer in cosine).
        return allHits.sorted { $0.distance < $1.distance }.prefix(topK).map { $0 }
    }

    // MARK: - Helpers

    static func resolveFolderURL(from source: KnowledgeSource) throws -> URL {
        guard let bookmark = source.bookmark else {
            throw NSError(domain: "Indexing", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Quelle hat kein Bookmark"])
        }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark,
                          options: [],
                          relativeTo: nil,
                          bookmarkDataIsStale: &stale)
        return url
    }

    static func collectSupportedFiles(rootURL: URL) -> [URL] {
        var out: [URL] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: rootURL,
                                             includingPropertiesForKeys: keys,
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return []
        }
        while let item = enumerator.nextObject() as? URL {
            let res = try? item.resourceValues(forKeys: Set(keys))
            guard res?.isRegularFile == true else { continue }
            if let size = res?.fileSize, size > 25_000_000 { continue } // skip > 25 MB
            if DocumentExtractor.canExtract(url: item) {
                out.append(item)
            }
        }
        return out
    }

    static func makeTempDirectory() throws -> URL {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("LokaloIndex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        return temp
    }
}
