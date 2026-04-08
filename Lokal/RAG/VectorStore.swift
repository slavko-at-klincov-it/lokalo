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
        case createFailed(String)

        var errorDescription: String? {
            switch self {
            case .dimensionMismatch(let e, let g):
                return "Vector dimension mismatch (expected \(e), got \(g))"
            case .persistFailed(let m): return "Vector index save failed: \(m)"
            case .loadFailed(let m):    return "Vector index load failed: \(m)"
            case .createFailed(let m):  return "Vector index create failed: \(m)"
            }
        }
    }

    private let index: USearchIndex
    let dimensions: Int
    private let storeURL: URL
    private var reservedCapacity: UInt32 = 0

    init(dimensions: Int, storeURL: URL) throws {
        self.dimensions = dimensions
        self.storeURL = storeURL

        do {
            let idx = try USearchIndex.make(
                metric: .cos,
                dimensions: UInt32(dimensions),
                connectivity: 16,
                quantization: .f16
            )
            try idx.reserve(1024)
            self.reservedCapacity = 1024
            self.index = idx
        } catch {
            throw StoreError.createFailed(error.localizedDescription)
        }

        if FileManager.default.fileExists(atPath: storeURL.path) {
            do {
                try index.load(path: storeURL.path)
            } catch {
                throw StoreError.loadFailed(error.localizedDescription)
            }
        }
    }

    /// Number of vectors currently in the index.
    var count: Int {
        (try? index.count) ?? 0
    }

    func upsert(key: UInt64, embedding: [Float32]) throws {
        guard embedding.count == dimensions else {
            throw StoreError.dimensionMismatch(expected: dimensions, got: embedding.count)
        }
        let currentCount = (try? index.count) ?? 0
        if currentCount >= Int(reservedCapacity) {
            let newCapacity = reservedCapacity * 2 + 64
            try index.reserve(newCapacity)
            reservedCapacity = newCapacity
        }
        try index.add(key: key, vector: embedding)
    }

    func remove(key: UInt64) {
        _ = try? index.remove(key: key)
    }

    func search(query: [Float32], topK: Int = 8) throws -> [(key: UInt64, distance: Float32)] {
        guard query.count == dimensions else {
            throw StoreError.dimensionMismatch(expected: dimensions, got: query.count)
        }
        let result = try index.search(vector: query, count: topK)
        return zip(result.0, result.1).map { ($0, $1) }
    }

    func persist() throws {
        do {
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
        try? FileManager.default.removeItem(at: storeURL)
    }
}
