//
//  ModelCatalog.swift
//  Lokal
//
//  Data-driven catalog of GGUF models that fit on iPhone.
//
//  The catalog used to be a hardcoded Swift array — every new model meant
//  a TestFlight build and a 1-day Apple review. Now the source of truth is
//  `Lokal/Resources/models.json`. The same JSON is also fetched from the
//  GitHub `main` branch by `RemoteCatalogService` so the app can pick up
//  new entries without an app update.
//
//  Loader precedence on launch:
//    1. Cached `catalog.json` in Application Support, IF its `version`
//       is greater-or-equal to the bundled version (i.e. user has had
//       at least one successful remote refresh since the last update).
//    2. Bundled `models.json` from the app bundle (always present).
//    3. Empty manifest if both fail (defensive — should never happen).
//
//  All URLs are verified against bartowski/* / unsloth/* HuggingFace
//  mirrors. Sizes are exact Content-Length values from the LFS CDN.
//

import Foundation

/// Top-level shape of `models.json`. Versioned so we can ship breaking
/// changes safely (the loader compares bundled vs cached version and
/// picks the newer one).
struct CatalogManifest: Codable, Sendable {
    let version: Int
    let generatedAt: String
    let maxEffectiveBillion: Double
    let suggested: [String]
    let entries: [ModelEntry]

    static let empty = CatalogManifest(
        version: 0,
        generatedAt: "missing",
        maxEffectiveBillion: 7.0,
        suggested: [],
        entries: []
    )
}

enum ModelCatalog {
    /// Loaded once at first access. Reads cache, falls back to bundled.
    static let manifest: CatalogManifest = loadManifest()

    static var all: [ModelEntry] { manifest.entries }
    static var suggested: [String] { manifest.suggested }

    /// Effective-parameter cutoff for phone-class catalog entries. Models above
    /// this number (in billions) are filtered out of every user-facing list.
    /// "Effective" means the active params per token, so MoE models are
    /// measured by what they actually compute, not by their total weight count.
    static var maxEffectiveBillion: Double { manifest.maxEffectiveBillion }

    /// All catalog entries that satisfy three hard rules:
    ///   1. they run fully on-device (`isLocalCapable`),
    ///   2. their effective active params are at most `maxEffectiveBillion`,
    ///   3. their license permits commercial App Store distribution.
    /// Every UI list that shows downloadable models must funnel through here.
    /// The license filter is defense-in-depth against a remote catalog
    /// update introducing a non-commercial entry — the bundled `models.json`
    /// is also checked at build time by `LicenseComplianceTests`.
    static var phoneCompatible: [ModelEntry] {
        all.filter {
            $0.isLocalCapable
            && $0.activeParametersBillion <= maxEffectiveBillion
            && $0.license.commercialUseAllowed
        }
    }

    static func entry(id: String) -> ModelEntry? {
        all.first { $0.id == id }
    }

    static func suggestedEntries() -> [ModelEntry] {
        let phoneIDs = Set(phoneCompatible.map(\.id))
        return suggested.compactMap { entry(id: $0) }.filter { phoneIDs.contains($0.id) }
    }

    // MARK: - Loading

    /// Filename of the cached catalog inside Application Support.
    static let cacheFilename = "catalog.json"

    /// URL the loader writes / reads from. Lives next to other Lokal app
    /// state in Application Support so it survives across launches but
    /// is wiped when the user deletes the app.
    static var cacheURL: URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return appSupport.appendingPathComponent(cacheFilename)
    }

    private static func loadManifest() -> CatalogManifest {
        let bundled = loadBundledManifest()
        let cached = loadCachedManifest()

        // Prefer cache only if its version is at least as new as the
        // bundled version. After an app update with a fresher bundled
        // catalog, this prevents an old cached snapshot from masking
        // newer entries.
        if let cached, cached.version >= bundled.version {
            return cached
        }
        return bundled
    }

    private static func loadBundledManifest() -> CatalogManifest {
        guard let url = Bundle.main.url(forResource: "models", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return .empty
        }
        do {
            return try JSONDecoder().decode(CatalogManifest.self, from: data)
        } catch {
            assertionFailure("Bundled models.json failed to decode: \(error)")
            return .empty
        }
    }

    private static func loadCachedManifest() -> CatalogManifest? {
        guard let url = cacheURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(CatalogManifest.self, from: data)
    }
}
