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
    /// against `ModelCatalog.entry(id:)`. An empty string means the user
    /// picked the "Später wählen" option in onboarding — `RootView` then
    /// drops them in the empty Library instead of auto-pushing a detail view.
    static let preferredFirstModelIDKey = "Lokal.onboarding.preferredFirstModelID"

    /// Hard-coded fallback for `preferredFirstModelIDKey`. The default is
    /// empty so the onboarding picker starts in a "Bitte wählen" state
    /// instead of silently pre-filling a model — the user has to make an
    /// explicit choice (either "Später wählen" or the featured entry).
    static let defaultFirstModelID = ""
}
