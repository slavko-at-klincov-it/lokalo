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
        case loading(modelID: String)
        case ready(modelID: String)
        case error(String)
    }

    var messages: [ChatMessage] = []
    var streamingBuffer: String = ""
    var isStreaming: Bool = false
    var settings: GenerationSettings = .default
    var systemPrompt: String = "You are Lokalo, a friendly on-device AI assistant. Answer concisely and helpfully."
    private(set) var loadState: LoadState = .idle

    private var engine: LlamaEngine?
    private weak var modelStore: ModelStore?
    private var streamTask: Task<Void, Never>?

    func attach(modelStore: ModelStore) {
        self.modelStore = modelStore
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
        if case .loading(let id) = loadState { return id }
        return nil
    }

    func ensureEngineLoaded() async {
        guard let modelStore, let active = modelStore.activeModel else {
            engine = nil
            loadState = .idle
            return
        }
        if case .ready(let id) = loadState, id == active.id { return }
        if case .loading(let id) = loadState, id == active.id { return }

        loadState = .loading(modelID: active.id)
        engine = nil
        do {
            // Load on a background queue to keep UI responsive.
            let path = ModelStore.fileURL(for: active).path
            var settings = self.settings
            settings.contextTokens = Int32(active.recommendedContextTokens)
            let engine = try await Task.detached(priority: .userInitiated) { () throws -> LlamaEngine in
                try LlamaEngine.load(path: path, settings: settings)
            }.value
            self.engine = engine
            await engine.updateSettings(settings)
            self.loadState = .ready(modelID: active.id)
        } catch {
            self.loadState = .error(error.localizedDescription)
        }
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
        guard !trimmed.isEmpty, let engine, let modelStore, let active = modelStore.activeModel else {
            FileLog.write("ChatStore.send: REJECTED (empty or no engine)")
            return
        }
        FileLog.write("ChatStore.send: trimmed=\(trimmed.count) chars, model=\(active.id)")

        // Append the user turn (no placeholder for the assistant — we render
        // streamingBuffer separately while isStreaming is true).
        let userMsg = ChatMessage(role: .user, content: trimmed)
        messages.append(userMsg)
        streamingBuffer = ""
        isStreaming = true

        // Render the conversation through the chat template (only completed
        // messages — the user turn we just added is the last one).
        let prompt = ChatTemplate.render(family: active.chatTemplate,
                                         system: systemPrompt.isEmpty ? nil : systemPrompt,
                                         messages: messages)
        let stops = ChatTemplate.stopStrings(family: active.chatTemplate)

        streamTask?.cancel()
        // Run the consume loop OFF MainActor so SwiftUI's rendering can
        // interleave between chunks. Each chunk hops back to MainActor only
        // for the state mutation, keeping the runloop free for layout/draw.
        streamTask = Task.detached(priority: .userInitiated) { [engine, weak self] in
            let t0 = Date()
            FileLog.write("stream: starting (prompt=\(prompt.count) chars)")
            let stream = await engine.generate(prompt: prompt, stopStrings: stops)
            var didError = false
            var errorMessage = ""
            var chunkCount = 0
            do {
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    chunkCount += 1
                    await MainActor.run {
                        guard let self else { return }
                        self.streamingBuffer += chunk
                    }
                }
            } catch {
                didError = true
                errorMessage = error.localizedDescription
                FileLog.write("stream: ERROR \(errorMessage)")
            }
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            FileLog.write("stream: done in \(ms) ms, \(chunkCount) chunks")
            await MainActor.run {
                guard let self else { return }
                let finalContent = didError
                    ? "[Fehler: \(errorMessage)]"
                    : self.streamingBuffer
                if !finalContent.isEmpty {
                    self.messages.append(ChatMessage(role: .assistant, content: finalContent))
                }
                self.streamingBuffer = ""
                self.isStreaming = false
                FileLog.write("stream: state cleared, messages=\(self.messages.count)")
            }
        }
    }
}
