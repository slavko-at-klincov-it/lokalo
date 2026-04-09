//
//  ModelLicense.swift
//  Lokal
//
//  Typed catalog of model licenses + commercial-use compliance.
//
//  Apple App Store distribution requires every shipped (or downloadable-via-
//  catalog) model to permit commercial redistribution. This enum is the
//  single source of truth for that decision: every license that appears in
//  `models.json` must map to one of the cases below, and only cases where
//  `commercialUseAllowed == true` are allowed to surface in the user-facing
//  catalog.
//
//  Two safety nets enforce this:
//    1. `ModelCatalog.phoneCompatible` filters out any entry with a
//       non-commercial license at load time. This protects users from a
//       remote catalog update that introduces a bad entry.
//    2. `LicenseComplianceTests` asserts the bundled `models.json` contains
//       zero non-commercial entries. This breaks the build before a bad
//       entry can ship.
//
//  Unknown license strings fall through to `.other(rawString)` which is
//  treated as non-commercial — conservative by design. If you add a new
//  model with a license not yet in this enum, the test will fail and you
//  must either add the new case here (and document the commercial-use
//  decision) or replace the model.
//

import Foundation

/// Typed wrapper around the `licenseLabel` string in `models.json`.
enum ModelLicense: Hashable, Sendable {
    case apache2_0
    case mit
    case bsd3Clause
    /// Meta's Llama Community License (covers 2.x and 3.x). Permits
    /// commercial use with attribution + a 700M MAU restriction.
    case llamaCommunity
    /// Google's Gemma Terms of Use. Permits commercial redistribution
    /// subject to the Acceptable Use Policy.
    case gemmaTerms
    /// Alibaba's Qianwen License (commercial OK; >100M MAU notification).
    case qianwenLicense
    /// Alibaba's Qianwen Research License — RESEARCH ONLY, no commercial
    /// redistribution. Models under this license cannot ship in the App
    /// Store catalog.
    case qwenResearch
    case cc_by_4_0
    case cc_by_sa_4_0
    /// CC BY-NC variants — non-commercial.
    case cc_by_nc
    /// Catch-all for licenses we haven't classified yet. Conservative
    /// default: blocked from commercial distribution.
    case other(String)

    /// Whether App Store distribution is permitted under this license.
    /// `false` means the model must NOT appear in the user-facing catalog.
    var commercialUseAllowed: Bool {
        switch self {
        case .apache2_0, .mit, .bsd3Clause,
             .llamaCommunity, .gemmaTerms, .qianwenLicense,
             .cc_by_4_0, .cc_by_sa_4_0:
            return true
        case .qwenResearch, .cc_by_nc:
            return false
        case .other:
            return false
        }
    }

    /// Human-readable label for the Settings → Lizenzen screen and the
    /// model detail page.
    var displayLabel: String {
        switch self {
        case .apache2_0:      return "Apache 2.0"
        case .mit:            return "MIT"
        case .bsd3Clause:     return "BSD-3-Clause"
        case .llamaCommunity: return "Llama Community"
        case .gemmaTerms:     return "Gemma Terms of Use"
        case .qianwenLicense: return "Qianwen License"
        case .qwenResearch:   return "Qwen Research License"
        case .cc_by_4_0:      return "CC BY 4.0"
        case .cc_by_sa_4_0:   return "CC BY-SA 4.0"
        case .cc_by_nc:       return "CC BY-NC"
        case .other(let raw): return raw
        }
    }

    /// Maps a `licenseLabel` string from `models.json` to a typed case.
    /// Matching is case-insensitive and whitespace-tolerant. Aliases for
    /// the same license (e.g. "Apache 2.0" / "Apache-2.0") all collapse
    /// to the same case so the JSON author can use whichever spelling
    /// they prefer.
    init(rawLabel: String) {
        let key = rawLabel
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch key {
        case "apache 2.0", "apache-2.0", "apache2.0", "apache 2", "apache-2":
            self = .apache2_0
        case "mit", "mit license", "mit-license":
            self = .mit
        case "bsd-3-clause", "bsd 3-clause", "bsd3", "bsd-3":
            self = .bsd3Clause
        case "llama community", "llama 2 community", "llama2 community",
             "llama 3 community", "llama 3.0 community",
             "llama 3.1 community", "llama 3.2 community",
             "llama3 community", "llama3.1 community", "llama3.2 community":
            self = .llamaCommunity
        case "gemma terms", "gemma terms of use",
             "google gemma terms", "google gemma terms of use":
            self = .gemmaTerms
        case "qianwen", "qianwen license", "tongyi qianwen license":
            self = .qianwenLicense
        case "qwen research", "qwen research license",
             "qianwen research license", "tongyi qianwen research license":
            self = .qwenResearch
        case "cc by 4.0", "cc-by-4.0", "cc by 4", "creative commons by 4.0":
            self = .cc_by_4_0
        case "cc by-sa 4.0", "cc-by-sa-4.0", "creative commons by-sa 4.0":
            self = .cc_by_sa_4_0
        case "cc by-nc", "cc-by-nc",
             "cc by-nc 4.0", "cc-by-nc-4.0",
             "cc by-nc-sa", "cc-by-nc-sa":
            self = .cc_by_nc
        default:
            self = .other(rawLabel)
        }
    }
}

extension ModelLicense: Codable {
    /// Encodes / decodes as a single string. The decoder runs through
    /// `init(rawLabel:)` so the JSON file can keep using human-readable
    /// labels like "Apache 2.0" without exposing the enum case names.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ModelLicense(rawLabel: raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(displayLabel)
    }
}
