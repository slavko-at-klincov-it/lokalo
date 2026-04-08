//
//  ModelStore.swift
//  Lokal
//

import Foundation
import Observation

@MainActor
@Observable
final class ModelStore {

    /// Safety headroom kept free on the volume so we don't fill the disk to
    /// the brim. iOS starts complaining well before the volume is at 0 bytes.
    static let safetyHeadroomBytes: Int64 = 500 * 1024 * 1024

    /// IDs of models that are fully downloaded and ready to load.
    private(set) var installedIDs: Set<String> = []
    /// Currently active model ID (the one ChatStore uses).
    var activeID: String?
    /// Bytes free on the models volume; refreshed by `refreshDiskUsage()`.
    private(set) var freeDiskBytes: Int64 = 0

    var hasInstalledModels: Bool { !installedIDs.isEmpty }
    var activeModel: ModelEntry? { activeID.flatMap { ModelCatalog.entry(id: $0) } }
    var installedModels: [ModelEntry] {
        installedIDs.compactMap { ModelCatalog.entry(id: $0) }
            .sorted { $0.displayName < $1.displayName }
    }
    var suggestedModels: [ModelEntry] {
        ModelCatalog.suggestedEntries().filter { !installedIDs.contains($0.id) }
    }
    var allCatalogModels: [ModelEntry] { ModelCatalog.phoneCompatible }

    /// Sum of bytes occupied by every installed model file.
    var totalInstalledBytes: Int64 {
        installedIDs
            .compactMap { ModelCatalog.entry(id: $0)?.sizeBytes }
            .reduce(0, +)
    }

    func bootstrap() async {
        let docs = Self.modelsDirectory()
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        var found: Set<String> = []
        let entries = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for e in entries where e.pathExtension.lowercased() == "gguf" {
            if let m = ModelCatalog.all.first(where: { $0.filename == e.lastPathComponent }) {
                // Verify size matches expected (cheap integrity check).
                let attrs = try? FileManager.default.attributesOfItem(atPath: e.path)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                if size == m.sizeBytes {
                    found.insert(m.id)
                }
            }
        }
        installedIDs = found
        if let savedActive = UserDefaults.standard.string(forKey: "Lokal.activeModelID"),
           found.contains(savedActive) {
            activeID = savedActive
        } else if let first = found.sorted().first {
            activeID = first
            UserDefaults.standard.set(first, forKey: "Lokal.activeModelID")
        }
        refreshDiskUsage()
    }

    func setActive(_ id: String) {
        guard installedIDs.contains(id) else { return }
        activeID = id
        UserDefaults.standard.set(id, forKey: "Lokal.activeModelID")
    }

    func markInstalled(_ id: String) {
        installedIDs.insert(id)
        if activeID == nil {
            activeID = id
            UserDefaults.standard.set(id, forKey: "Lokal.activeModelID")
        }
        refreshDiskUsage()
    }

    func remove(_ id: String) {
        guard let entry = ModelCatalog.entry(id: id) else { return }
        let url = Self.fileURL(for: entry)
        try? FileManager.default.removeItem(at: url)
        installedIDs.remove(id)
        if activeID == id {
            activeID = installedIDs.sorted().first
            if let a = activeID {
                UserDefaults.standard.set(a, forKey: "Lokal.activeModelID")
            } else {
                UserDefaults.standard.removeObject(forKey: "Lokal.activeModelID")
            }
        }
        refreshDiskUsage()
    }

    func isInstalled(_ id: String) -> Bool { installedIDs.contains(id) }

    // MARK: - Disk usage / eviction planning

    /// Re-read the volume's free-bytes value. Cheap; call after every
    /// install/remove or before showing storage UI.
    func refreshDiskUsage() {
        freeDiskBytes = Self.queryFreeDiskBytes()
    }

    /// True if `entry` fits on disk right now without evicting anything.
    func canFit(_ entry: ModelEntry) -> Bool {
        freeDiskBytes >= entry.sizeBytes + Self.safetyHeadroomBytes
    }

    /// Models we'd suggest deleting to make room for `entry`. Largest first,
    /// excluding the active model and `entry` itself. Returns the smallest
    /// prefix of that list whose freed bytes (combined with current freeBytes)
    /// satisfy `entry.sizeBytes + safetyHeadroom`.
    func evictionCandidates(for entry: ModelEntry) -> [ModelEntry] {
        let needed = entry.sizeBytes + Self.safetyHeadroomBytes - freeDiskBytes
        guard needed > 0 else { return [] }
        let pool = installedModels
            .filter { $0.id != entry.id && $0.id != activeID }
            .sorted { $0.sizeBytes > $1.sizeBytes }
        var freed: Int64 = 0
        var picked: [ModelEntry] = []
        for candidate in pool {
            picked.append(candidate)
            freed += candidate.sizeBytes
            if freed >= needed { break }
        }
        return picked
    }

    /// Sum of `sizeBytes` over the given entries.
    func combinedSize(_ entries: [ModelEntry]) -> Int64 {
        entries.reduce(0) { $0 + $1.sizeBytes }
    }

    private static func queryFreeDiskBytes() -> Int64 {
        let url = modelsDirectory()
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey]
        if let values = try? url.resourceValues(forKeys: keys),
           let bytes = values.volumeAvailableCapacityForImportantUsage {
            return Int64(bytes)
        }
        return 0
    }

    // MARK: - Filesystem helpers

    nonisolated static func modelsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("models", isDirectory: true)
    }

    nonisolated static func fileURL(for entry: ModelEntry) -> URL {
        modelsDirectory().appendingPathComponent(entry.filename)
    }

    nonisolated static func partialFileURL(for entry: ModelEntry) -> URL {
        modelsDirectory().appendingPathComponent(entry.filename + ".partial")
    }
}
