//
//  ChatView.swift
//  Lokal
//

import SwiftUI

struct ChatView: View {
    @Environment(ModelStore.self) private var modelStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(ChatSessionStore.self) private var sessionStore
    @Environment(KnowledgeBaseStore.self) private var kbStore
    @Binding var path: NavigationPath
    @State private var input: String = ""
    @State private var showChatSettings = false
    @State private var showModelPicker = false
    @State private var showKnowledge = false
    @State private var showChatDrawer = false
    @State private var showMultiChatHint = false
    @FocusState private var inputFocused: Bool

    @AppStorage(Self.multiChatHintSeenKey) private var multiChatHintSeen: Bool = false

    var body: some View {
        @Bindable var chat = chatStore
        // VStack(spacing: 0) so the composer sits directly below the
        // scroll view with no gap, and the composer is in the view
        // hierarchy OUTSIDE any scroll view — that way it respects
        // the outer `MainTabBar` safe-area inset installed on
        // `RootView`, and will never land *behind* the tab bar.
        //
        // The status banner is overlaid at the top via `.overlay`
        // so it floats above the scroll content like a toast
        // instead of competing with the composer for the bottom
        // of a `ZStack(alignment: .bottom)`.
        VStack(spacing: 0) {
            messageList
                .scrollDismissesKeyboard(.interactively)
                // Tap on an empty area of the message list (or on
                // a message bubble — they don't consume taps) while
                // the composer is focused dismisses the keyboard.
                // `simultaneousGesture` so normal scroll gestures
                // keep working — the tap only fires on a touch that
                // never moves. The `guard inputFocused` avoids
                // swallowing interactions when the keyboard is
                // already down.
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if inputFocused { inputFocused = false }
                    }
                )
            composer
        }
        .overlay(alignment: .top) {
            if let banner = chatStore.statusBanner {
                statusBanner(text: banner)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            // Slide-in chat drawer. Lives on the `ChatView` level so it
            // stays inside the Chat tab; the MainTabBar remains visible
            // and interactive below the drawer, matching the
            // Poe/LM-Studio pattern.
            chatDrawerOverlay
        }
        .overlay {
            // Center card shown when the active session's model does
            // not match the currently loaded one. Composer is disabled
            // via `chatStore.canSend` while this is visible.
            if let pending = chatStore.pendingModelSwitch, !chatStore.isSwitchingModel {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    PendingModelSwitchCard(targetModelID: pending)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: chatStore.pendingModelSwitch)
        .animation(.easeInOut(duration: 0.25), value: showMultiChatHint)
        .task {
            // Show the multi-chat tooltip once, ~600 ms after the chat tab
            // first appears, then auto-dismiss after 5 s. The flag is set
            // the first time the user actually taps the drawer button.
            guard !multiChatHintSeen, !showMultiChatHint else { return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            showMultiChatHint = true
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if showMultiChatHint {
                showMultiChatHint = false
            }
        }
        .overlay(alignment: .leading) {
            // Invisible edge-swipe strip that opens the drawer when the
            // user drags from the left edge of the chat content. 20pt
            // wide, active only when we're on the stack root and the
            // drawer isn't already showing, so the NavigationStack's
            // own interactive-pop gesture keeps working on child views.
            if path.isEmpty && !showChatDrawer {
                Color.clear
                    .frame(width: 20)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(edgeSwipeGesture)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // Floating chip bar. `safeAreaInset` pushes the scroll
            // content below this view but lets it *scroll through* the
            // inset region, so old messages remain visible behind the
            // chips as the user scrolls up — matching the native iOS
            // "content under the navigation bar" behaviour.
            customTopBar
        }
        .modelSwitchOverlay()
        .navigationBarHidden(true)
        .sheet(isPresented: $showChatSettings) {
            ChatSettingsSheet()
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheet(path: $path)
        }
        .sheet(isPresented: $showKnowledge) {
            KnowledgeView()
        }
        .task(id: modelStore.activeID) {
            if let id = modelStore.activeID {
                // Self-heal: if the user installed their first model AFTER
                // the app-launch bootstrap ran (common on fresh installs —
                // onboarding → pick model → chat tab), no default session
                // exists yet. Seed one now so `send()` isn't rejected with
                // "no active session".
                if sessionStore.sessions.isEmpty {
                    sessionStore.seedDefaultSessionIfEmpty(
                        modelID: id,
                        knowledgeBaseID: kbStore.ragEnabled ? kbStore.activeBaseID : nil
                    )
                }
                await chatStore.switchTo(modelID: id)
            } else {
                await chatStore.ensureEngineLoaded()
            }
        }
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-LokalAutoOpenSettings") { showChatSettings = true }
            if args.contains("-LokalAutoOpenPicker") { showModelPicker = true }
        }
    }

    /// Custom top bar — replaces the standard SwiftUI `.toolbar` so we can
    /// stack the leading and trailing icon pairs vertically. Each icon keeps
    /// its own circular `.ultraThinMaterial` chip (matching the standard
    /// iOS 26 toolbar button look), but the bar itself has no background so
    /// the chat surface shows through between the chips.
    private var customTopBar: some View {
        HStack(alignment: .center, spacing: 12) {
            // Leading: drawer + new chat (vertical stack of individual chips)
            VStack(spacing: 10) {
                topBarIconButton(
                    systemName: "sidebar.left",
                    accessibilityLabel: "Chat-Liste",
                    accessibilityHint: "Öffnet die Liste aller Unterhaltungen."
                ) {
                    inputFocused = false
                    ChatHaptics.drawerOpen()
                    withAnimation(.interpolatingSpring(stiffness: 380, damping: 32)) {
                        showChatDrawer = true
                    }
                    multiChatHintSeen = true
                    showMultiChatHint = false
                }

                topBarIconButton(
                    systemName: "square.and.pencil",
                    accessibilityLabel: "Neue Unterhaltung",
                    accessibilityHint: "Legt einen neuen leeren Chat an."
                ) {
                    createNewChat()
                }
            }
            .overlay(alignment: .topLeading) {
                // First-run tooltip — relative to the leading VStack so the
                // anchor is always directly under the drawer button regardless
                // of the device or safe-area inset height.
                if showMultiChatHint {
                    multiChatHintBubble
                        .fixedSize()
                        .offset(x: -2, y: 105)
                        .transition(.opacity)
                }
            }

            Spacer(minLength: 4)

            // Center: model picker as its own capsule chip, vertically
            // centered between the two icon stacks. Matches the icon
            // chips — ultra-thin material fill, hairline stroke overlay,
            // gentle shadow for depth.
            Button {
                showModelPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(modelStore.activeModel?.displayName ?? "Lokalo")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.18), radius: 7, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Modell wechseln")
            .accessibilityValue(modelStore.activeModel?.displayName ?? "Kein Modell")
            .accessibilityHint("Öffnet die Modell-Auswahl.")

            Spacer(minLength: 4)

            // Trailing: knowledge + settings (vertical stack of individual chips)
            VStack(spacing: 10) {
                topBarIconButton(
                    systemName: ragIndicator,
                    accessibilityLabel: "Wissensbasen",
                    accessibilityHint: "Verwaltet Quellen und RAG-Einstellungen."
                ) {
                    showKnowledge = true
                }

                topBarIconButton(
                    systemName: "gearshape",
                    accessibilityLabel: "Chat-Einstellungen",
                    accessibilityHint: "Einstellungen nur für diesen Chat."
                ) {
                    showChatSettings = true
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// First-launch tooltip pointing at the drawer button. Visual style
    /// matches the chip-bar aesthetic — ultra-thin material capsule with a
    /// hairline stroke and subtle shadow, plus a small triangle anchor.
    private var multiChatHintBubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Anchor triangle pointing at the drawer button.
            Triangle()
                .fill(.ultraThinMaterial)
                .frame(width: 14, height: 8)
                .padding(.leading, 6)

            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Neu: mehrere Chats mit verschiedenen Modellen.")
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)
            .frame(maxWidth: 240)
        }
        .onTapGesture {
            multiChatHintSeen = true
            showMultiChatHint = false
        }
    }

    /// A single circular chip that matches the stock iOS 26 toolbar-button
    /// look: ultra-thin material fill, hairline stroke for edge definition,
    /// gentle shadow for depth. 46pt diameter — comfortably above Apple's
    /// 44pt minimum tap target and visually prominent enough to anchor the
    /// top bar without feeling heavy.
    @ViewBuilder
    private func topBarIconButton(
        systemName: String,
        accessibilityLabel: String,
        accessibilityHint: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.18), radius: 7, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .modifier(OptionalAccessibilityHintModifier(hint: accessibilityHint))
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
            .accessibilityLabel(chatStore.isStreaming ? "Antwort stoppen" : "Nachricht senden")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var sendEnabled: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chatStore.canSend
    }

    private func statusBanner(text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial)
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

    /// Create a fresh chat session pointing at the currently loaded model
    /// (or, if nothing is loaded yet, the model the current session already
    /// uses as a fallback) and switch to it. Non-destructive — the old
    /// session stays around in the drawer.
    private func createNewChat() {
        inputFocused = false
        let seedModelID = modelStore.activeID
            ?? sessionStore.activeSession?.chatModelID
            ?? ""
        guard !seedModelID.isEmpty else {
            // No model to point the new chat at — the drawer / picker will
            // take over. This matches the fresh-install edge case where the
            // user hasn't picked a model yet.
            return
        }
        let newSession = sessionStore.create(
            modelID: seedModelID,
            preset: .lokaloDefault,
            knowledgeBaseID: sessionStore.activeSession?.knowledgeBaseID
        )
        sessionStore.setActive(newSession.id)
    }

    private var ragIndicator: String {
        if let active = kbStore.activeBase, !active.sources.isEmpty, kbStore.ragEnabled {
            return "books.vertical.fill"
        }
        return "books.vertical"
    }

    // MARK: - Chat drawer overlay

    /// Width used for the drawer panel — 82 % of the screen, capped at
    /// 340pt on larger devices. A touch of content from ChatView stays
    /// visible on the right so the user sees what they came from.
    private var drawerWidth: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        return min(340, screenWidth * 0.82)
    }

    @ViewBuilder
    private var chatDrawerOverlay: some View {
        if showChatDrawer {
            ZStack(alignment: .leading) {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closeDrawer()
                    }
                    .transition(.opacity)

                ChatDrawerView(
                    isPresented: $showChatDrawer,
                    onCreateNew: {
                        closeDrawerAndCreateNewChat()
                    }
                )
                .frame(width: drawerWidth)
                .frame(maxHeight: .infinity)
                .transition(.move(edge: .leading))
            }
        }
    }

    /// Drag from the left edge to open the drawer. Triggers once the user
    /// has dragged more than 30pt to the right.
    private var edgeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onEnded { value in
                guard value.translation.width > 30,
                      abs(value.translation.height) < value.translation.width else { return }
                inputFocused = false
                ChatHaptics.drawerOpen()
                withAnimation(.interpolatingSpring(stiffness: 380, damping: 32)) {
                    showChatDrawer = true
                }
                multiChatHintSeen = true
                showMultiChatHint = false
            }
    }

    private func closeDrawer() {
        ChatHaptics.drawerClose()
        withAnimation(.interpolatingSpring(stiffness: 380, damping: 32)) {
            showChatDrawer = false
        }
    }

    private func closeDrawerAndCreateNewChat() {
        ChatHaptics.drawerClose()
        withAnimation(.interpolatingSpring(stiffness: 380, damping: 32)) {
            showChatDrawer = false
        }
        // Defer the create call so the drawer close animation finishes
        // before the new session's empty state renders.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.createNewChat()
        }
    }

    // MARK: - First-run tooltip

    /// UserDefaults flag — set to `true` the first time the user opens the
    /// drawer. While unset, a small tooltip bubble appears next to the
    /// drawer button on launch to advertise the multi-chat feature.
    fileprivate static let multiChatHintSeenKey = "Lokal.multiChatHintSeen"
}

// Tiny helper so `topBarIconButton` can skip the `.accessibilityHint`
// modifier when the caller doesn't have anything meaningful to add.
private struct OptionalAccessibilityHintModifier: ViewModifier {
    let hint: String?
    func body(content: Content) -> some View {
        if let hint {
            content.accessibilityHint(hint)
        } else {
            content
        }
    }
}

/// Tiny upward-pointing triangle used as the anchor for the multi-chat
/// tooltip bubble. Drawn as a Path so it inherits the bubble's material fill.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// SwiftUI #Preview removed: ChatView depends on the full LokalApp store
// graph (ModelStore, ChatStore, KnowledgeBaseStore, …). Run the app in
// the simulator to iterate on this view.
