//
//  OnboardingPreferences.swift
//  Lokalo
//
//  Single source of truth for the UserDefaults keys touched by the
//  first-launch onboarding flow. Both the OnboardingFlow itself and the
//  Settings sheet (where the user can re-edit any of these) should read
//  and write through these constants — never via raw string literals.
//

import Foundation

enum OnboardingPreferences {
    /// Set to `true` once the user has tapped "Loslegen" in Beat 2.
    static let hasCompletedKey = "Lokal.hasCompletedOnboarding"

    /// Allow large model downloads over cellular. Default `false` → WLAN-only.
    static let cellularDownloadsAllowedKey = "Lokal.onboarding.cellularDownloadsAllowed"

    /// The model the user picked as the suggested-first-model. Lookup happens
    /// against `ModelCatalog.entry(id:)`. Default falls back to the smallest
    /// Qwen if the chosen ID has been removed from the catalog.
    static let preferredFirstModelIDKey = "Lokal.onboarding.preferredFirstModelID"

    /// Hard-coded fallback for `preferredFirstModelIDKey`. Matches the smallest
    /// model in the bundled catalog (~380 MB Q4_K_M).
    static let defaultFirstModelID = "qwen-2.5-0.5b-instruct-q4km"
}
