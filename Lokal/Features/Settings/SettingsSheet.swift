//
//  SettingsSheet.swift
//  Lokal
//

import SwiftUI

struct SettingsSheet: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(ModelStore.self) private var modelStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var chat = chatStore
        NavigationStack {
            Form {
                Section("Sampling") {
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
                }

                Section("System Prompt") {
                    TextEditor(text: $chat.systemPrompt)
                        .frame(minHeight: 96)
                        .font(.callout)
                }

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
                }

                Section {
                    Text("Lokalo · On-device AI. Nichts verlässt dein iPhone.")
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
