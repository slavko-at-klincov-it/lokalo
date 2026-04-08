//
//  DownloadManager.swift
//  Lokal
//
//  Pull GGUF files from HuggingFace with progress + pause/resume.
//

import Foundation
import Observation

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
    private weak var modelStore: ModelStore?
    private var sessionDelegate: DelegateBox?
    private var session: URLSession?
    private var taskMap: [Int: String] = [:]      // urlSessionTask.taskIdentifier → modelID
    private var lastSampleTime: [String: Date] = [:]
    private var lastSampleBytes: [String: Int64] = [:]

    init() {
        setupSession()
    }

    func attach(modelStore: ModelStore) {
        self.modelStore = modelStore
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

    func startDownload(for entry: ModelEntry) {
        if let existing = tasks[entry.id], existing.state == .downloading { return }
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

        guard let session else { return }
        let dataTask = session.dataTask(with: request)
        taskMap[dataTask.taskIdentifier] = entry.id
        lastSampleTime[entry.id] = .now
        lastSampleBytes[entry.id] = task.bytesDownloaded
        dataTask.resume()
    }

    func cancel(_ id: String) {
        guard let entry = ModelCatalog.entry(id: id) else { return }
        if let urlTask = currentURLSessionTask(for: id) {
            urlTask.cancel()
        }
        if let task = tasks[id] {
            task.state = .paused
        }
        try? FileManager.default.removeItem(at: ModelStore.partialFileURL(for: entry))
        tasks[id]?.bytesDownloaded = 0
    }

    func pause(_ id: String) {
        if let urlTask = currentURLSessionTask(for: id) { urlTask.cancel() }
        tasks[id]?.state = .paused
    }

    func resume(_ id: String) {
        guard let entry = ModelCatalog.entry(id: id) else { return }
        startDownload(for: entry)
    }

    private func currentURLSessionTask(for id: String) -> URLSessionTask? {
        guard let session else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        var found: URLSessionTask?
        session.getAllTasks { all in
            found = all.first { taskID in
                self.taskMap[taskID.taskIdentifier] == id
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1.0)
        return found
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

        if let error {
            // Cancellation gives URLError.cancelled
            if (error as? URLError)?.code == .cancelled {
                if task.state != .paused { task.state = .paused }
                return
            }
            task.state = .failed(error.localizedDescription)
            task.error = error.localizedDescription
            return
        }

        // Move .partial → final filename.
        let partial = ModelStore.partialFileURL(for: entry)
        let final = ModelStore.fileURL(for: entry)
        do {
            if FileManager.default.fileExists(atPath: final.path) {
                try FileManager.default.removeItem(at: final)
            }
            try FileManager.default.moveItem(at: partial, to: final)
            task.state = .completed
            task.bytesDownloaded = task.bytesTotal
            modelStore?.markInstalled(entry.id)
        } catch {
            task.state = .failed("Konnte Datei nicht speichern: \(error.localizedDescription)")
            task.error = task.state == .failed("") ? "" : "\(error)"
        }
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
