//
//  EmbeddingDownloader.swift
//  Lokal
//
//  Lightweight downloader for embedding GGUFs. Uses URLSession.bytes(for:)
//  for resumable progress reporting. Embedding models are small (<200 MB),
//  so we don't need the full pause/resume machinery of DownloadManager.
//

import Foundation
import Observation

@MainActor
@Observable
final class EmbeddingDownloader {

    enum State: Equatable {
        case idle
        case downloading
        case completed
        case failed(String)
    }

    var state: State = .idle
    var bytesDownloaded: Int64 = 0
    var bytesTotal: Int64 = 0
    var currentEntryID: String?

    private weak var store: EmbeddingModelStore?

    var progress: Double {
        bytesTotal > 0 ? min(1.0, Double(bytesDownloaded) / Double(bytesTotal)) : 0
    }

    func attach(store: EmbeddingModelStore) {
        self.store = store
    }

    func download(_ entry: EmbeddingModelEntry) async {
        if state == .downloading { return }
        state = .downloading
        currentEntryID = entry.id
        bytesDownloaded = 0
        bytesTotal = entry.sizeBytes

        let final = EmbeddingModelStore.fileURL(for: entry)
        let partial = EmbeddingModelStore.partialFileURL(for: entry)
        try? FileManager.default.createDirectory(
            at: EmbeddingModelStore.modelsDirectory(),
            withIntermediateDirectories: true
        )

        var request = URLRequest(url: entry.downloadURL)
        request.setValue("Lokalo/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            if let http = response as? HTTPURLResponse,
               let lenStr = http.value(forHTTPHeaderField: "Content-Length"),
               let len = Int64(lenStr), len > 0 {
                bytesTotal = len
            }
            // Stream into the partial file.
            try? FileManager.default.removeItem(at: partial)
            FileManager.default.createFile(atPath: partial.path, contents: nil)
            guard let handle = try? FileHandle(forWritingTo: partial) else {
                throw NSError(domain: "EmbeddingDownloader", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Could not open partial file for writing"])
            }
            defer { try? handle.close() }

            var buffer: [UInt8] = []
            buffer.reserveCapacity(64 * 1024)
            var lastFlush = Date()
            for try await byte in asyncBytes {
                buffer.append(byte)
                if buffer.count >= 64 * 1024 {
                    try handle.write(contentsOf: Data(buffer))
                    bytesDownloaded += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    if Date().timeIntervalSince(lastFlush) > 0.1 {
                        lastFlush = Date()
                    }
                }
            }
            if !buffer.isEmpty {
                try handle.write(contentsOf: Data(buffer))
                bytesDownloaded += Int64(buffer.count)
            }
            try handle.close()

            // Move into place.
            if FileManager.default.fileExists(atPath: final.path) {
                try FileManager.default.removeItem(at: final)
            }
            try FileManager.default.moveItem(at: partial, to: final)
            state = .completed
            store?.markInstalled(entry.id)
        } catch {
            state = .failed(error.lokaloMessage)
            try? FileManager.default.removeItem(at: partial)
        }
    }
}
