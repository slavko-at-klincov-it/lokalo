//
//  DarkBlueGradient.swift
//  Lokal
//
//  Central visual identity: the Lokalo dark-blue LinearGradient,
//  previously hardcoded inline in Beat 1, Beat 2, OnboardingFlow,
//  and the ChatEmptyState. Lives here so every screen references
//  a single source of truth — change the colours once, they update
//  everywhere.
//
//  Ships with an `AppearanceMode` enum (dark / light) and a
//  `.lokaloThemedBackground()` ViewModifier that applies the gradient
//  only in dark mode (via `@Environment(\.colorScheme)`) and simultaneously
//  hides iOS's default scroll-content background so List and Form
//  views show the gradient through. In light mode the modifier is a
//  no-op and iOS's native Form/List styling is preserved.
//

import SwiftUI

// MARK: - AppearanceMode

/// User-selectable theme for the whole app. Only two cases on
/// purpose — the user explicitly asked not to expose a "System"
/// option, they want a deliberate choice.
enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case dark
    case light

    var id: String { rawValue }

    var colorScheme: ColorScheme {
        switch self {
        case .dark:  return .dark
        case .light: return .light
        }
    }

    /// German label used in both the Beat 2 theme card and the
    /// Settings picker. Short, uppercase-friendly.
    var label: String {
        switch self {
        case .dark:  return "Dunkel"
        case .light: return "Hell"
        }
    }

    /// SF Symbol shown in the Beat 2 theme-card preview capsules.
    var iconName: String {
        switch self {
        case .dark:  return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }
}

// MARK: - DarkBlueGradient

/// The Lokalo signature background: a dark-blue vertical gradient
/// from near-black to a deeper blue and back to near-black. Used
/// throughout the dark-mode experience — onboarding beats, chat
/// empty state, and every top-level tab content view via the
/// `.lokaloThemedBackground()` modifier.
struct DarkBlueGradient: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.02, green: 0.04, blue: 0.10),
                Color(red: 0.04, green: 0.06, blue: 0.16),
                Color(red: 0.01, green: 0.02, blue: 0.06)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// The light-mode counterpart to `DarkBlueGradient`. A very subtle
/// white-to-near-white gradient that gives the onboarding screens
/// the same layered depth feeling in light mode as the dark
/// gradient does in dark mode, without being obtrusive. Used by
/// `Beat2EinstellungenView` and any other onboarding view that
/// paints a background explicitly instead of relying on the
/// `.lokaloThemedBackground()` modifier.
struct LightBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(white: 1.00),
                Color(white: 0.97),
                Color(white: 0.99)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// Theme-aware background for views that paint their own background
/// explicitly in an inner ZStack (e.g. the onboarding beats, which
/// don't use `.lokaloThemedBackground()` because they're not
/// scroll-container based). Reads `colorScheme` and picks either
/// the dark-blue or the light gradient.
struct ThemedOnboardingBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            DarkBlueGradient()
        } else {
            LightBackground()
        }
    }
}

// MARK: - LokaloThemedBackground modifier

/// View modifier that makes any screen's root container theme-aware.
///
/// In dark mode:
///   - `scrollContentBackground(.hidden)` so List/Form views don't
///     paint their own default (grey) background over the gradient.
///   - A `DarkBlueGradient()` is layered behind the content via
///     `.background { ... }`.
///
/// In light mode both effects are no-ops — `scrollContentBackground`
/// falls back to `.automatic` and no extra background is drawn —
/// so the native iOS look is preserved exactly as it was before.
///
/// Call this on the root container of every top-level view (List,
/// Form, ScrollView) that should participate in the themed
/// experience. Safe to apply to views that aren't scroll containers
/// too — the `.scrollContentBackground` modifier on a non-scrollable
/// view is a harmless no-op.
struct LokaloThemedBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(colorScheme == .dark ? .hidden : .automatic)
            .background {
                if colorScheme == .dark {
                    DarkBlueGradient()
                }
            }
    }
}

extension View {
    /// Applies the Lokalo dark-blue gradient background in dark mode
    /// and hides the default List/Form scroll-content background so
    /// the gradient shows through. In light mode the modifier is a
    /// no-op and the native iOS look is preserved.
    func lokaloThemedBackground() -> some View {
        modifier(LokaloThemedBackground())
    }
}
