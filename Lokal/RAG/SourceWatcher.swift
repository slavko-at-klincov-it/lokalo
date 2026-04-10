//
//  SourceWatcher.swift
//  Lokal
//
//  Watches local-folder knowledge sources for filesystem changes using
//  DispatchSource. When a change is detected, fires `onSourceChanged`
//  after a debounce delay so that rapid saves (e.g. user editing a file)
//  don't trigger N re-indexes.
//
//  Limitation: DispatchSource on iOS only detects changes to the watched
//  directory itself (direct children added/removed), not recursive
//  subdirectory changes. The actual change detection therefore relies on
//  SHA-256 manifest comparison during incremental indexing — the
//  DispatchSource serves as a lightweight "something probably changed"
//  hint that triggers the real diff.
//

import Foundation
import Observation

@MainActor
@Observable
final class SourceWatcher {

    /// Fires when a watched source's folder has changed. The caller
    /// (LokalApp) connects this to IndexingService.indexSource().
    var onSourceChanged: ((UUID) -> Void)?

    /// Bundles every resource associated with a single watch so that
    /// cleanup is straightforward and nothing leaks.
    private struct WatchEntry {
        let dispatchSource: DispatchSourceFileSystemObject
        /// The security-scoped URL whose access must be held for the
        /// lifetime of the file descriptor.
        let scopedURL: URL?
        let didStartAccess: Bool
    }

    private var entries: [UUID: WatchEntry] = [:]
    private var debounceTasks: [UUID: Task<Void, Never>] = [:]

    private static let debounceSeconds: UInt64 = 5

    /// Start watching a local-folder source for changes.
    func watch(source: KnowledgeSource) {
        guard source.kind == .localFolder, source.bookmark != nil else { return }
        guard entries[source.id] == nil else { return }

        guard let url = try? IndexingService.resolveFolderURL(from: source) else { return }
        let started = url.startAccessingSecurityScopedResource()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            if started { url.stopAccessingSecurityScopedResource() }
            return
        }

        // Keep a reference to the scoped URL so we can release access
        // when the watch is cancelled.
        let scopedURL = started ? url : nil

        let sourceID = source.id
        let dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .link],
            queue: .main
        )
        dispatchSource.setEventHandler { [weak self] in
            self?.handleChange(sourceID: sourceID)
        }
        dispatchSource.setCancelHandler { [scopedURL, started] in
            close(fd)
            if started { scopedURL?.stopAccessingSecurityScopedResource() }
        }
        dispatchSource.resume()

        entries[sourceID] = WatchEntry(
            dispatchSource: dispatchSource,
            scopedURL: scopedURL,
            didStartAccess: started
        )
    }

    /// Stop watching a source (e.g. when it's removed).
    func unwatch(sourceID: UUID) {
        debounceTasks[sourceID]?.cancel()
        debounceTasks.removeValue(forKey: sourceID)

        if let entry = entries.removeValue(forKey: sourceID) {
            entry.dispatchSource.cancel()
        }
    }

    /// Watch all local-folder sources in the given knowledge bases.
    func watchAll(in bases: [KnowledgeBase]) {
        for kb in bases {
            for source in kb.sources where source.kind == .localFolder {
                watch(source: source)
            }
        }
    }

    /// Stop all watchers.
    func unwatchAll() {
        for (_, task) in debounceTasks { task.cancel() }
        debounceTasks.removeAll()
        for (_, entry) in entries { entry.dispatchSource.cancel() }
        entries.removeAll()
    }

    // MARK: - Private

    private func handleChange(sourceID: UUID) {
        debounceTasks[sourceID]?.cancel()
        debounceTasks[sourceID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.onSourceChanged?(sourceID)
        }
    }
}
