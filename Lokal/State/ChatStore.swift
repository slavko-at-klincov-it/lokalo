//
//  ChatStore.swift
//  Lokal
//

import Foundation
import Observation

@MainActor
@Observable
final class ChatStore {

    enum LoadState: Equatable {
        case idle
        /// Old engine is being torn down before a new one is loaded.
        case unloading(previousID: String)
        /// New engine is being loaded; `progress` is in 0…1 from llama.cpp.
        case loading(modelID: String, progress: Double)
        case ready(modelID: String)
        case error(String)
    }

    // MARK: - Observable state

    // UI-only: live streaming tail, not persisted token-by-token.
    var streamingBuffer: String = ""
    var isStreaming: Bool = false
    private(set) var loadState: LoadState = .idle
    /// Optional banner shown above the chat composer (e.g. "Tool: search_files…").
    private(set) var statusBanner: String?

    /// Set when the user switches to a session whose `chatModelID` does not
    /// match the currently loaded model. The `PendingModelSwitchCard` reads
    /// this and offers "Modell laden" / "Zurück". `ChatView` disables the
    /// composer while this is non-nil.
    var pendingModelSwitch: String?

    /// Remembers the session the user was in before the pending switch, so
    /// "Zurück" can restore it without guessing.
    var previousSessionID: UUID?

    // MARK: - Per-chat computed properties

    /// Messages of the currently-active session. Reading this is equivalent
    /// to calling `sessionStore.messages(for: activeID)`; writing via
    /// `send()` / `clearConversation()` is routed through the session store
    /// so persistence happens automatically.
    var messages: [ChatMessage] {
        guard let id = sessionStore.activeSessionID else { return [] }
        return sessionStore.messages(for: id)
    }

    /// Active session's sampling settings with a writable shim so the
    /// existing `SettingsSheet` binding (`$chat.settings.temperature`, etc.)
    /// keeps working. Writes land on the session and persist.
    var settings: GenerationSettings {
        get {
            sessionStore.activeSession?.settings ?? Self.fallbackSettings
        }
        set {
            guard var active = sessionStore.activeSession else { return }
            active.settings = newValue
            sessionStore.updateMeta(active)
        }
    }

    /// Active session's system prompt with a writable shim. Editing the text
    /// via `$chat.systemPrompt` automatically flips the preset to `.custom`
    /// so a later preset change doesn't silently clobber the user's edit.
    var systemPrompt: String {
        get {
            sessionStore.activeSession?.systemPromptText ?? Self.fallbackSystemPrompt
        }
        set {
            guard var active = sessionStore.activeSession else { return }
            active.systemPromptText = newValue
            if active.systemPromptPreset != .custom,
               newValue != active.systemPromptPreset.defaultText {
                active.systemPromptPreset = .custom
            }
            sessionStore.updateMeta(active)
        }
    }

    // MARK: - Fallbacks

    /// Used when no active session exists yet (pre-seed on a fresh install).
    /// Kept private so nothing can leak "the global system prompt" pattern
    /// back into the rest of the code.
    private static let fallbackSystemPrompt =
        "Du bist Lokalo, ein freundlicher On-Device-KI-Assistent. Antworte prägnant und hilfsbereit."
    private static let fallbackSettings = GenerationSettings.default

    // MARK: - Dependencies

    private var engine: LlamaEngine?
    /// Strong references — owned by LokalApp's dependency graph. Forming a
    /// DAG (no cycles), so strong refs are correct and remove an entire
    /// class of "weak nil → silent feature degradation" bugs.
    private let modelStore: ModelStore
    private let kbStore: KnowledgeBaseStore
    let sessionStore: ChatSessionStore
    private let indexingService: IndexingService
    private let mcpStore: MCPStore

    private var streamTask: Task<Void, Never>?

    /// Serialises `switchTo` calls so rapid chat switches don't overlap
    /// engine loads. A new `switchTo` cancels the previous one before
    /// starting.
    private var currentSwitchTask: Task<Void, Never>?

