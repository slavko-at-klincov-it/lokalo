//
//  KnowledgeBase.swift
//  Lokal
//
//  Codable model types for the RAG system. A KnowledgeBase is a collection
//  of Sources; each Source is a folder/repo/cloud-drive that gets indexed
//  into a USearch HNSW index + sqlite chunk metadata DB.
//

import Foundation

/// Top-level container; in v1 we keep ONE active KB, but the model already
/// supports multiple so the user can later switch.
struct KnowledgeBase: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var createdAt: Date
    /// The embedding model used to populate this KB. Locked once indexed.
    var embeddingModelID: String
    /// Vector dimensions (must match `embeddingModelID`).
    var dimensions: Int
    var sources: [KnowledgeSource]

    init(id: UUID = UUID(),
         name: String,
         embeddingModelID: String,
         dimensions: Int,
         sources: [KnowledgeSource] = []) {
        self.id = id
        self.name = name
        self.createdAt = .now
        self.embeddingModelID = embeddingModelID
        self.dimensions = dimensions
        self.sources = sources
    }

    var totalChunks: Int { sources.reduce(0) { $0 + $1.indexedChunks } }
    var totalDocuments: Int { sources.reduce(0) { $0 + $1.indexedDocuments } }
}

enum KnowledgeSourceKind: String, Codable, Sendable, Hashable {
    case localFolder
    case githubRepo
    case googleDriveFolder
    case onedriveFolder

    var label: String {
        switch self {
        case .localFolder:        return "Lokaler Ordner"
        case .githubRepo:         return "GitHub Repo"
        case .googleDriveFolder:  return "Google Drive"
        case .onedriveFolder:     return "OneDrive"
        }
    }

    var iconName: String {
        switch self {
        case .localFolder:        return "folder"
        case .githubRepo:         return "chevron.left.forwardslash.chevron.right"
        case .googleDriveFolder:  return "doc.circle"
        case .onedriveFolder:     return "cloud"
        }
    }
}

enum KnowledgeSourceStatus: String, Codable, Sendable, Hashable {
    case idle
    case indexing
    case ready
    case error
}

struct KnowledgeSource: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var kind: KnowledgeSourceKind
    var displayName: String
    /// For `.localFolder`: a security-scoped bookmark created from the picker.
    /// For OAuth-based sources: the remote root identifier (repo full_name, drive folder ID).
    var bookmark: Data?
    var remoteRootID: String?
    /// For OAuth sources: which `Connection.id` (provider login) was used.
    var connectionID: UUID?
    var createdAt: Date
    var lastIndexedAt: Date?
    var indexedDocuments: Int
    var indexedChunks: Int
    var status: KnowledgeSourceStatus
    var statusMessage: String?

    init(id: UUID = UUID(),
         kind: KnowledgeSourceKind,
         displayName: String,
         bookmark: Data? = nil,
         remoteRootID: String? = nil,
         connectionID: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.bookmark = bookmark
        self.remoteRootID = remoteRootID
        self.connectionID = connectionID
        self.createdAt = .now
        self.lastIndexedAt = nil
        self.indexedDocuments = 0
        self.indexedChunks = 0
        self.status = .idle
        self.statusMessage = nil
    }
}

/// In-memory representation of a chunk pulled from sqlite for citation rendering.
struct KnowledgeChunk: Hashable, Codable, Sendable {
    let key: UInt64
    let sourceID: UUID
    let documentPath: String
    let documentName: String
    let pageIndex: Int?
    let charStart: Int
    let charEnd: Int
    let text: String
}

/// A retrieval hit with its distance score.
struct RetrievalHit: Hashable, Sendable {
    let chunk: KnowledgeChunk
    let distance: Float
}

/// Citation surfaced on an assistant message in the chat.
struct Citation: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let sourceName: String
    let snippet: String
    let pageIndex: Int?
    let documentPath: String

    init(id: UUID = UUID(),
         sourceName: String,
         snippet: String,
         pageIndex: Int?,
         documentPath: String) {
        self.id = id
        self.sourceName = sourceName
        self.snippet = snippet
        self.pageIndex = pageIndex
        self.documentPath = documentPath
    }
}
