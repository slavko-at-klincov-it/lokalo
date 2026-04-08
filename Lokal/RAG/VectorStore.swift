//
//  VectorStore.swift
//  Lokal
//
//  Thin actor wrapper around USearch's HNSW index. One instance per
//  knowledge base. Persists to a single .usearch file on disk.
//

import Foundation
import USearch

actor VectorStore {

    enum StoreError: LocalizedError {
        case dimensionMismatch(expected: Int, got: Int)
        case persistFailed(String)
        case loadFailed(String)

        var errorDescription: String? {
            switch self {
            case .dimensionMismatch(let e, let g):
                return "Vector dimension mismatch (expected \(e), got \(g))"
            case .persistFailed(let m): return "Vector index save failed: \(m)"
            case .loadFailed(let m):    return "Vector index load failed: \(m)"
            }
        }
    }

    private let index: USearchIndex
    let dimensions: UInt32
    private let storeURL: URL

    init(dimensions: Int, storeURL: URL) throws {
        self.dimensions = UInt32(dimensions)
        self.storeURL = storeURL

        let idx = USearchIndex.make(
            metric: .cos,
            dimensions: UInt32(dimensions),
            connectivity: 16,
            quantization: .F16
        )
        idx.reserve(1024)
        self.index = idx

        if FileManager.default.fileExists(atPath: storeURL.path) {
            do {
                try index.load(path: storeURL.path)
            } catch {
                throw StoreError.loadFailed(error.localizedDescription)
            }
        }
    }

    /// Number of vectors currently in the index.
    var count: Int { Int(index.count) }

    func upsert(key: UInt64, embedding: [Float32]) throws {
        guard embedding.count == Int(dimensions) else {
            throw StoreError.dimensionMismatch(expected: Int(dimensions), got: embedding.count)
        }
        if index.capacity == index.count {
            index.reserve(UInt32(index.capacity * 2 + 64))
        }
        index.add(key: key, vector: embedding)
    }

    func remove(key: UInt64) {
        _ = index.remove(key: key)
    }

    func search(query: [Float32], topK: Int = 8) throws -> [(key: UInt64, distance: Float32)] {
        guard query.count == Int(dimensions) else {
            throw StoreError.dimensionMismatch(expected: Int(dimensions), got: query.count)
        }
        let result = index.search(vector: query, count: UInt32(topK))
        return zip(result.0, result.1).map { ($0, $1) }
    }

    func persist() throws {
        do {
            // Make sure the parent directory exists.
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try index.save(path: storeURL.path)
        } catch {
            throw StoreError.persistFailed(error.localizedDescription)
        }
    }

    func resetIndex() {
        // USearch has no clear-all API; recreate by removing the file and
        // re-instantiating in the next init() call. Callers should rebuild.
        try? FileManager.default.removeItem(at: storeURL)
    }
}
