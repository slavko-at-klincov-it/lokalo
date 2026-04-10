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
        var skippedFiles: [String] = []
        var failedFiles: [String] = []
    }

    var current: Progress?
    var lastError: String?

    private let kbStore: KnowledgeBaseStore
    private let embeddingStore: EmbeddingModelStore
    private let connectionStore: ConnectionStore
    private var task: Task<Void, Never>?
    private var indexingSourceID: UUID?
    private var syncTimer: Task<Void, Never>?

    /// Per-source cache of loaded VectorStore + ChunkStore so that
    /// `query()` doesn't reload the USearch index and reopen the SQLite
    /// database from disk on every single call. Indexed by source ID.
    /// Invalidated whenever a source is re-indexed or removed.
    private struct LoadedStore {
        let vectorStore: VectorStore
        let chunkStore: ChunkStore
    }
    private var loadedStores: [UUID: LoadedStore] = [:]

    init(kbStore: KnowledgeBaseStore,
         embeddingStore: EmbeddingModelStore,
         connectionStore: ConnectionStore) {
        self.kbStore = kbStore
        self.embeddingStore = embeddingStore
        self.connectionStore = connectionStore
        // Drop cached VectorStore/ChunkStore for any source the user
        // removes, so the next query reloads a fresh copy.
        kbStore.onSourceRemoved = { [weak self] sourceID in
            Task { @MainActor in self?.invalidateCache(for: sourceID) }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        indexingSourceID = nil
    }

    /// Cancel the active indexing task only if it targets the given source.
    func cancelIfIndexing(sourceID: UUID) {
        if indexingSourceID == sourceID {
            cancel()
        }
    }

    /// Drop the cached stores for a given source. Call after re-indexing,
    /// removing, or otherwise mutating the on-disk state for that source.
    func invalidateCache(for sourceID: UUID) {
        loadedStores.removeValue(forKey: sourceID)
    }

    /// Drop every cached store. Call when an entire knowledge base is
    /// removed or when the embedding model changes (different dimensions
    /// invalidate every existing index).
    func invalidateAllCaches() {
        loadedStores.removeAll()
    }

    /// Index a source. Automatically picks incremental mode when a valid
    /// manifest exists and the embedding model hasn't changed; otherwise
    /// falls back to a full re-index.
    func indexSource(_ source: KnowledgeSource, in baseID: UUID, forceFullReindex: Bool = false) {
        guard let entry = embeddingStore.activeEntry else {
            lastError = "Kein Embedding-Modell verfügbar."
            return
        }
        cancel()
        // Re-indexing invalidates the on-disk USearch index for this
        // source, so any cached store is now stale.
        invalidateCache(for: source.id)
        indexingSourceID = source.id
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

        let connectionStoreRef = self.connectionStore
        let kbStoreRef = kbStore
        let embeddingStoreRef = embeddingStore

        let forceFullReindex = forceFullReindex
        task = Task { [weak self] in
            do {
                // Check for existing manifest to decide full vs incremental.
                let manifestURL = KnowledgeBaseStore.documentManifestURL(for: source.id)
                let existingManifest = DocumentManifest.load(from: manifestURL)
                let canIncremental = !forceFullReindex
                    && existingManifest != nil
                    && existingManifest?.embeddingModelID == entry.id

                // Resolve the file URLs that need to be processed.
                let scopedURL: URL?
                switch source.kind {
                case .localFolder:
                    let resolved = try Self.resolveFolderURL(from: source)
                    scopedURL = resolved
                    let started = resolved.startAccessingSecurityScopedResource()
                    defer {
                        if started { resolved.stopAccessingSecurityScopedResource() }
                    }
                    let collected = Self.collectSupportedFiles(rootURL: resolved)
                    if canIncremental, let manifest = existingManifest {
                        try await self?.runIncrementalPipeline(
                            urls: collected.accepted,
                            skippedFiles: collected.skipped,
                            rootURL: resolved,
                            source: source,
                            baseID: baseID,
                            entry: entry,
                            manifest: manifest,
                            embeddingStore: embeddingStoreRef,
                            kbStore: kbStoreRef
                        )
                    } else {
                        try await self?.runIndexingPipeline(
                            urls: collected.accepted,
                            skippedFiles: collected.skipped,
                            rootURL: resolved,
                            source: source,
                            baseID: baseID,
                            entry: entry,
                            embeddingStore: embeddingStoreRef,
                            kbStore: kbStoreRef
                        )
                    }
                case .githubRepo, .googleDriveFolder, .onedriveFolder:
                    let temp = try Self.makeTempDirectory()
                    defer { try? FileManager.default.removeItem(at: temp) }
                    try await connectionStoreRef.fetchAllFiles(
                        for: source,
                        into: temp
                    )
                    scopedURL = nil
                    let collected = Self.collectSupportedFiles(rootURL: temp)
                    if canIncremental, let manifest = existingManifest {
                        try await self?.runIncrementalPipeline(
                            urls: collected.accepted,
                            skippedFiles: collected.skipped,
                            rootURL: temp,
                            source: source,
                            baseID: baseID,
                            entry: entry,
                            manifest: manifest,
                            embeddingStore: embeddingStoreRef,
                            kbStore: kbStoreRef
                        )
                    } else {
                        try await self?.runIndexingPipeline(
                            urls: collected.accepted,
                            skippedFiles: collected.skipped,
                            rootURL: temp,
                            source: source,
                            baseID: baseID,
                            entry: entry,
                            embeddingStore: embeddingStoreRef,
                            kbStore: kbStoreRef
                        )
                    }
                }
                _ = scopedURL
            } catch {
                await MainActor.run {
                    self?.lastError = error.lokaloMessage
                    var failed = source
                    failed.status = .error
                    failed.statusMessage = error.lokaloMessage
                    self?.kbStore.update(source: failed)
                    self?.current = nil
                    self?.indexingSourceID = nil
                }
            }

            // Free the embedding engine after every indexing run so the
            // chat LLM has the full RAM budget.
            await MainActor.run {
                embeddingStoreRef.unloadEngine()
            }
        }
    }

    // MARK: - Full Re-Index Pipeline

    private func runIndexingPipeline(urls: [URL],
                                     skippedFiles: [String],
                                     rootURL: URL,
                                     source: KnowledgeSource,
                                     baseID: UUID,
                                     entry: EmbeddingModelEntry,
                                     embeddingStore: EmbeddingModelStore,
                                     kbStore: KnowledgeBaseStore) async throws {
        await MainActor.run {
            self.current?.totalFiles = urls.count
            self.current?.skippedFiles = skippedFiles
            self.current?.status = "Indiziere \(urls.count) Dateien…"
        }

        // Atomic re-indexing: write to a staging directory first, then
        // swap into the final location only on success.
        let stagingDir = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        let stagingIndexURL = stagingDir.appendingPathComponent("index.usearch")
        let stagingChunkURL = stagingDir.appendingPathComponent("chunks.sqlite")

        let chunkStore = try ChunkStore(url: stagingChunkURL)
        let vectorStore = try await VectorStore(
            dimensions: entry.dimensions,
            storeURL: stagingIndexURL
        )

        let embedder = try await embeddingStore.ensureEngine()

        var processed = 0
        var totalChunks = 0
        var indexedDocuments = 0
        var failedFiles: [String] = []
        var manifestRecords: [String: DocumentRecord] = [:]

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
                let relativePath = Self.relativePath(of: url, to: rootURL)
                let hash = (try? FileHasher.sha256Hex(of: url)) ?? UUID().uuidString
                let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now

                var documentChunks: [(key: UInt64, sourceID: UUID, documentPath: String,
                                      documentName: String, pageIndex: Int?,
                                      charStart: Int, charEnd: Int, text: String)] = []
                var chunkKeys: [UInt64] = []
                for chunk in chunks {
                    if Task.isCancelled { break }
                    let textWithPrefix = (entry.documentPrefix ?? "") + chunk.text
                    let vec = try await embedder.embed(textWithPrefix)
                    let key = UInt64.random(in: 1...UInt64.max)
                    try await vectorStore.upsert(key: key, embedding: vec)
                    documentChunks.append((key, source.id, url.path, url.lastPathComponent,
                                           chunk.pageIndex, chunk.charStart, chunk.charEnd, chunk.text))
                    chunkKeys.append(key)
                    totalChunks += 1
                }
                try await chunkStore.insertBatch(documentChunks)
                manifestRecords[relativePath] = DocumentRecord(
                    relativePath: relativePath, sha256: hash,
                    modifiedAt: modDate, chunkKeys: chunkKeys
                )
                indexedDocuments += 1
            } catch {
                failedFiles.append(url.lastPathComponent)
                #if DEBUG
                print("Index error for \(url.lastPathComponent): \(error.lokaloMessage)")
                #endif
            }
            processed += 1
            let snapshotProcessed = processed
            let snapshotChunks = totalChunks
            let snapshotFailed = failedFiles
            await MainActor.run {
                self.current?.processedFiles = snapshotProcessed
                self.current?.indexedChunks = snapshotChunks
                self.current?.failedFiles = snapshotFailed
            }
        }

        guard !Task.isCancelled else { return }

        try await vectorStore.persist()

        // Atomic swap: move staging files into final location.
        let finalIndexURL = KnowledgeBaseStore.indexFileURL(for: source.id)
        let finalChunkURL = KnowledgeBaseStore.chunkDBFileURL(for: source.id)
        try FileManager.default.createDirectory(
            at: finalIndexURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: finalChunkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: finalIndexURL)
        try? FileManager.default.removeItem(at: finalChunkURL)
        try FileManager.default.moveItem(at: stagingIndexURL, to: finalIndexURL)
        try FileManager.default.moveItem(at: stagingChunkURL, to: finalChunkURL)

        // Save the document manifest for future incremental runs.
        let manifest = DocumentManifest(
            sourceID: source.id,
            records: manifestRecords,
            embeddingModelID: entry.id,
            indexedAt: .now
        )
        try? manifest.save(to: KnowledgeBaseStore.documentManifestURL(for: source.id))

        var done = source
        done.status = .ready
        done.lastIndexedAt = .now
        done.indexedDocuments = indexedDocuments
        done.indexedChunks = totalChunks
        done.statusMessage = nil
        await MainActor.run {
            kbStore.update(source: done)
            self.current = nil
            self.indexingSourceID = nil
        }
    }

    // MARK: - Incremental Pipeline

    private func runIncrementalPipeline(urls: [URL],
                                        skippedFiles: [String],
                                        rootURL: URL,
                                        source: KnowledgeSource,
                                        baseID: UUID,
                                        entry: EmbeddingModelEntry,
                                        manifest: DocumentManifest,
                                        embeddingStore: EmbeddingModelStore,
                                        kbStore: KnowledgeBaseStore) async throws {
        // Build a lookup of current files by relative path.
        var currentFiles: [String: URL] = [:]
        for url in urls {
            currentFiles[Self.relativePath(of: url, to: rootURL)] = url
        }

        // Classify files into: unchanged, changed/new, deleted.
        var toIndex: [(url: URL, relativePath: String)] = []
        var toRemoveKeys: [UInt64] = []
        var unchangedCount = 0

        for (relPath, record) in manifest.records {
            if currentFiles[relPath] == nil {
                // File was deleted — remove its chunks.
                toRemoveKeys.append(contentsOf: record.chunkKeys)
            }
        }

        for (relPath, url) in currentFiles {
            if let existing = manifest.records[relPath] {
                let hash = (try? FileHasher.sha256Hex(of: url)) ?? ""
                if hash == existing.sha256 {
                    unchangedCount += 1
                } else {
                    // File changed — remove old chunks, re-index.
                    toRemoveKeys.append(contentsOf: existing.chunkKeys)
                    toIndex.append((url, relPath))
                }
            } else {
                // New file.
                toIndex.append((url, relPath))
            }
        }

        let totalWork = toIndex.count
        let deletedDocs = manifest.records.keys.filter { currentFiles[$0] == nil }.count

        await MainActor.run {
            self.current?.totalFiles = totalWork
            self.current?.skippedFiles = skippedFiles
            self.current?.status = "\(unchangedCount) unverändert, \(totalWork) zu aktualisieren, \(deletedDocs) gelöscht"
        }

        // If nothing changed, just update the timestamp and return.
        if toIndex.isEmpty && toRemoveKeys.isEmpty {
            var done = source
            done.status = .ready
            done.lastIndexedAt = .now
            done.statusMessage = nil
            await MainActor.run {
                kbStore.update(source: done)
                self.current = nil
                self.indexingSourceID = nil
            }
            return
        }

        // Load existing stores for in-place modification.
        let indexURL = KnowledgeBaseStore.indexFileURL(for: source.id)
        let chunkURL = KnowledgeBaseStore.chunkDBFileURL(for: source.id)
        let vectorStore = try await VectorStore(dimensions: entry.dimensions, storeURL: indexURL)
        let chunkStore = try ChunkStore(url: chunkURL)

        let embedder = try await embeddingStore.ensureEngine()

        // Build updated manifest starting from unchanged records.
        var updatedRecords = manifest.records
        // Remove deleted files from manifest.
        for relPath in manifest.records.keys where currentFiles[relPath] == nil {
            updatedRecords.removeValue(forKey: relPath)
        }

        // Phase 1: Insert new/changed chunks FIRST. If the app crashes
        // here, we end up with duplicates (old + new) rather than data
        // loss. Duplicates are harmless — the next incremental run will
        // detect the stale manifest and clean up.
        var processed = 0
        var newChunks = 0
        var failedFiles: [String] = []

        for (url, relPath) in toIndex {
            if Task.isCancelled { break }
            do {
                let doc = try DocumentExtractor.extract(from: url)
                if doc.isEmpty {
                    processed += 1
                    await MainActor.run { self.current?.processedFiles = processed }
                    continue
                }
                let chunks = Chunker.chunk(doc, targetTokens: 384, overlapTokens: 64)
                let hash = (try? FileHasher.sha256Hex(of: url)) ?? UUID().uuidString
                let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now

                var documentChunks: [(key: UInt64, sourceID: UUID, documentPath: String,
                                      documentName: String, pageIndex: Int?,
                                      charStart: Int, charEnd: Int, text: String)] = []
                var chunkKeys: [UInt64] = []
                for chunk in chunks {
                    if Task.isCancelled { break }
                    let textWithPrefix = (entry.documentPrefix ?? "") + chunk.text
                    let vec = try await embedder.embed(textWithPrefix)
                    let key = UInt64.random(in: 1...UInt64.max)
                    try await vectorStore.upsert(key: key, embedding: vec)
                    documentChunks.append((key, source.id, url.path, url.lastPathComponent,
                                           chunk.pageIndex, chunk.charStart, chunk.charEnd, chunk.text))
                    chunkKeys.append(key)
                    newChunks += 1
                }
                try await chunkStore.insertBatch(documentChunks)
                updatedRecords[relPath] = DocumentRecord(
                    relativePath: relPath, sha256: hash,
                    modifiedAt: modDate, chunkKeys: chunkKeys
                )
            } catch {
                failedFiles.append(url.lastPathComponent)
                #if DEBUG
                print("Incremental index error for \(url.lastPathComponent): \(error.lokaloMessage)")
                #endif
            }
            processed += 1
            let snapshotProcessed = processed
            let snapshotChunks = newChunks
            let snapshotFailed = failedFiles
            await MainActor.run {
                self.current?.processedFiles = snapshotProcessed
                self.current?.indexedChunks = snapshotChunks
                self.current?.failedFiles = snapshotFailed
            }
        }

        guard !Task.isCancelled else { return }

        // Phase 2: Now remove old keys for changed/deleted files.
        // New chunks are already safely persisted above.
        for key in toRemoveKeys {
            await vectorStore.remove(key: key)
        }
        if !toRemoveKeys.isEmpty {
            try await chunkStore.deleteKeys(toRemoveKeys)
        }

        try await vectorStore.persist()

        // Save manifest. If crash happens between persist() and here,
        // the manifest is stale — but queries still work, and the next
        // incremental run detects the mismatch via hash comparison and
        // triggers a full re-index.
        let updatedManifest = DocumentManifest(
            sourceID: source.id,
            records: updatedRecords,
            embeddingModelID: entry.id,
            indexedAt: .now
        )
        try? updatedManifest.save(to: KnowledgeBaseStore.documentManifestURL(for: source.id))

        // Invalidate cached stores so queries reload the updated index.
        await MainActor.run { [source] in
            self.invalidateCache(for: source.id)
        }

        let totalDocs = updatedRecords.count
        let totalChunksCount = updatedRecords.values.reduce(0) { $0 + $1.chunkKeys.count }
        var done = source
        done.status = .ready
        done.lastIndexedAt = .now
        done.indexedDocuments = totalDocs
        done.indexedChunks = totalChunksCount
        done.statusMessage = nil
        await MainActor.run {
            kbStore.update(source: done)
            self.current = nil
            self.indexingSourceID = nil
        }
    }

    // MARK: - Auto-Index Staleness Check

    /// Check all sources in the active KB and index the first stale one.
    /// Local sources are considered stale after 5 minutes, cloud sources
    /// after 30 minutes. Called on app foreground resume.
    func checkStaleSources() {
        guard current == nil else { return }
        guard let kb = kbStore.activeBase else { return }
        for source in kb.sources where source.status == .ready {
            guard let lastIndexed = source.lastIndexedAt else { continue }
            let staleness: TimeInterval = source.kind == .localFolder ? 5 * 60 : 30 * 60
            if Date.now.timeIntervalSince(lastIndexed) > staleness {
                indexSource(source, in: kb.id)
                return
            }
        }
    }

    // MARK: - Periodic Cloud Sync

    /// Start a repeating timer that syncs cloud sources every `interval`
    /// seconds while the app is in the foreground. Only processes one
    /// stale cloud source per tick to avoid network storms.
    func startPeriodicCloudSync(interval: TimeInterval = 15 * 60) {
        stopPeriodicCloudSync()
        syncTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self?.syncNextStaleCloudSource()
            }
        }
    }

    func stopPeriodicCloudSync() {
        syncTimer?.cancel()
        syncTimer = nil
    }

    private func syncNextStaleCloudSource() {
        guard current == nil else { return }
        guard let kb = kbStore.activeBase else { return }
        let cloudKinds: Set<KnowledgeSourceKind> = [.githubRepo, .googleDriveFolder, .onedriveFolder]
        for source in kb.sources where source.status == .ready && cloudKinds.contains(source.kind) {
            guard let lastIndexed = source.lastIndexedAt else { continue }
            if Date.now.timeIntervalSince(lastIndexed) > 30 * 60 {
                indexSource(source, in: kb.id)
                return
            }
        }
    }

    /// Run a query against an active KnowledgeBase and return the top-K hits.
    /// Loads each source's USearch index + ChunkStore lazily and caches them
    /// for the rest of the session, so subsequent queries (and chat tool-call
    /// loops) hit memory instead of disk.
    func query(_ text: String, baseID: UUID, topK: Int = 5, maxDistance: Float = 0.45) async throws -> [RetrievalHit] {
        guard let kb = kbStore.bases.first(where: { $0.id == baseID }) else {
            return []
        }
        guard let entry = embeddingStore.activeEntry else { return [] }

        let embedder = try await embeddingStore.ensureEngine()
        let queryText = (entry.queryPrefix ?? "") + text
        let queryVec = try await embedder.embed(queryText)

        var allHits: [RetrievalHit] = []
        for source in kb.sources where source.status == .ready {
            do {
                let loaded = try await loadedStore(for: source, dimensions: entry.dimensions)
                let raw = try await loaded.vectorStore.search(query: queryVec, topK: topK)
                let chunks = try await loaded.chunkStore.chunks(for: raw.map { $0.key })
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
                // If a cached store is broken, drop it so the next query
                // tries to reload from disk instead of returning the same
                // bad cache forever.
                invalidateCache(for: source.id)
            }
        }

        // Sort by distance ascending (lower = closer in cosine), filter
        // out results beyond the relevance threshold, then take top-K.
        return allHits
            .sorted { $0.distance < $1.distance }
            .filter { $0.distance <= maxDistance }
            .prefix(topK)
            .map { $0 }
    }

    /// Get or build the cached `(VectorStore, ChunkStore)` pair for a source.
    /// The actual disk loading happens off-actor via `Task.detached` so the
    /// main actor doesn't block on USearch / SQLite I/O.
    private func loadedStore(for source: KnowledgeSource, dimensions: Int) async throws -> LoadedStore {
        if let cached = loadedStores[source.id] {
            return cached
        }
        let indexURL = KnowledgeBaseStore.indexFileURL(for: source.id)
        let chunkURL = KnowledgeBaseStore.chunkDBFileURL(for: source.id)
        let loaded = try await Task.detached(priority: .userInitiated) { () -> LoadedStore in
            let vectorStore = try await VectorStore(dimensions: dimensions, storeURL: indexURL)
            let chunkStore  = try ChunkStore(url: chunkURL)
            return LoadedStore(vectorStore: vectorStore, chunkStore: chunkStore)
        }.value
        loadedStores[source.id] = loaded
        return loaded
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

    static func collectSupportedFiles(rootURL: URL) -> (accepted: [URL], skipped: [String]) {
        var out: [URL] = []
        var skipped: [String] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: rootURL,
                                             includingPropertiesForKeys: keys,
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return ([], [])
        }
        while let item = enumerator.nextObject() as? URL {
            let res = try? item.resourceValues(forKeys: Set(keys))
            guard res?.isRegularFile == true else { continue }
            if let size = res?.fileSize, size > 25_000_000 {
                skipped.append(item.lastPathComponent)
                continue
            }
            if DocumentExtractor.canExtract(url: item) {
                out.append(item)
            }
        }
        return (out, skipped)
    }

    static func makeTempDirectory() throws -> URL {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("LokaloIndex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        return temp
    }

    /// Compute a stable relative path for manifest keys.
    static func relativePath(of url: URL, to root: URL) -> String {
        let filePath = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        if filePath.hasPrefix(rootPath) {
            let start = filePath.index(filePath.startIndex, offsetBy: rootPath.count)
            var rel = String(filePath[start...])
            if rel.hasPrefix("/") { rel.removeFirst() }
            return rel
        }
        return url.lastPathComponent
    }
}
