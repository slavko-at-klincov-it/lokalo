//
//  DownloadManager.swift
//  Lokal
//
//  Pull GGUF files from HuggingFace with progress + pause/resume.
//

import Foundation
import Network
import Observation
import CryptoKit

/// Coarse classification of the active network path. The download manager
/// uses this to honor the user's "Modelle ohne WLAN laden" preference.
enum NetworkType: Equatable {
    case wifi
    case cellular
    case none
}

@MainActor
@Observable
final class DownloadTask: Identifiable {
    let id: String   // model entry id
    let entry: ModelEntry
    var bytesDownloaded: Int64 = 0
    var bytesTotal: Int64 = 0
    var bytesPerSecond: Double = 0
    var state: State = .queued
    var error: String?

    enum State: Equatable {
        case queued
        case downloading
        /// Fully downloaded, hashing the file to verify its `sha256`
        /// before the atomic rename to the final filename. The UI
        /// should show a spinner with a "Wird überprüft…" label.
        case verifying
        case paused
        case completed
        case failed(String)
    }

    var progress: Double {
        bytesTotal > 0 ? min(1.0, Double(bytesDownloaded) / Double(bytesTotal)) : 0
    }

    init(entry: ModelEntry) {
        self.id = entry.id
        self.entry = entry
        self.bytesTotal = entry.sizeBytes
    }
}

@MainActor
@Observable
final class DownloadManager {
    private(set) var tasks: [String: DownloadTask] = [:]
    /// Latest classification of the device's network path. Updated by an
    /// `NWPathMonitor` running on a background queue. Read by the UI to
    /// decide whether to warn the user about cellular downloads.
    private(set) var currentNetworkType: NetworkType = .wifi
    private let modelStore: ModelStore
    private var sessionDelegate: DelegateBox?
    private var session: URLSession?
    /// Forward lookup: modelID → URLSessionDataTask. Used by `cancel` /
    /// `pause` to reach into URLSession without doing an async
    /// `getAllTasks` traversal. Entries are inserted in `startDownload`
    /// and removed in `completed` (or on manual cancel).
    private var urlTasks: [String: URLSessionDataTask] = [:]
    /// Reverse lookup: URLSessionTask.taskIdentifier → modelID. Needed
    /// because the URLSession delegate callbacks hand us an `Int`
    /// identifier and we need to route back to the right `DownloadTask`.
    private var taskMap: [Int: String] = [:]
    private var lastSampleTime: [String: Date] = [:]
    private var lastSampleBytes: [String: Int64] = [:]
    /// `NWPathMonitor` is thread-safe (it can be cancelled from any queue),
    /// so we mark it `nonisolated(unsafe)` to allow access from `deinit`.
    nonisolated(unsafe) private var pathMonitor: NWPathMonitor?
    private let pathMonitorQueue = DispatchQueue(label: "lokalo.downloadmanager.pathmonitor")

    init(modelStore: ModelStore) {
        self.modelStore = modelStore
        setupSession()
        startPathMonitoring()
    }

    deinit {
        pathMonitor?.cancel()
    }

    /// True when the user is currently on cellular AND has not opted in to
    /// large downloads over mobile in onboarding / settings. UI should warn
    /// the user before calling `startDownload(for:)` (or pass `force: true`).
    var cellularDownloadsBlocked: Bool {
        let allowed = UserDefaults.standard.bool(forKey: OnboardingPreferences.cellularDownloadsAllowedKey)
        return currentNetworkType == .cellular && !allowed
    }

    /// Same check tied to a specific entry — kept as a separate API so the UI
    /// reads naturally even though the logic is currently entry-independent.
    func cellularBlocks(_ entry: ModelEntry) -> Bool {
        return cellularDownloadsBlocked
    }

