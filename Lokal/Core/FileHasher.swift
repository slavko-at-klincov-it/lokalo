//
//  FileHasher.swift
//  Lokal
//
//  Streaming SHA-256 hash utility. Processes files in 1 MB chunks so
//  memory stays flat even for large documents.
//

import Foundation
import CryptoKit

enum FileHasher {
    /// Returns the SHA-256 digest as a lowercase hex string.
    /// Streams through the file in 1 MB chunks — never holds more than
    /// one chunk in memory at a time.
    static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 1 << 20 // 1 MiB
        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
