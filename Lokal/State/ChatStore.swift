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

    var messages: [ChatMessage] = []
    var streamingBuffer: String = ""
    var isStreaming: Bool = false
    var settings: GenerationSettings = .default
    var systemPrompt: String = "You are Lokalo, a friendly on-device AI assistant. Answer concisely and helpfully."
    private(set) var loadState: LoadState = .idle
    /// Optional banner shown above the chat composer (e.g. "Tool: search_files…").
    private(set) var statusBanner: String?

    private var engine: LlamaEngine?
    /// Strong references — owned by LokalApp's dependency graph. Forming a
    /// DAG (no cycles), so strong refs are correct and remove an entire
    /// class of "weak nil → silent feature degradation" bugs.
    private let modelStore: ModelStore
    private let kbStore: KnowledgeBaseStore
    private let indexingService: IndexingService
    private let mcpStore: MCPStore
    private var streamTask: Task<Void, Never>?

    init(modelStore: ModelStore,
         kbStore: KnowledgeBaseStore,
         indexingService: IndexingService,
         mcpStore: MCPStore) {
        self.modelStore = modelStore
        self.kbStore = kbStore
        self.indexingService = indexingService
        self.mcpStore = mcpStore
    }

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

    var canSend: Bool {
        if case .ready = loadState { return !isStreaming }
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
    func switchTo(modelID: String) async {
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

    func clearConversation() {
        streamTask?.cancel()
        Task { await engine?.cancel() }
        messages = []
        streamingBuffer = ""
        isStreaming = false
    }

    func cancelStreaming() {
        streamTask?.cancel()
        Task { await engine?.cancel() }
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let engine, let active = modelStore.activeModel else {
            FileLog.write("ChatStore.send: REJECTED (empty or no engine)")
            return
        }
        FileLog.write("ChatStore.send: trimmed=\(trimmed.count) chars, model=\(active.id)")

        let userMsg = ChatMessage(role: .user, content: trimmed)
        messages.append(userMsg)
        streamingBuffer = ""
        isStreaming = true
        statusBanner = nil

        // Capture strong references to the dependency stores so the
        // detached task can talk to them without weak/optional gymnastics.
        let kbStore = self.kbStore
        let indexingService = self.indexingService
        let mcpStore = self.mcpStore
        let activeFamily = active.chatTemplate
        let baseSystem = systemPrompt
        let snapshotMessages = messages
        let queryText = trimmed

        streamTask?.cancel()
        streamTask = Task.detached(priority: .userInitiated) { [engine, weak self] in
            // 1) RAG augmentation: retrieve top-K chunks if a knowledge base is active.
            var citations: [Citation] = []
            var augmentedSystem = baseSystem
            if let activeKB = await kbStore.activeBase,
               await kbStore.ragEnabled {
                do {
                    let hits = try await indexingService.query(queryText, baseID: activeKB.id, topK: 5)
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
            let tools = await mcpStore.discoveredTools()
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
                            guard let self else { return }
                            self.streamingBuffer = snapshot
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
                        self?.statusBanner = label
                    }
                    let mcpArguments = MCPClientService.convert(arguments: parsed.arguments)
                    do {
                        let result = try await mcpStore.service.callTool(
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
                            self?.streamingBuffer = ""
                            self?.statusBanner = nil
                        }
                        continue
                    } catch {
                        let errMsg = "Tool-Call fehlgeschlagen: \(error.lokaloMessage)"
                        rollingMessages.append(ChatMessage(role: .assistant, content: assistantText))
                        rollingMessages.append(ChatMessage(role: .user, content: errMsg))
                        await MainActor.run {
                            self?.streamingBuffer = ""
                            self?.statusBanner = nil
                        }
                        continue
                    }
                }

                // No tool call → done.
                break
            }

            await MainActor.run {
                guard let self else { return }
                let finalContent = didError
                    ? "[Fehler: \(errorMessage)]"
                    : (lastAssistantText.isEmpty ? self.streamingBuffer : lastAssistantText)
                if !finalContent.isEmpty {
                    self.messages.append(ChatMessage(
                        role: .assistant,
                        content: finalContent,
                        citations: citations.isEmpty ? nil : citations
                    ))
                }
                self.streamingBuffer = ""
                self.isStreaming = false
                self.statusBanner = nil
                FileLog.write("stream: state cleared, messages=\(self.messages.count)")
            }
        }
    }
}
