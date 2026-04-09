//
//  SettingsSheet.swift
//  Lokal
//

import SwiftUI

struct SettingsSheet: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(ModelStore.self) private var modelStore
    @Environment(\.dismiss) private var dismiss

    // Onboarding preferences — bound here so the user can re-edit any choice
    // they made in the first-launch flow. Same UserDefaults keys as Beat 2.
    @AppStorage(OnboardingPreferences.microphoneIntentKey)
    private var microphoneIntent: Bool = false
    @AppStorage(OnboardingPreferences.notificationsIntentKey)
    private var notificationsIntent: Bool = false
    @AppStorage(OnboardingPreferences.cellularDownloadsAllowedKey)
    private var cellularAllowed: Bool = false
    @AppStorage(OnboardingPreferences.preferredFirstModelIDKey)
    private var preferredFirstModelID: String = OnboardingPreferences.defaultFirstModelID
    @AppStorage(OnboardingPreferences.hasCompletedKey)
    private var hasCompletedOnboarding: Bool = false

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
                }

                Section("Personalisierung") {
                    Toggle(isOn: $microphoneIntent) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Mikrofon")
                                Text("Sprich mit dem Modell, statt zu tippen.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "mic")
                        }
                    }
                    Toggle(isOn: $notificationsIntent) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Benachrichtigungen")
                                Text("Lokalo meldet sich, wenn eine längere Antwort fertig ist.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "bell")
                        }
                    }
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

                Section("Erweitert") {
                    sliderRow(label: "Temperatur",
                              value: Binding(
                                get: { Double(chat.settings.temperature) },
                                set: { chat.settings.temperature = Float($0) }),
                              range: 0.0...2.0,
                              format: "%.2f")
                    sliderRow(label: "Top-p",
                              value: Binding(
                                get: { Double(chat.settings.topP) },
                                set: { chat.settings.topP = Float($0) }),
                              range: 0.05...1.0,
                              format: "%.2f")
                    sliderRow(label: "Min-p",
                              value: Binding(
                                get: { Double(chat.settings.minP) },
                                set: { chat.settings.minP = Float($0) }),
                              range: 0.0...0.5,
                              format: "%.2f")
                    Stepper(value: Binding(
                        get: { chat.settings.maxNewTokens },
                        set: { chat.settings.maxNewTokens = $0 }),
                            in: 32...2048, step: 32) {
                        HStack {
                            Text("Max. Token")
                            Spacer()
                            Text("\(chat.settings.maxNewTokens)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    NavigationLink {
                        Form {
                            TextEditor(text: $chat.systemPrompt)
                                .frame(minHeight: 200)
                                .font(.callout)
                        }
                        .navigationTitle("System Prompt")
                    } label: {
                        Label("System Prompt", systemImage: "text.bubble")
                    }
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
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") {
                        chatStore.settings = chat.settings
                        Task { await chatStore.ensureEngineLoaded() }
                        dismiss()
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

    private func sliderRow(label: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
                .tint(.accentColor)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
