//
//  SettingsSheet.swift
//  Lokal
//

import SwiftUI

struct SettingsSheet: View {
    /// When true, the view renders its own "Fertig" toolbar button
    /// that dismisses the enclosing sheet. When false, the view is
    /// assumed to live inside a tab (the `MainTabBar` navigation
    /// container) and the dismiss button is hidden — a tab doesn't
    /// need a done button because tabs don't close.
    let showsDismiss: Bool

    init(showsDismiss: Bool = true) {
        self.showsDismiss = showsDismiss
    }

    @Environment(ChatStore.self) private var chatStore
    @Environment(ModelStore.self) private var modelStore
    @Environment(\.dismiss) private var dismiss

    // Onboarding preferences — bound here so the user can re-edit any choice
    // they made in the first-launch flow. Same UserDefaults keys as Beat 2.
    @AppStorage(OnboardingPreferences.cellularDownloadsAllowedKey)
    private var cellularAllowed: Bool = false
    @AppStorage(OnboardingPreferences.preferredFirstModelIDKey)
    private var preferredFirstModelID: String = OnboardingPreferences.defaultFirstModelID
    @AppStorage(OnboardingPreferences.hasCompletedKey)
    private var hasCompletedOnboarding: Bool = false
    @AppStorage(OnboardingPreferences.appearanceModeKey)
    private var appearanceModeRaw: String = OnboardingPreferences.defaultAppearanceMode.rawValue
    @AppStorage(OnboardingPreferences.allowBackgroundActivityKey)
    private var allowBackgroundActivity: Bool = true

    @State private var showOnboardingResetConfirm = false

    var body: some View {
        @Bindable var chat = chatStore
        NavigationStack {
            Form {
                if let active = modelStore.activeModel {
                    Section("Aktives Modell") {
                        HStack {
                            Text(active.displayName)
                            Spacer()
                            Text(String(format: "%.1f GB", active.sizeGB))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                Section("Speicher") {
                    HStack {
                        Text("Geladene Modelle")
                        Spacer()
                        Text("\(modelStore.installedModels.count)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Belegt")
                        Spacer()
                        Text(formatBytes(totalUsedBytes))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if let free = freeBytes {
                        HStack {
                            Text("Frei")
                            Spacer()
                            Text(formatBytes(free))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    NavigationLink {
                        StorageDiagnosticView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Speicherdiagnose")
                                Text("Zeigt jede Datei in Documents/models/ und erlaubt Orphan-Cleanup.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "stethoscope")
                        }
                    }
                }

                Section("Personalisierung") {
                    Toggle(isOn: $cellularAllowed) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Modelle ohne WLAN laden")
                                Text("Standardmäßig nur über WLAN — Modelle sind oft 1–4 GB.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                    }
                    Picker(selection: $preferredFirstModelID) {
                        Text("Später wählen").tag("")
                        ForEach(ModelCatalog.phoneCompatible.sorted { $0.sizeBytes < $1.sizeBytes }) { entry in
                            Text("\(entry.displayName) · \(String(format: "%.1f GB", entry.sizeGB))")
                                .tag(entry.id)
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Empfohlenes Modell")
                                Text("Wird beim ersten Start hervorgehoben.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "shippingbox")
                        }
                    }

                    Picker(selection: $appearanceModeRaw) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Erscheinungsbild")
                                Text("Wählt den Farbmodus für die gesamte App.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "circle.lefthalf.filled")
                        }
                    }
                }

                Section("Leistung") {
                    Toggle(isOn: $allowBackgroundActivity) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hintergrundaktivität erlauben")
                                Text("Wenn deaktiviert, werden Modelle beim Wechsel in den Hintergrund entladen, um Speicher freizugeben.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "moon.zzz")
                        }
                    }
                }

                Section("Erweiterungen") {
                    NavigationLink {
                        ConnectionsSettingsView()
                    } label: {
                        Label("Verbindungen", systemImage: "link")
                    }
                    NavigationLink {
                        MCPServerListView()
                    } label: {
                        Label("MCP-Server", systemImage: "bolt.horizontal")
                    }
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Generierungs-Einstellungen")
                                .font(.body)
                            Text("Temperatur, System Prompt und weitere Parameter findest du direkt im jeweiligen Chat — tippe oben rechts auf das Zahnrad-Symbol.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "text.bubble")
                    }
                } header: {
                    Text("Pro-Chat-Einstellungen")
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("Über Lokalo", systemImage: "info.circle")
                    }
                    NavigationLink {
                        LicensesView()
                    } label: {
                        Label("Lizenzen", systemImage: "doc.text")
                    }
                    Button {
                        showOnboardingResetConfirm = true
                    } label: {
                        Label("Onboarding erneut anzeigen", systemImage: "sparkles")
                    }
                    .tint(.primary)
                }

                Section {
                    Text("Lokalo · On-device AI. Inferenz läuft auf deinem iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .lokaloThemedBackground()
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDismiss {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fertig") {
                            dismiss()
                        }
                    }
                }
            }
            .confirmationDialog("Onboarding erneut anzeigen?",
                                isPresented: $showOnboardingResetConfirm,
                                titleVisibility: .visible) {
                Button("Anzeigen") {
                    hasCompletedOnboarding = false
                    dismiss()
                }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Beim nächsten Schließen der Einstellungen wird wieder die Begrüßung angezeigt.")
            }
        }
    }

    private var totalUsedBytes: Int64 {
        modelStore.installedModels.reduce(0) { $0 + $1.sizeBytes }
    }

    private var freeBytes: Int64? {
        let url = ModelStore.modelsDirectory()
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let v = values.volumeAvailableCapacityForImportantUsage {
            return v
        }
        return nil
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
