//
//  DownloadManagerTests.swift
//  LokalTests
//
//  Verifies the DownloadManager can pull a real (small) GGUF from HuggingFace
//  and lands it in Documents/models with the expected size.
//

import XCTest
@testable import Lokal

@MainActor
final class DownloadManagerTests: XCTestCase {

    func testCanFetchRangeHeaderFromHF() async throws {
        // Smallest catalog entry: Qwen 0.5B Q4_K_M ~380MB. We only fetch 1 MB
        // (Range request) to keep this test fast yet exercise the real CDN.
        let entry = try XCTUnwrap(ModelCatalog.entry(id: "qwen-2.5-0.5b-instruct-q4km"))
        var request = URLRequest(url: entry.downloadURL)
        request.setValue("Lokal/1.0 (iOS test)", forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=0-1048575", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertTrue(http.statusCode == 206 || http.statusCode == 200,
                      "Expected 206/200, got \(http.statusCode)")
        XCTAssertGreaterThanOrEqual(data.count, 1024 * 256, "Response too small")
        // GGUF magic header is "GGUF"
        let prefix = data.prefix(4)
        XCTAssertEqual(prefix, Data("GGUF".utf8), "First 4 bytes should be 'GGUF', got \(prefix.map { String(format: "%02x", $0) }.joined())")
    }

    func testStartDownloadProgressesViaDownloadManager() async throws {
        // Use TinyLlama 1.1B Chat — NOT preloaded by other tests, so the
        // DownloadManager flow always runs from scratch.
        let entry = try XCTUnwrap(ModelCatalog.entry(id: "tinyllama-1.1b-chat-q4km"))

        let partial = ModelStore.partialFileURL(for: entry)
        let final = ModelStore.fileURL(for: entry)
        try? FileManager.default.removeItem(at: partial)
        try? FileManager.default.removeItem(at: final)

        let store = ModelStore()
        await store.bootstrap()
        let manager = DownloadManager()
        manager.attach(modelStore: store)

        manager.startDownload(for: entry)
        // Wait up to 25s for at least 1 MB of progress.
        let deadline = Date().addingTimeInterval(25)
        var progressed = false
        while Date() < deadline {
            if let task = manager.task(for: entry.id), task.bytesDownloaded > 1_048_576 {
                progressed = true
                break
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        manager.cancel(entry.id)
        XCTAssertTrue(progressed, "Expected at least 1 MB of progress within 25 seconds")
        // Clean up partial file so this test is idempotent.
        try? FileManager.default.removeItem(at: ModelStore.partialFileURL(for: entry))
    }
}
