//
//  RootView.swift
//  Lokal
//

import SwiftUI

struct RootView: View {
    @Environment(ModelStore.self) private var modelStore
    @Environment(ChatStore.self) private var chatStore
    @State private var path = NavigationPath()

    /// Set when the user finished onboarding and picked a preferred first
    /// model. Used as a one-shot to push that model's detail view on top
    /// of LibraryView so the next action ("Herunterladen") is unmistakable.
    @AppStorage(OnboardingPreferences.preferredFirstModelIDKey)
    private var preferredFirstModelID: String = OnboardingPreferences.defaultFirstModelID
    @AppStorage(OnboardingPreferences.hasCompletedKey)
    private var hasCompletedOnboarding: Bool = false
    @State private var didShowPreferredFirstModel = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if modelStore.hasInstalledModels {
                    ChatView(path: $path)
                } else {
                    LibraryView(path: $path)
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .library:
                    LibraryView(path: $path)
                case .modelDetail(let id):
                    if let entry = ModelCatalog.entry(id: id) {
                        ModelDetailView(entry: entry, path: $path)
                    } else {
                        Text("Modell nicht gefunden")
                    }
                }
            }
        }
        .task(id: modelStore.activeID) {
            await chatStore.ensureEngineLoaded()
        }
        .task {
            // Wait for `LokalApp.task` to finish `modelStore.bootstrap()`
            // before deciding whether to auto-push the preferred-model
            // detail view. Without this delay we'd race the bootstrap and
            // always see "no models" on first launch even when one is
            // installed.
            try? await Task.sleep(nanoseconds: 600_000_000)
            presentPreferredFirstModelIfNeeded()
        }
        .onChange(of: hasCompletedOnboarding) { _, _ in
            presentPreferredFirstModelIfNeeded()
        }
    }

    /// One-shot: right after the user finishes onboarding, if they picked a
    /// preferred first model and they don't have any model installed yet,
    /// push that model's detail view so they see the "Herunterladen" button
    /// immediately instead of landing in an empty library wondering what
    /// to do next. The flag prevents re-pushing on every render.
    private func presentPreferredFirstModelIfNeeded() {
        guard hasCompletedOnboarding,
              !didShowPreferredFirstModel,
              !modelStore.hasInstalledModels,
              ModelCatalog.entry(id: preferredFirstModelID) != nil
        else {
            return
        }
        didShowPreferredFirstModel = true
        path.append(Route.modelDetail(preferredFirstModelID))
    }
}

enum Route: Hashable {
    case library
    case modelDetail(String)
}
