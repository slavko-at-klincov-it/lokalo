//
//  DocumentManifest.swift
//  Lokal
//
//  Per-source manifest that records the SHA-256 hash, modification date,
//  and associated chunk keys for every indexed document. Enables
//  incremental re-indexing: only changed / new / deleted files need
//  processing on subsequent runs.
//

import Foundation

struct DocumentRecord: Codable, Hashable {
    let relativePath: String
    let sha256: String
    let modifiedAt: Date
    let chunkKeys: [UInt64]
}

struct DocumentManifest: Codable {
    var sourceID: UUID
    var records: [String: DocumentRecord]   // keyed by relativePath
    var embeddingModelID: String
    var indexedAt: Date

    // MARK: - Persistence

    func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: [.atomic])
    }

    static func load(from url: URL) -> DocumentManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DocumentManifest.self, from: data)
    }
}
