//
//  ModelStore.swift
//  Lokal
//

import Foundation
import Observation

@MainActor
@Observable
final class ModelStore {

    /// IDs of models that are fully downloaded and ready to load.
    private(set) var installedIDs: Set<String> = []
    /// Currently active model ID (the one ChatStore uses).
    var activeID: String?

    var hasInstalledModels: Bool { !installedIDs.isEmpty }
    var activeModel: ModelEntry? { activeID.flatMap { ModelCatalog.entry(id: $0) } }
    var installedModels: [ModelEntry] {
        installedIDs.compactMap { ModelCatalog.entry(id: $0) }
            .sorted { $0.displayName < $1.displayName }
    }
    var suggestedModels: [ModelEntry] {
        ModelCatalog.suggestedEntries().filter { !installedIDs.contains($0.id) }
    }
    var allCatalogModels: [ModelEntry] { ModelCatalog.all }

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
    }

    func isInstalled(_ id: String) -> Bool { installedIDs.contains(id) }

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
