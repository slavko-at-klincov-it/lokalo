//
//  ChatView.swift
//  Lokal
//

import SwiftUI

struct ChatView: View {
    @Environment(ModelStore.self) private var modelStore
    @Environment(ChatStore.self) private var chatStore
    @Binding var path: NavigationPath
    @State private var input: String = ""
    @State private var showSettings = false
    @State private var showModelPicker = false
    @State private var showNewChatConfirm = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        @Bindable var chat = chatStore
        ZStack(alignment: .bottom) {
            messageList
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) { composer }
            if case .loading = chatStore.loadState {
                loadingBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showNewChatConfirm = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .disabled(chatStore.messages.isEmpty)
            }
            ToolbarItem(placement: .principal) {
                Button {
                    showModelPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(modelStore.activeModel?.displayName ?? "Lokalo")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheet(path: $path)
        }
        .confirmationDialog("Neue Unterhaltung beginnen?",
                            isPresented: $showNewChatConfirm,
                            titleVisibility: .visible) {
            Button("Verlauf löschen", role: .destructive) {
                chatStore.clearConversation()
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Der aktuelle Verlauf wird verworfen.")
        }
        .task(id: modelStore.activeID) {
            await chatStore.ensureEngineLoaded()
        }
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-LokalAutoOpenSettings") { showSettings = true }
            if args.contains("-LokalAutoOpenPicker") { showModelPicker = true }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if chatStore.messages.isEmpty && !chatStore.isStreaming {
                        emptyChatState
                            .padding(.top, 80)
                    } else {
                        ForEach(chatStore.messages) { message in
                            MessageBubble(message: message, isStreaming: false)
                                .id(message.id)
                        }
                        if chatStore.isStreaming {
                            // Live streaming bubble — its own ChatMessage so the
                            // ForEach above doesn't have to be invalidated each token.
                            MessageBubble(
                                message: ChatMessage(role: .assistant, content: chatStore.streamingBuffer),
                                isStreaming: true
                            )
                            .id("STREAMING")
                        }
                    }
                    Color.clear.frame(height: 1).id("BOTTOM")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .onChange(of: chatStore.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("BOTTOM", anchor: .bottom)
                }
            }
            .onChange(of: chatStore.streamingBuffer) { _, _ in
                proxy.scrollTo("BOTTOM", anchor: .bottom)
            }
        }
    }

    private var emptyChatState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Stell deine erste Frage")
                .font(.title3.weight(.semibold))
            Text("Modell läuft komplett offline auf deinem iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Nachricht eingeben…", text: $input, axis: .vertical)
                .lineLimit(1...6)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color(uiColor: .separator), lineWidth: 0.5)
                )
                .submitLabel(.send)
                .onSubmit { trySend() }

            Button(action: chatStore.isStreaming ? stop : trySend) {
                Image(systemName: chatStore.isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(sendEnabled ? Color.accentColor : Color.gray.opacity(0.4))
                    )
            }
            .disabled(!sendEnabled && !chatStore.isStreaming)
            .animation(.easeInOut(duration: 0.15), value: sendEnabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var sendEnabled: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chatStore.canSend
    }

    private var loadingBanner: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Modell wird geladen…")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .frame(maxWidth: .infinity)
    }

    private func trySend() {
        guard sendEnabled else { return }
        let text = input
        FileLog.write("trySend: input.count=\(text.count) chars, focused=\(inputFocused)")
        inputFocused = false
        input = ""
        FileLog.write("trySend: cleared, input=\"\(input)\"")
        chatStore.send(text)
        DispatchQueue.main.async {
            self.inputFocused = true
            FileLog.write("trySend: refocused, input=\"\(self.input)\"")
        }
    }

    private func stop() {
        chatStore.cancelStreaming()
    }
}

#Preview {
    NavigationStack {
        ChatView(path: .constant(NavigationPath()))
            .environment(ModelStore())
            .environment(ChatStore())
    }
}
