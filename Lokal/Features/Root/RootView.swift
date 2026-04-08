//
//  RootView.swift
//  Lokal
//

import SwiftUI

struct RootView: View {
    @Environment(ModelStore.self) private var modelStore
    @Environment(ChatStore.self) private var chatStore
    @State private var path = NavigationPath()

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
    }
}

enum Route: Hashable {
    case library
    case modelDetail(String)
}
