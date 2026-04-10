//
//  ChatSettingsSheet.swift
//  Lokal
//
//  Per-chat settings sheet — reached via the gear icon in the top bar of
//  `ChatView`. Everything in this sheet mutates the **active session only**.
//  For app-wide defaults (storage, theme, OAuth, MCP, …) see the dedicated
//  "Einstellungen" tab in `MainTabBar`.
//

import SwiftUI

struct ChatSettingsSheet: View {

    @Environment(ChatStore.self) private var chatStore
    @Environment(ChatSessionStore.self) private var sessionStore
    @Environment(KnowledgeBaseStore.self) private var kbStore
    @Environment(\.dismiss) private var dismiss

    @State private var showClearHistoryConfirm = false
    @State private var showDeleteChatConfirm = false

    var body: some View {
        @Bindable var chat = chatStore
        NavigationStack {
            Form {
                titleSection
                purposeSection(chat: $chat)
                knowledgeBaseSection
                samplingSection(chat: $chat)
                dangerSection
                footerSection
            }
            .lokaloThemedBackground()
            .navigationTitle("Chat-Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
            .confirmationDialog(
                "Verlauf dieses Chats leeren?",
                isPresented: $showClearHistoryConfirm,
                titleVisibility: .visible
            ) {
                Button("Verlauf leeren", role: .destructive) {
                    chatStore.clearConversation()
                }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Alle Nachrichten werden entfernt, der Chat selbst bleibt bestehen.")
            }
            .confirmationDialog(
                "Diesen Chat komplett löschen?",
                isPresented: $showDeleteChatConfirm,
                titleVisibility: .visible
            ) {
                Button("Chat löschen", role: .destructive) {
                    if let id = sessionStore.activeSessionID {
                        sessionStore.delete(id)
                        dismiss()
                    }
                }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Der gesamte Verlauf und die Einstellungen dieses Chats werden entfernt.")
            }
        }
    }

    // MARK: - Sections

    private var titleSection: some View {
        Section {
            TextField(
                "Titel (automatisch)",
                text: Binding(
                    get: { sessionStore.activeSession?.title ?? "" },
                    set: { newValue in
                        guard var session = sessionStore.activeSession else { return }
                        session.title = newValue
                        sessionStore.updateMeta(session)
                    }
                )
            )
            .textInputAutocapitalization(.sentences)
        } header: {
            Text("Titel")
        } footer: {
            Text("Leer lassen → automatischer Titel aus der ersten Nachricht.")
        }
    }

    @ViewBuilder
    private func purposeSection(chat: Bindable<ChatStore>) -> some View {
        Section {
            Picker(
                "Zweck",
                selection: Binding(
                    get: { sessionStore.activeSession?.systemPromptPreset ?? .lokaloDefault },
                    set: { newPreset in
                        guard var session = sessionStore.activeSession else { return }
                        session.systemPromptPreset = newPreset
                        // Only overwrite prompt text when switching away
                        // from `.custom` — user edits on `.custom` are kept.
                        if newPreset != .custom {
                            session.systemPromptText = newPreset.defaultText
                            if let suggested = newPreset.suggestedSettings {
                                session.settings = suggested
                            }
                        }
                        sessionStore.updateMeta(session)
                    }
                )
            ) {
                ForEach(SystemPromptPreset.allCases, id: \.self) { preset in
                    Label(preset.displayName, systemImage: preset.symbolName)
                        .tag(preset)
                }
            }
            .pickerStyle(.navigationLink)

            NavigationLink {
                Form {
                    TextEditor(text: chat.wrappedValue.binding(for: \.systemPrompt))
                        .frame(minHeight: 240)
                        .font(.callout)
                } // inner Form closes
                .navigationTitle("System Prompt")
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("System Prompt bearbeiten", systemImage: "text.bubble")
            }
        } header: {
            Text("Zweck & System Prompt")
        } footer: {
            Text("Ein Zweck setzt passende Temperatur und einen Start-Prompt. Eigene Änderungen am Text kippen den Zweck auf „Benutzerdefiniert“.")
        }
    }

    private var knowledgeBaseSection: some View {
        Section {
            Picker(
                "Wissensbasis",
                selection: Binding<UUID?>(
                    get: { sessionStore.activeSession?.knowledgeBaseID },
                    set: { newID in
                        guard var session = sessionStore.activeSession else { return }
                        session.knowledgeBaseID = newID
                        sessionStore.updateMeta(session)
                    }
                )
            ) {
                Text("Keine").tag(UUID?.none)
                ForEach(kbStore.bases, id: \.id) { base in
                    Text(base.name).tag(UUID?.some(base.id))
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text("Wissen")
        } footer: {
            Text("RAG-Quellen werden nur verwendet, wenn hier eine Wissensbasis gewählt ist.")
        }
    }

    @ViewBuilder
    private func samplingSection(chat: Bindable<ChatStore>) -> some View {
        Section {
            sliderRow(
                label: "Temperatur",
                value: Binding(
                    get: { Double(chat.wrappedValue.settings.temperature) },
                    set: { chat.wrappedValue.settings.temperature = Float($0) }
                ),
                range: 0.0...2.0,
                format: "%.2f"
            )
            sliderRow(
                label: "Top-p",
                value: Binding(
                    get: { Double(chat.wrappedValue.settings.topP) },
                    set: { chat.wrappedValue.settings.topP = Float($0) }
                ),
                range: 0.05...1.0,
                format: "%.2f"
            )
            sliderRow(
                label: "Min-p",
                value: Binding(
                    get: { Double(chat.wrappedValue.settings.minP) },
                    set: { chat.wrappedValue.settings.minP = Float($0) }
                ),
                range: 0.0...0.5,
                format: "%.2f"
            )
            Stepper(
                value: Binding(
                    get: { chat.wrappedValue.settings.maxNewTokens },
                    set: { chat.wrappedValue.settings.maxNewTokens = $0 }
                ),
                in: 32...2048,
                step: 32
            ) {
                HStack {
                    Text("Max. Token")
                    Spacer()
                    Text("\(chat.wrappedValue.settings.maxNewTokens)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Generierung")
        } footer: {
            Text("Werte gelten nur für diesen Chat.")
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showClearHistoryConfirm = true
            } label: {
                Label("Verlauf leeren", systemImage: "eraser")
            }
            .disabled(chatStore.messages.isEmpty)

            Button(role: .destructive) {
                showDeleteChatConfirm = true
            } label: {
                Label("Chat löschen", systemImage: "trash")
            }
            .disabled(sessionStore.sessions.count <= 1)
        } header: {
            Text("Chat verwalten")
        } footer: {
            if sessionStore.sessions.count <= 1 {
                Text("Der letzte Chat kann nicht gelöscht werden.")
            }
        }
    }

    private var footerSection: some View {
        Section {
            Text("Globale App-Einstellungen findest du im Tab „Einstellungen“ unten.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Helpers

    private func sliderRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
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
}

// MARK: - Binding helper

private extension ChatStore {
    /// Writable binding for a read/write key-path on an @Observable class,
    /// so TextEditor can bind to `chat.systemPrompt` as an lvalue without
    /// the `@Bindable` macro complaining about computed properties.
    func binding<T>(for keyPath: ReferenceWritableKeyPath<ChatStore, T>) -> Binding<T> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { self[keyPath: keyPath] = $0 }
        )
    }
}
