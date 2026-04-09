//
//  RemoteCatalogService.swift
//  Lokal
//
//  Pulls the latest `models.json` from the GitHub `main` branch on app
//  launch and writes it to Application Support. The next launch picks
//  up the cached copy via `ModelCatalog.loadManifest`.
//
//  This is the second half of the data-driven catalog: the first half
//  (`Lokal/Resources/models.json` + `ModelCatalog.loadManifest`) makes
//  the catalog editable as data; this service makes it self-updating
//  without an app rebuild.
//
//  Failure modes are silent on purpose. The bundled catalog is always
//  present, so a failed remote refresh just means "user keeps the
//  catalog they already have". We log to FileLog so a user with debug
//  logging on can see what happened.
//

import Foundation

@MainActor
@Observable
final class RemoteCatalogService {
    /// Where to fetch the catalog from. Points at the `main` branch of
    /// the repo so any merged update is live the next time the user
    /// launches the app.
    static let remoteURL = URL(
        string: "https://raw.githubusercontent.com/slavko-at-klincov-it/lokalo/main/Lokal/Resources/models.json"
    )!

    private(set) var lastRefreshDate: Date?
    private(set) var lastRefreshOutcome: Outcome = .pending

    enum Outcome: Equatable {
        case pending
        case usedRemote(version: Int, entryCount: Int)
        case alreadyFresh
        case skipped(reason: String)
        case failed(message: String)
    }

    /// Fetches the remote catalog. Updates the on-disk cache only if
    /// the remote version is strictly newer than what's already there.
    /// Safe to call from anywhere — never throws, always returns.
    func refresh() async {
        guard let cacheURL = ModelCatalog.cacheURL else {
            lastRefreshOutcome = .skipped(reason: "no Application Support directory")
            FileLog.write("RemoteCatalog: skipped — no Application Support directory")
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            var request = URLRequest(url: Self.remoteURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                lastRefreshOutcome = .failed(message: "no HTTP response")
                FileLog.write("RemoteCatalog: failed — no HTTP response")
                return
            }

            guard http.statusCode == 200 else {
                lastRefreshOutcome = .failed(message: "HTTP \(http.statusCode)")
                FileLog.write("RemoteCatalog: failed — HTTP \(http.statusCode)")
                return
            }

            // Validate the payload before persisting it. A garbled
            // catalog must NEVER overwrite the working cache.
            let remote = try JSONDecoder().decode(CatalogManifest.self, from: data)

            guard !remote.entries.isEmpty else {
                lastRefreshOutcome = .failed(message: "remote catalog has no entries")
                FileLog.write("RemoteCatalog: failed — remote has 0 entries")
                return
            }

            // Compare against whatever the loader currently uses
            // (which itself is the higher of bundled and previous cache).
            let current = ModelCatalog.manifest
            if remote.version <= current.version {
                lastRefreshOutcome = .alreadyFresh
                lastRefreshDate = Date()
                FileLog.write("RemoteCatalog: already fresh (remote v\(remote.version) ≤ local v\(current.version))")
                return
            }

            try data.write(to: cacheURL, options: .atomic)
            lastRefreshOutcome = .usedRemote(version: remote.version, entryCount: remote.entries.count)
            lastRefreshDate = Date()
            FileLog.write("RemoteCatalog: cached v\(remote.version) with \(remote.entries.count) entries")
        } catch {
            lastRefreshOutcome = .failed(message: error.localizedDescription)
            FileLog.write("RemoteCatalog: failed — \(error.localizedDescription)")
        }
    }
}