    init(modelStore: ModelStore,
         kbStore: KnowledgeBaseStore,
         sessionStore: ChatSessionStore,
         indexingService: IndexingService,
         mcpStore: MCPStore) {
        self.modelStore = modelStore
        self.kbStore = kbStore
        self.sessionStore = sessionStore
        self.indexingService = indexingService
        self.mcpStore = mcpStore
    }

    // MARK: - Auto-test hook

    /// If the app was launched with `-LokalAutoTestPrompt "..."`, fire off
    /// that prompt automatically once the engine is ready. Used for end-to-end
    /// UI screenshots and smoke testing.
    func runAutoTestPromptIfPresent() async {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-LokalAutoTestPrompt"),
              idx + 1 < args.count else { return }
        let prompt = args[idx + 1]
        // Wait until engine is ready before sending.
        for _ in 0..<200 {
            if isReady { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard isReady else { return }
        send(prompt)
    }

    // MARK: - Load state helpers

    var canSend: Bool {
        if case .ready = loadState { return !isStreaming && pendingModelSwitch == nil }
        return false
    }

    var isReady: Bool {
        if case .ready = loadState { return true }
        return false
    }

    var loadingModelID: String? {
        if case .loading(let id, _) = loadState { return id }
        return nil
    }

    var loadProgress: Double {
        if case .loading(_, let p) = loadState { return p }
        return 0
    }

    var isSwitchingModel: Bool {
        switch loadState {
        case .unloading, .loading: return true
        default: return false
        }
    }

    // MARK: - Session switching

    /// Called by the drawer when the user taps a chat row. Switches the
    /// active session in the session store. If the target session's model
    /// is different from what's currently loaded, sets `pendingModelSwitch`
    /// so the `PendingModelSwitchCard` shows — the user must explicitly
    /// confirm the (expensive) model change.
    func switchActiveSession(to id: UUID) {
        guard let session = sessionStore.sessions.first(where: { $0.id == id }) else { return }
        // Remember the previous session so "Zurück" in the pending card
        // can put the user back where they were.
        previousSessionID = sessionStore.activeSessionID

        let currentLoaded: String?
        switch loadState {
        case .ready(let id), .loading(let id, _): currentLoaded = id
        default: currentLoaded = nil
        }

        if currentLoaded == session.chatModelID {
            // Same model (or nothing loaded yet and the target model is also
            // the modelStore's active) — no user confirmation needed.
            sessionStore.setActive(id)
            pendingModelSwitch = nil
        } else {
            // Different model — flip the session but gate sending on an
            // explicit confirmation. The card reads `pendingModelSwitch`.
            sessionStore.setActive(id)
            pendingModelSwitch = session.chatModelID
        }
    }

    /// Called by the pending card's "Modell laden" button. Triggers the
    /// actual engine swap via `modelStore.setActive`, which in turn runs
    /// `switchTo` through the existing `.task(id:)` hook.
    func confirmPendingModelSwitch() {
        guard let target = pendingModelSwitch else { return }
        modelStore.setActive(target)
        pendingModelSwitch = nil
    }

    /// Called by the pending card's "Zurück" button. Reverts to the session
    /// the user was in before, without touching the model.
    func cancelPendingModelSwitch() {
        pendingModelSwitch = nil
        if let prev = previousSessionID,
           sessionStore.sessions.contains(where: { $0.id == prev }) {
            sessionStore.setActive(prev)
        }
        previousSessionID = nil
    }

    // MARK: - Engine lifecycle

    /// Backwards-compatible shim used by call sites that just want "make sure
    /// the active model is loaded". Internally delegates to `switchTo`.
    func ensureEngineLoaded() async {
        guard let active = modelStore.activeModel else {
            await tearDownEngine()
            loadState = .idle
            return
        }
        await switchTo(modelID: active.id)
    }

    /// Unload the current engine (if any) and load `modelID`. Drives the
    /// `loadState` machine through `.unloading → .loading(progress) → .ready`.
    /// Safe to call from `.task(id:)` — re-entry on the same model is a no-op.
    ///
    /// Race-guard: awaits any in-flight switch task and cancels it before
    /// starting a new one. Rapid back-to-back switches (e.g. user tapping
    /// through chats in the drawer) always end up on the latest target.
    func switchTo(modelID: String) async {
        currentSwitchTask?.cancel()
        if let prior = currentSwitchTask {
            _ = await prior.value
        }

        let task = Task { @MainActor in
            await self.performSwitch(to: modelID)
        }
        currentSwitchTask = task
        _ = await task.value
    }

    private func performSwitch(to modelID: String) async {
        guard let target = ModelCatalog.entry(id: modelID),
              modelStore.isInstalled(modelID) else {
            await tearDownEngine()
            loadState = .idle
            return
        }

        // Already loaded → nothing to do.
        if case .ready(let id) = loadState, id == target.id { return }
        // Already loading the same model → nothing to do.
        if case .loading(let id, _) = loadState, id == target.id { return }

        // Cancel any in-flight generation, then tear down the previous engine.
        cancelStreaming()
        if engine != nil {
            // Determine "previous id" for the unload UI label.
            let previousID: String
            switch loadState {
            case .ready(let id), .loading(let id, _): previousID = id
            default: previousID = ""
            }
            loadState = .unloading(previousID: previousID)
            await tearDownEngine()
        }

        loadState = .loading(modelID: target.id, progress: 0)

        do {
            let path = ModelStore.fileURL(for: target).path
            // Use the session's sampling if available, else fall back.
            var settings = self.settings
            settings.contextTokens = Int32(target.recommendedContextTokens)
            let targetID = target.id

            // Progress updates hop back to the main actor. Debounced to ~1 %
            // increments to keep the UI smooth without flooding the runloop.
            let progressHandler: @Sendable (Double) -> Void = { p in
                Task { @MainActor [weak self] in
                    self?.handleLoadProgress(p, modelID: targetID)
                }
            }

            let engine = try await Task.detached(priority: .userInitiated) {
                try LlamaEngine.load(path: path, settings: settings, progress: progressHandler)
            }.value

            // Make sure the final 1.0 frame is rendered even if the callback
            // never reached exactly 1.0 due to debouncing.
            self.loadState = .loading(modelID: target.id, progress: 1.0)
            self.engine = engine
            await engine.updateSettings(settings)
            self.loadState = .ready(modelID: target.id)

            // Sync the active session's chatModelID with the newly loaded
            // model so a user-initiated picker swap is reflected in the
            // session. If the session already pointed at this model (which
            // is the common multi-chat path), this is a no-op.
            if var active = sessionStore.activeSession, active.chatModelID != target.id {
                active.chatModelID = target.id
                sessionStore.updateMeta(active)
            }
        } catch {
            self.engine = nil
            self.loadState = .error(error.lokaloMessage)
        }
    }

    /// Tear down the current engine actor, waiting for `shutdown()` to finish.
    private func tearDownEngine() async {
        guard let engine else { return }
        await engine.cancel()
        await engine.shutdown()
        self.engine = nil
    }

    /// Apply a new progress reading from the loader thread, debounced.
    private func handleLoadProgress(_ value: Double, modelID: String) {
        guard case .loading(let currentID, let current) = loadState,
              currentID == modelID else { return }
        let clamped = max(0, min(1, value))
        // Only step forward; suppress jitter back from the callback.
        guard clamped >= current + 0.01 || clamped >= 0.999 else { return }
        loadState = .loading(modelID: modelID, progress: clamped)
    }

    /// Dismiss a sticky `.error` so the overlay closes.
    func clearLoadError() {
        if case .error = loadState { loadState = .idle }
    }

    /// Clear the current session's message history. Persisted.
    func clearConversation() {
        streamTask?.cancel()
        Task { await engine?.cancel() }
        if let id = sessionStore.activeSessionID {
            sessionStore.clearMessages(sessionID: id)
        }
        streamingBuffer = ""
        isStreaming = false
        statusBanner = nil
    }

    func cancelStreaming() {
        streamTask?.cancel()
        Task { await engine?.cancel() }
    }

    // MARK: - Send + inference loop

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let engine, let active = modelStore.activeModel else {
            FileLog.write("ChatStore.send: REJECTED (empty or no engine)")
            return
        }
        guard let sessionID = sessionStore.activeSessionID else {
            FileLog.write("ChatStore.send: REJECTED (no active session)")
            return
        }
        FileLog.write("ChatStore.send: trimmed=\(trimmed.count) chars, model=\(active.id)")

        // Pre-persist the user message immediately, BEFORE inference starts,
        // so a mid-inference crash / jetsam-kill still keeps the user's turn
        // on disk.
        let userMsg = ChatMessage(role: .user, content: trimmed)
        sessionStore.appendMessage(userMsg, sessionID: sessionID)

        streamingBuffer = ""
        isStreaming = true
        statusBanner = nil

        // Capture the dependencies the detached task will need. `ChatStore`
        // and `ChatSessionStore` are `@MainActor`, so the task hops back via
        // `MainActor.run` for every mutation.
        let kbStoreRef = self.kbStore
        let indexingServiceRef = self.indexingService
        let mcpStoreRef = self.mcpStore
        let activeFamily = active.chatTemplate
        let baseSystem = systemPrompt
        let snapshotMessages = sessionStore.messages(for: sessionID)
        let queryText = trimmed
        let sessionKBID = sessionStore.activeSession?.knowledgeBaseID

        streamTask?.cancel()
        streamTask = Task.detached(priority: .userInitiated) { [engine, weak self] in

            // 1) RAG augmentation: retrieve top-K chunks if the current session
            //    has a knowledge base linked *and* the global RAG kill-switch
            //    allows it.
            var citations: [Citation] = []
            var augmentedSystem = baseSystem
            let ragGlobalEnabled = await MainActor.run { kbStoreRef.ragEnabled }
            if let kbID = sessionKBID, ragGlobalEnabled {
                do {
                    let hits = try await indexingServiceRef.query(queryText, baseID: kbID, topK: 5)
                    if !hits.isEmpty {
                        let contextLines = hits.enumerated().map { idx, hit -> String in
                            let snippet = hit.chunk.text.replacingOccurrences(of: "\n", with: " ")
                            return "[\(idx + 1)] (\(hit.chunk.documentName)) \(snippet)"
                        }
                        let block = contextLines.joined(separator: "\n\n")
                        augmentedSystem = """
                        \(baseSystem)

                        Nutze die folgenden Quellen-Auszüge aus den Wissensbasen des Nutzers, wenn sie zur Frage passen. Zitiere sie inline als [1], [2], usw.
                        \(block)
                        """
                        citations = hits.map { hit in
                            let snippet = hit.chunk.text.count > 320
                                ? String(hit.chunk.text.prefix(320)) + "…"
                                : hit.chunk.text
                            return Citation(
                                sourceName: hit.chunk.documentName,
                                snippet: snippet,
                                pageIndex: hit.chunk.pageIndex,
                                documentPath: hit.chunk.documentPath
                            )
                        }
                    }
                } catch {
                    FileLog.write("RAG retrieval failed: \(error.lokaloMessage)")
                }
            }

            // 2) MCP tools advertisement (best-effort).
            var toolsBySignature: [String: MCPClientService.DiscoveredTool] = [:]
            let tools = await mcpStoreRef.discoveredTools()
            if !tools.isEmpty {
                let descriptions = tools.map { "\($0.toolName): \($0.description)" }
                let toolsSection = ToolCallParser.systemPromptSection(toolDescriptions: descriptions)
                augmentedSystem += toolsSection
                for tool in tools {
                    toolsBySignature[tool.toolName] = tool
                }
            }

            var rollingMessages = snapshotMessages
            var lastAssistantText = ""
            var didError = false
            var errorMessage = ""

            // 3) Inference loop with optional MCP tool-call hops.
            for _ in 0..<5 {
                if Task.isCancelled { break }
                let prompt = ChatTemplate.render(
                    family: activeFamily,
                    system: augmentedSystem.isEmpty ? nil : augmentedSystem,
                    messages: rollingMessages
                )
                let stops = ChatTemplate.stopStrings(family: activeFamily)

                let stream = await engine.generate(prompt: prompt, stopStrings: stops)
                var assistantText = ""
                do {
                    for try await chunk in stream {
                        if Task.isCancelled { break }
                        assistantText += chunk
                        let snapshot = assistantText
                        await MainActor.run {
                            guard let strongSelf = self else { return }
                            strongSelf.streamingBuffer = snapshot
                        }
                    }
                } catch {
                    didError = true
                    errorMessage = error.lokaloMessage
                    FileLog.write("stream: ERROR \(errorMessage)")
                    break
                }
                lastAssistantText = assistantText

                // Tool-call detection.
                if let parsed = ToolCallParser.parse(assistantText),
                   let tool = toolsBySignature[parsed.name] {
                    let serverID = tool.serverID
                    let toolName = tool.toolName
                    let label = "Tool: \(toolName) wird ausgeführt …"
                    await MainActor.run {
                        guard let strongSelf = self else { return }
                        strongSelf.statusBanner = label
                    }
                    let mcpArguments = MCPClientService.convert(arguments: parsed.arguments)
                    do {
                        let result = try await mcpStoreRef.service.callTool(
                            serverID: serverID,
                            name: toolName,
                            arguments: mcpArguments
                        )
                        // Append the assistant tool-call as is, then a synthetic user message
                        // containing the tool result. Continue the loop.
                        rollingMessages.append(ChatMessage(role: .assistant, content: assistantText))
                        rollingMessages.append(ChatMessage(
                            role: .user,
                            content: "Tool result for \(toolName):\n\(result)"
                        ))
                        await MainActor.run {
                            guard let strongSelf = self else { return }
                            strongSelf.streamingBuffer = ""
                            strongSelf.statusBanner = nil
                        }
                        continue
                    } catch {
                        let errMsg = "Tool-Call fehlgeschlagen: \(error.lokaloMessage)"
                        rollingMessages.append(ChatMessage(role: .assistant, content: assistantText))
                        rollingMessages.append(ChatMessage(role: .user, content: errMsg))
                        await MainActor.run {
                            guard let strongSelf = self else { return }
                            strongSelf.streamingBuffer = ""
                            strongSelf.statusBanner = nil
                        }
                        continue
                    }
                }

                // No tool call → done.
                break
            }

            // Persist the final assistant message.
            let errMsgCapture = errorMessage
            let didErrorCapture = didError
            let lastAssistantCapture = lastAssistantText
            let citationsCapture = citations
            await MainActor.run {
                guard let strongSelf = self else { return }
                let finalContent = didErrorCapture
                    ? "[Fehler: \(errMsgCapture)]"
                    : (lastAssistantCapture.isEmpty ? strongSelf.streamingBuffer : lastAssistantCapture)
                if !finalContent.isEmpty {
                    let assistantMsg = ChatMessage(
                        role: .assistant,
                        content: finalContent,
                        citations: citationsCapture.isEmpty ? nil : citationsCapture
                    )
                    strongSelf.sessionStore.appendMessage(assistantMsg, sessionID: sessionID)
                }
                strongSelf.streamingBuffer = ""
                strongSelf.isStreaming = false
                strongSelf.statusBanner = nil
                FileLog.write("stream: state cleared, messages=\(strongSelf.messages.count)")
            }
        }
    }
}
