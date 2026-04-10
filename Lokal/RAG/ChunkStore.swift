//
//  ChunkStore.swift
//  Lokal
//
//  SQLite-backed metadata store for RAG chunks. Pairs with USearch:
//  USearch holds (key -> vector), this holds (key -> chunk_text + provenance).
//  Uses the system SQLite3 library — no extra Swift package needed.
//

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor ChunkStore {

    enum StoreError: LocalizedError {
        case openFailed(String)
        case prepareFailed(String)
        case stepFailed(String)

        var errorDescription: String? {
            switch self {
            case .openFailed(let m):     return "Could not open chunk DB: \(m)"
            case .prepareFailed(let m):  return "Could not prepare statement: \(m)"
            case .stepFailed(let m):     return "SQLite step failed: \(m)"
            }
        }
    }

    private var db: OpaquePointer?
    private let url: URL

    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &handle, flags, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(handle))
            sqlite3_close_v2(handle)
            throw StoreError.openFailed(msg)
        }
        self.db = handle
        try createSchema()
    }

    deinit {
        if let db { sqlite3_close_v2(db) }
    }

    private func createSchema() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS chunks (
            key            INTEGER PRIMARY KEY,
            source_id      TEXT NOT NULL,
            document_path  TEXT NOT NULL,
            document_name  TEXT NOT NULL,
            page_index     INTEGER,
            char_start     INTEGER NOT NULL,
            char_end       INTEGER NOT NULL,
            text           TEXT NOT NULL,
            created_at     REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_chunks_source ON chunks(source_id);
        CREATE INDEX IF NOT EXISTS idx_chunks_doc    ON chunks(document_path);
        """
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw StoreError.prepareFailed(msg)
        }
    }

    func insert(key: UInt64,
                sourceID: UUID,
                documentPath: String,
                documentName: String,
                pageIndex: Int?,
                charStart: Int,
                charEnd: Int,
                text: String) throws {
        let sql = """
        INSERT OR REPLACE INTO chunks
          (key, source_id, document_path, document_name, page_index,
           char_start, char_end, text, created_at)
        VALUES (?,?,?,?,?,?,?,?,?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(bitPattern: key))
        sqlite3_bind_text(stmt, 2, sourceID.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, documentPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, documentName, -1, SQLITE_TRANSIENT)
        if let p = pageIndex {
            sqlite3_bind_int(stmt, 5, Int32(p))
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        sqlite3_bind_int(stmt, 6, Int32(charStart))
        sqlite3_bind_int(stmt, 7, Int32(charEnd))
        sqlite3_bind_text(stmt, 8, text, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 9, Date.now.timeIntervalSince1970)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw StoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Batch-insert chunks in a single SQLite transaction. Dramatically
    /// faster than individual inserts for large documents (1 fsync
    /// instead of N).
    func insertBatch(_ chunks: [(key: UInt64, sourceID: UUID, documentPath: String,
                                  documentName: String, pageIndex: Int?,
                                  charStart: Int, charEnd: Int, text: String)]) throws {
        guard !chunks.isEmpty else { return }
        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
        let sql = """
        INSERT OR REPLACE INTO chunks
          (key, source_id, document_path, document_name, page_index,
           char_start, char_end, text, created_at)
        VALUES (?,?,?,?,?,?,?,?,?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        let now = Date.now.timeIntervalSince1970
        for chunk in chunks {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_int64(stmt, 1, Int64(bitPattern: chunk.key))
            sqlite3_bind_text(stmt, 2, chunk.sourceID.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, chunk.documentPath, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, chunk.documentName, -1, SQLITE_TRANSIENT)
            if let p = chunk.pageIndex {
                sqlite3_bind_int(stmt, 5, Int32(p))
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            sqlite3_bind_int(stmt, 6, Int32(chunk.charStart))
            sqlite3_bind_int(stmt, 7, Int32(chunk.charEnd))
            sqlite3_bind_text(stmt, 8, chunk.text, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 9, now)
            if sqlite3_step(stmt) != SQLITE_DONE {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw StoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    }

    func chunks(for keys: [UInt64]) throws -> [KnowledgeChunk] {
        guard !keys.isEmpty else { return [] }
        let placeholders = keys.map { _ in "?" }.joined(separator: ",")
        let sql = """
        SELECT key, source_id, document_path, document_name,
               page_index, char_start, char_end, text
        FROM chunks WHERE key IN (\(placeholders));
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        for (i, key) in keys.enumerated() {
            sqlite3_bind_int64(stmt, Int32(i + 1), Int64(bitPattern: key))
        }
        var out: [KnowledgeChunk] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let key = UInt64(bitPattern: sqlite3_column_int64(stmt, 0))
            let sourceIDStr = String(cString: sqlite3_column_text(stmt, 1))
            let docPath = String(cString: sqlite3_column_text(stmt, 2))
            let docName = String(cString: sqlite3_column_text(stmt, 3))
            let pageIdx: Int? = sqlite3_column_type(stmt, 4) == SQLITE_NULL
                ? nil
                : Int(sqlite3_column_int(stmt, 4))
            let cStart = Int(sqlite3_column_int(stmt, 5))
            let cEnd   = Int(sqlite3_column_int(stmt, 6))
            let text = String(cString: sqlite3_column_text(stmt, 7))
            if let sid = UUID(uuidString: sourceIDStr) {
                out.append(KnowledgeChunk(
                    key: key,
                    sourceID: sid,
                    documentPath: docPath,
                    documentName: docName,
                    pageIndex: pageIdx,
                    charStart: cStart,
                    charEnd: cEnd,
                    text: text
                ))
            }
        }
        return out
    }

    /// Delete specific chunks by their keys. Batches large deletes
    /// to stay within SQLite's parameter limit (~32k).
    func deleteKeys(_ keys: [UInt64]) throws {
        guard !keys.isEmpty else { return }
        let batchSize = 500
        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
        for batch in stride(from: 0, to: keys.count, by: batchSize) {
            let end = min(batch + batchSize, keys.count)
            let slice = keys[batch..<end]
            let placeholders = slice.map { _ in "?" }.joined(separator: ",")
            let sql = "DELETE FROM chunks WHERE key IN (\(placeholders));"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }
            for (i, key) in slice.enumerated() {
                sqlite3_bind_int64(stmt, Int32(i + 1), Int64(bitPattern: key))
            }
            if sqlite3_step(stmt) != SQLITE_DONE {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw StoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    }

    func deleteAll(forSource sourceID: UUID) throws -> [UInt64] {
        let sqlSelect = "SELECT key FROM chunks WHERE source_id = ?;"
        var stmt: OpaquePointer?
        var keys: [UInt64] = []
        if sqlite3_prepare_v2(db, sqlSelect, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sourceID.uuidString, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                keys.append(UInt64(bitPattern: sqlite3_column_int64(stmt, 0)))
            }
            sqlite3_finalize(stmt)
        }
        let sqlDelete = "DELETE FROM chunks WHERE source_id = ?;"
        var delStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sqlDelete, -1, &delStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(delStmt, 1, sourceID.uuidString, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(delStmt)
        }
        sqlite3_finalize(delStmt)
        return keys
    }

    func count(forSource sourceID: UUID) throws -> Int {
        let sql = "SELECT COUNT(*) FROM chunks WHERE source_id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, sourceID.uuidString, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    func totalCount() throws -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM chunks;", -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }
}