    private func startPathMonitoring() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let type: NetworkType
            if path.status == .satisfied {
                if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
                    type = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    type = .cellular
                } else {
                    type = .wifi
                }
            } else {
                type = .none
            }
            Task { @MainActor in
                self?.currentNetworkType = type
            }
        }
        monitor.start(queue: pathMonitorQueue)
    }

    private func setupSession() {
        let box = DelegateBox()
        sessionDelegate = box
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = true
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60 * 6
        config.httpMaximumConnectionsPerHost = 2
        let session = URLSession(configuration: config, delegate: box, delegateQueue: nil)
        self.session = session
        box.manager = self
    }

    /// Re-attach any in-flight tasks after app launch (best-effort).
    func resumePending() async {
        // Walk the partial files in the models directory; nothing to "resume" yet
        // because background tasks aren't restored across launches in this simple build.
        let dir = ModelStore.modelsDirectory()
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for e in entries where e.pathExtension == "partial" {
            // Leave them on disk; user can re-tap download to resume.
            _ = e
        }
    }

    func task(for id: String) -> DownloadTask? { tasks[id] }

    // MARK: - Public actions

    /// Start (or resume) a download. Honors the cellular preference unless
    /// `force` is true. Returns false when the call was refused because the
    /// user is on cellular and hasn't opted in — the UI should react by
    /// showing a confirmation, then re-call with `force: true`.
    @discardableResult
    func startDownload(for entry: ModelEntry, force: Bool = false) -> Bool {
        if !force && cellularBlocks(entry) {
            return false
        }
        if let existing = tasks[entry.id], existing.state == .downloading { return true }
        try? FileManager.default.createDirectory(at: ModelStore.modelsDirectory(), withIntermediateDirectories: true)
        let task = tasks[entry.id] ?? DownloadTask(entry: entry)
        tasks[entry.id] = task
        task.state = .downloading
        task.error = nil

        var request = URLRequest(url: entry.downloadURL)
        request.setValue("Lokal/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        let partial = ModelStore.partialFileURL(for: entry)
        let resumeOffset = (try? FileManager.default.attributesOfItem(atPath: partial.path)[.size] as? NSNumber)?.int64Value ?? 0
        if resumeOffset > 0 && resumeOffset < entry.sizeBytes {
            request.setValue("bytes=\(resumeOffset)-", forHTTPHeaderField: "Range")
            task.bytesDownloaded = resumeOffset
        } else {
            try? FileManager.default.removeItem(at: partial)
            task.bytesDownloaded = 0
        }

        guard let session else { return false }
        let dataTask = session.dataTask(with: request)
        taskMap[dataTask.taskIdentifier] = entry.id
        urlTasks[entry.id] = dataTask
        lastSampleTime[entry.id] = .now
        lastSampleBytes[entry.id] = task.bytesDownloaded
        dataTask.resume()
        return true
    }

    func cancel(_ id: String) {
        guard let entry = ModelCatalog.entry(id: id) else { return }
        urlTasks[id]?.cancel()
        urlTasks.removeValue(forKey: id)
        if let task = tasks[id] {
            task.state = .paused
        }
        try? FileManager.default.removeItem(at: ModelStore.partialFileURL(for: entry))
        tasks[id]?.bytesDownloaded = 0
    }

    func pause(_ id: String) {
        urlTasks[id]?.cancel()
        urlTasks.removeValue(forKey: id)
        tasks[id]?.state = .paused
    }

    func resume(_ id: String) {
        guard let entry = ModelCatalog.entry(id: id) else { return }
        startDownload(for: entry)
    }

    // MARK: - Delegate callbacks

    fileprivate func received(_ data: Data, for taskIdentifier: Int) {
        guard let modelID = taskMap[taskIdentifier],
              let entry = ModelCatalog.entry(id: modelID),
              let task = tasks[modelID] else { return }

        let partial = ModelStore.partialFileURL(for: entry)
        // Append.
        if FileManager.default.fileExists(atPath: partial.path) {
            if let handle = try? FileHandle(forWritingTo: partial) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        } else {
            try? data.write(to: partial)
        }
        task.bytesDownloaded += Int64(data.count)

        // Sample throughput.
        let now = Date()
        let lastTime = lastSampleTime[modelID] ?? now
        if now.timeIntervalSince(lastTime) >= 0.5 {
            let lastBytes = lastSampleBytes[modelID] ?? 0
            let elapsed = now.timeIntervalSince(lastTime)
            let bytes = task.bytesDownloaded - lastBytes
            task.bytesPerSecond = elapsed > 0 ? Double(bytes) / elapsed : 0
            lastSampleTime[modelID] = now
            lastSampleBytes[modelID] = task.bytesDownloaded
        }
    }

    fileprivate func gotResponse(_ response: URLResponse, for taskIdentifier: Int) {
        guard let modelID = taskMap[taskIdentifier],
              let task = tasks[modelID],
              let http = response as? HTTPURLResponse else { return }
        // For Range requests we get 206 + Content-Range "bytes A-B/C"
        if http.statusCode == 206, let cr = http.value(forHTTPHeaderField: "Content-Range"),
           let total = Int64(cr.split(separator: "/").last.map(String.init) ?? "") {
            task.bytesTotal = total
        } else if let len = http.value(forHTTPHeaderField: "Content-Length"),
                  let bytes = Int64(len) {
            // For 200 responses, Content-Length is the remaining (full) size.
            task.bytesTotal = task.bytesDownloaded + bytes
            if task.bytesTotal == bytes && task.bytesDownloaded > 0 {
                // Server didn't honor Range; reset partial file.
                let partial = ModelStore.partialFileURL(for: task.entry)
                try? FileManager.default.removeItem(at: partial)
                task.bytesDownloaded = 0
                task.bytesTotal = bytes
            }
        }
    }

    fileprivate func completed(_ taskIdentifier: Int, error: Error?) {
        guard let modelID = taskMap[taskIdentifier],
              let entry = ModelCatalog.entry(id: modelID),
              let task = tasks[modelID] else { return }
        taskMap.removeValue(forKey: taskIdentifier)
        urlTasks.removeValue(forKey: modelID)

        if let error {
            // Cancellation gives URLError.cancelled
            if (error as? URLError)?.code == .cancelled {
                if task.state != .paused { task.state = .paused }
                return
            }
            task.state = .failed(error.lokaloMessage)
            task.error = error.lokaloMessage
            return
        }

        // The download finished OK. Verify the hash (if any) off the
        // main actor — SHA-256 of a 500 MB file blocks the UI for
        // ~1-2 s on modern iPhones, too long to do synchronously on
        // MainActor. The partial stays in place until verification
        // succeeds; the atomic rename is the very last step.
        task.state = .verifying
        let partial = ModelStore.partialFileURL(for: entry)
        let final = ModelStore.fileURL(for: entry)
        let expected = entry.sha256
        let finalizedID = entry.id

        Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = Self.verifyAndInstall(
                partial: partial,
                final: final,
                expectedHash: expected
            )
            // `finalize` is MainActor-isolated; `await` hops back.
            await self?.finalize(modelID: finalizedID, outcome: outcome)
        }
    }

    /// Applies the result of the off-main-actor verify/move step back
    /// onto the `DownloadTask`. Called from `completed()` via
    /// `Task.detached` → `MainActor.run`.
    private func finalize(modelID: String, outcome: VerifyOutcome) {
        guard let task = tasks[modelID] else { return }
        switch outcome {
        case .installed(let totalBytes):
            task.state = .completed
            task.bytesDownloaded = totalBytes
            modelStore.markInstalled(modelID)
        case .verificationFailed(let expected, let actual):
            // A bad hash means corrupted bytes or an actively wrong
            // file at the URL — never silently keep it. The partial
            // has already been deleted by `verifyAndInstall`.
            let msg = "Integritätsprüfung fehlgeschlagen. Erwartet: \(expected.prefix(12))…, erhalten: \(actual.prefix(12))…"
            task.state = .failed(msg)
            task.error = msg
        case .moveFailed(let message):
            task.state = .failed(message)
            task.error = message
        }
    }

    private enum VerifyOutcome {
        case installed(totalBytes: Int64)
        case verificationFailed(expected: String, actual: String)
        case moveFailed(String)
    }

    /// Pure function that runs on a detached task (NOT on MainActor).
    /// Hashes the partial file if `expectedHash` is non-nil, bails
    /// immediately on mismatch, then moves to the final location.
    nonisolated private static func verifyAndInstall(
        partial: URL,
        final: URL,
        expectedHash: String?
    ) -> VerifyOutcome {
        if let expectedHash {
            let actual: String
            do {
                actual = try sha256Hex(of: partial)
            } catch {
                return .moveFailed("Konnte Datei nicht prüfen: \(error.lokaloMessage)")
            }
            if actual != expectedHash {
                // Delete the corrupted partial so a retry starts fresh.
                try? FileManager.default.removeItem(at: partial)
                return .verificationFailed(expected: expectedHash, actual: actual)
            }
        }

        do {
            if FileManager.default.fileExists(atPath: final.path) {
                try FileManager.default.removeItem(at: final)
            }
            try FileManager.default.moveItem(at: partial, to: final)
            let attrs = try FileManager.default.attributesOfItem(atPath: final.path)
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            return .installed(totalBytes: size)
        } catch {
            return .moveFailed("Konnte Datei nicht speichern: \(error.lokaloMessage)")
        }
    }

    /// Streams the file through a CryptoKit SHA-256 hasher in 1 MB
    /// chunks so we never hold more than one chunk in memory at a time.
    /// Returns the digest as a lowercase hex string for direct
    /// comparison against `models.json`.
    nonisolated private static func sha256Hex(of fileURL: URL) throws -> String {
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

// MARK: - URLSession delegate (forwards to actor)

private final class DelegateBox: NSObject, URLSessionDataDelegate {
    weak var manager: DownloadManager?

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let id = dataTask.taskIdentifier
        Task { @MainActor in self.manager?.gotResponse(response, for: id) }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        let id = dataTask.taskIdentifier
        let copy = data
        Task { @MainActor in self.manager?.received(copy, for: id) }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        Task { @MainActor in self.manager?.completed(id, error: error) }
    }
}
