//
//  ChatSessionStore.swift
//  Lokal
//
//  Persistent store for chat sessions. Mirrors the pattern used by
//  KnowledgeBaseStore: a top-level JSON manifest in Application Support,
//  plus one JSON file per session that holds the message history (loaded
//  lazily the first time a session is opened).
//
//  Storage layout:
//    Application Support/LokaloRAG/chat-sessions.json   — index + session meta
//    Application Support/LokaloRAG/sessions/<id>.json   — message list per session
//

import Foundation
import Observation

@MainActor
@Observable
final class ChatSessionStore {

    // MARK: - Observable state

    private(set) var sessions: [ChatSession] = []
    var activeSessionID: UUID?

    /// The currently-active session, falling back to the first one in the
    /// list if `activeSessionID` is nil or stale. Never returns nil after
    /// `bootstrap()` has run on a non-empty store.
    var activeSession: ChatSession? {
        if let id = activeSessionID, let match = sessions.first(where: { $0.id == id }) {
            return match
        }
        return sessions.first
    }

    // MARK: - Message cache

    /// Lazily loaded per-session message arrays. The active session's messages
    /// always end up here; inactive sessions are loaded on demand when the
    /// user opens them.
    private var loadedMessages: [UUID: [ChatMessage]] = [:]

    // MARK: - Lifecycle

    func bootstrap() {
        ensureDirectories()
        loadManifest()
        if activeSessionID == nil {
            activeSessionID = sessions.first?.id
        }
        // Eagerly preload the active session's messages so the first ChatView
        // render doesn't flash an empty list.
        if let id = activeSessionID {
            _ = messages(for: id)
        }
    }

    /// Called once from `LokalApp.task` after `bootstrap()` if the manifest
    /// is empty — so the app always has at least one chat to show. The caller
    /// supplies the seed model ID (normally `modelStore.activeID` or the
    /// onboarding preferred model).
    @discardableResult
    func seedDefaultSessionIfEmpty(modelID: String,
                                   knowledgeBaseID: UUID?,
                                   defaultSettings: GenerationSettings? = nil,
                                   defaultSystemPrompt: String? = nil) -> ChatSession? {
        guard sessions.isEmpty else { return nil }
        // Same cascade as `create()` so the very first chat the user
        // ever sees already runs on the model author's recommended
        // sampling values, not on `GenerationSettings.default`.
        let modelDefaults = ModelCatalog.entry(id: modelID)?.recommendedSamplingDefaults
        let effectiveSettings = defaultSettings
            ?? modelDefaults
            ?? .default
        let seed = ChatSession(
            title: "",
            chatModelID: modelID,
            settings: effectiveSettings,
            systemPromptPreset: .lokaloDefault,
            systemPromptText: defaultSystemPrompt,
            knowledgeBaseID: knowledgeBaseID
        )
        sessions.append(seed)
        activeSessionID = seed.id
        loadedMessages[seed.id] = []
        try? persistManifest()
        try? persistMessages(for: seed.id)
        return seed
    }

    // MARK: - Session CRUD

    @discardableResult
    func create(modelID: String,
                preset: SystemPromptPreset = .lokaloDefault,
                knowledgeBaseID: UUID? = nil,
                settings: GenerationSettings? = nil,
                systemPromptText: String? = nil,
                title: String = "") -> ChatSession {
        // Cascade for the initial sampling values:
        //   1. Explicit caller settings (power-user / Create-Sheet)
        //   2. Preset's suggestion (e.g. Code-Reviewer 0.2 / Creative 0.95)
        //      — `lokaloDefault` returns `nil` here so the next layer wins.
        //   3. Model author's recommendation from `models.json`, populated by
        //      `tools/catalog/update_catalog.py` from HuggingFace.
        //   4. Hardcoded fallback (`GenerationSettings.default`).
        let modelDefaults = ModelCatalog.entry(id: modelID)?.recommendedSamplingDefaults
        let effectiveSettings = settings
            ?? preset.suggestedSettings
            ?? modelDefaults
            ?? .default
        let session = ChatSession(
            title: title,
            chatModelID: modelID,
            settings: effectiveSettings,
            systemPromptPreset: preset,
            systemPromptText: systemPromptText,
            knowledgeBaseID: knowledgeBaseID
        )
        sessions.insert(session, at: 0)
        loadedMessages[session.id] = []
        try? persistManifest()
        try? persistMessages(for: session.id)
        return session
    }

    func setActive(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        activeSessionID = id
        // Preload the target session's messages so the view can render
        // without a flash of empty state.
        _ = messages(for: id)
        try? persistManifest()
    }

    func delete(_ id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions.remove(at: idx)
        loadedMessages.removeValue(forKey: id)
        try? FileManager.default.removeItem(at: Self.messagesFileURL(for: id))
        if activeSessionID == id {
            activeSessionID = sessions.first?.id
        }
        try? persistManifest()
    }

    func rename(_ id: UUID, title: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].title = title
        sessions[idx].updatedAt = .now
        try? persistManifest()
    }

    /// Update the session's metadata (model, system prompt, settings, KB).
    /// Passes the messages through untouched. Used by the edit sheet.
    func updateMeta(_ updated: ChatSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == updated.id }) else { return }
        var next = updated
        next.updatedAt = .now
        sessions[idx] = next
        try? persistManifest()
    }

    @discardableResult
    func duplicate(_ id: UUID) -> ChatSession? {
        guard let source = sessions.first(where: { $0.id == id }) else { return nil }
        let sourceMessages = messages(for: id)
        let copy = ChatSession(
            title: source.displayTitle == "Neue Unterhaltung" ? "" : source.displayTitle + " (Kopie)",
            createdAt: .now,
            updatedAt: .now,
            lastMessagePreview: source.lastMessagePreview,
            chatModelID: source.chatModelID,
            settings: source.settings,
            systemPromptPreset: source.systemPromptPreset,
            systemPromptText: source.systemPromptText,
            knowledgeBaseID: source.knowledgeBaseID
        )
        sessions.insert(copy, at: 0)
        loadedMessages[copy.id] = sourceMessages
        try? persistManifest()
        try? persistMessages(for: copy.id)
        return copy
    }

    /// Called when a knowledge base is deleted. Unlinks any sessions that
    /// pointed at the removed KB so we don't keep dangling UUIDs.
    func unlinkSessionsFromRemovedBase(_ baseID: UUID) {
        var changed = false
        for idx in sessions.indices where sessions[idx].knowledgeBaseID == baseID {
            sessions[idx].knowledgeBaseID = nil
            sessions[idx].updatedAt = .now
            changed = true
        }
        if changed { try? persistManifest() }
    }

    // MARK: - Messages

    /// Return the message list for `sessionID`, loading it from disk on the
    /// first access. Cached for the lifetime of the store (released with
    /// `delete` or on a memory pressure Level 2).
    func messages(for sessionID: UUID) -> [ChatMessage] {
        if let cached = loadedMessages[sessionID] {
            return cached
        }
        let loaded = Self.loadMessagesFromDisk(sessionID: sessionID)
        loadedMessages[sessionID] = loaded
        return loaded
    }

    /// Append a message to the session and persist the updated file. Also
    /// updates `updatedAt` and the `lastMessagePreview` so the drawer sorts
    /// and renders correctly without needing to re-read the session file.
    func appendMessage(_ message: ChatMessage, sessionID: UUID) {
        var list = messages(for: sessionID)
        list.append(message)
        loadedMessages[sessionID] = list
        touchSession(id: sessionID, previewFrom: message)
        try? persistMessages(for: sessionID)
    }

    /// Replace the full message list for a session (used when the streaming
    /// buffer is flushed into a final assistant message).
    func replaceMessages(_ messages: [ChatMessage], sessionID: UUID) {
        loadedMessages[sessionID] = messages
        if let lastNonEmpty = messages.reversed().first(where: { !$0.content.isEmpty }) {
            touchSession(id: sessionID, previewFrom: lastNonEmpty)
        } else {
            touchSessionTimestamp(id: sessionID)
        }
        try? persistMessages(for: sessionID)
    }

    func clearMessages(sessionID: UUID) {
        loadedMessages[sessionID] = []
        if let idx = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[idx].lastMessagePreview = ""
            sessions[idx].updatedAt = .now
        }
        try? persistManifest()
        try? persistMessages(for: sessionID)
    }

    /// Evict all cached messages except those of the active session. Called
    /// by `MemoryPressureCoordinator` at Level 2 to free RAM without losing
    /// any persisted data.
    func evictInactiveMessageCaches() {
        let keep = activeSessionID
        loadedMessages = loadedMessages.filter { $0.key == keep }
    }

    // MARK: - Private helpers

    private func touchSession(id: UUID, previewFrom message: ChatMessage) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].updatedAt = .now
        let preview = message.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if !preview.isEmpty {
            sessions[idx].lastMessagePreview = String(preview.prefix(140))
        }
        // Auto-title from first user turn if still empty.
        if sessions[idx].title.isEmpty && message.role == .user {
            sessions[idx].title = ChatSession.makeAutoTitle(from: message.content)
        }
        try? persistManifest()
    }

    private func touchSessionTimestamp(id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].updatedAt = .now
        try? persistManifest()
    }

    // MARK: - File paths

    private static func rootDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("LokaloRAG", isDirectory: true)
    }

    private static func manifestURL() -> URL {
        rootDirectory().appendingPathComponent("chat-sessions.json")
    }

    private static func sessionsDirectory() -> URL {
        rootDirectory().appendingPathComponent("sessions", isDirectory: true)
    }

    private static func messagesFileURL(for sessionID: UUID) -> URL {
        sessionsDirectory().appendingPathComponent("\(sessionID.uuidString).json")
    }

    private func ensureDirectories() {
        try? FileManager.default.createDirectory(at: Self.rootDirectory(), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Self.sessionsDirectory(), withIntermediateDirectories: true)
    }

    // MARK: - Persistence: manifest

    private struct Manifest: Codable {
        var sessions: [ChatSession]
        var activeSessionID: UUID?
        var schemaVersion: Int
    }

    private static let currentSchemaVersion = 1

    private func persistManifest() throws {
        let manifest = Manifest(
            sessions: sessions,
            activeSessionID: activeSessionID,
            schemaVersion: Self.currentSchemaVersion
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: Self.manifestURL(), options: [.atomic])
    }

    private func loadManifest() {
        guard let data = try? Data(contentsOf: Self.manifestURL()) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(Manifest.self, from: data) else { return }
        self.sessions = manifest.sessions
        self.activeSessionID = manifest.activeSessionID
    }

    // MARK: - Persistence: messages

    private struct MessagesFile: Codable {
        var messages: [ChatMessage]
        var schemaVersion: Int
    }

    private func persistMessages(for sessionID: UUID) throws {
        let list = loadedMessages[sessionID] ?? []
        let file = MessagesFile(messages: list, schemaVersion: Self.currentSchemaVersion)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(file)
        try data.write(to: Self.messagesFileURL(for: sessionID), options: [.atomic])
    }

    private static func loadMessagesFromDisk(sessionID: UUID) -> [ChatMessage] {
        guard let data = try? Data(contentsOf: messagesFileURL(for: sessionID)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(MessagesFile.self, from: data))?.messages ?? []
    }
}
