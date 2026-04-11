//
//  ChatSession.swift
//  Lokal
//
//  A persistent chat session. Each session carries its own model, system
//  prompt, sampling settings and optionally a knowledge base. Messages are
//  stored in a sibling JSON file (sessions/<id>.json), loaded lazily, so the
//  index file `chat-sessions.json` stays lightweight even with dozens of
//  historic sessions.
//

import Foundation

// MARK: - SystemPromptPreset

/// Predefined "purpose" presets that seed a chat's system prompt and sampling
/// defaults. Users can pick a preset and keep it, or edit the text — editing
/// the text flips the preset to `.custom` so we know not to overwrite it on
/// subsequent preset changes.
enum SystemPromptPreset: String, Codable, CaseIterable, Sendable, Hashable {
    case lokaloDefault
    case codeReviewer
    case summarizer
    case translator
    case tutor
    case creative
    case custom

    var displayName: String {
        switch self {
        case .lokaloDefault: return "Lokalo Standard"
        case .codeReviewer:  return "Code-Reviewer"
        case .summarizer:    return "Zusammenfasser"
        case .translator:    return "Übersetzer"
        case .tutor:         return "Tutor"
        case .creative:      return "Kreativ"
        case .custom:        return "Benutzerdefiniert"
        }
    }

    /// SF Symbol name for the preset chip.
    var symbolName: String {
        switch self {
        case .lokaloDefault: return "bubble.left.and.bubble.right"
        case .codeReviewer:  return "chevron.left.forwardslash.chevron.right"
        case .summarizer:    return "text.alignleft"
        case .translator:    return "character.bubble"
        case .tutor:         return "graduationcap"
        case .creative:      return "paintbrush.pointed"
        case .custom:        return "slider.horizontal.3"
        }
    }

    /// German default prompt text for each preset. `.custom` returns empty —
    /// callers should keep whatever the user typed.
    var defaultText: String {
        switch self {
        case .lokaloDefault:
            return "Du bist Lokalo, ein freundlicher On-Device-KI-Assistent. Antworte prägnant und hilfsbereit."
        case .codeReviewer:
            return "Du reviewst Code. Sei prägnant, nenne Zeilennummern wenn möglich, und schlage einen konkreten Fix vor. Erkläre nur, was für das Verständnis nötig ist."
        case .summarizer:
            return "Du fasst Dokumente und Unterhaltungen zusammen. Antworte in 3–5 Bulletpoints. Konzentriere dich auf Fakten, nicht auf Meinungen."
        case .translator:
            return "Du übersetzt zwischen Deutsch und Englisch. Behalte den ursprünglichen Tonfall und die Formatierung bei. Liefere nur die Übersetzung, ohne Kommentare."
        case .tutor:
            return "Du erklärst Konzepte wie einem interessierten Erwachsenen ohne Vorwissen im Thema. Nutze Analogien aus dem Alltag und prüfe am Ende mit einer kurzen Frage, ob der Lernende mitkommt."
        case .creative:
            return "Du bist kreativ, verspielt und offen für unkonventionelle Ideen. Wenn eine Antwort mehrere Richtungen erlaubt, biete zwei oder drei Varianten an."
        case .custom:
            return ""
        }
    }

    /// Suggested generation defaults for each preset. `.custom` returns nil so
    /// the existing user settings are kept. These are only applied when the
    /// user picks a preset in the create sheet — once edited, the user's
    /// sampling values win.
    ///
    /// `.lokaloDefault` returns `nil` (not `GenerationSettings.default`) so
    /// the cascade in `ChatSessionStore.create()` falls through to the
    /// model-author's recommended sampling defaults instead of forcing
    /// every Lokalo-Standard chat into a single hard-coded value set.
    var suggestedSettings: GenerationSettings? {
        var base = GenerationSettings.default
        switch self {
        case .lokaloDefault:
            return nil  // cascade falls through to model defaults
        case .codeReviewer:
            base.temperature = 0.2
            base.topP = 0.9
            return base
        case .summarizer:
            base.temperature = 0.3
            base.topP = 0.9
            return base
        case .translator:
            base.temperature = 0.3
            base.topP = 0.9
            return base
        case .tutor:
            base.temperature = 0.5
            base.topP = 0.95
            return base
        case .creative:
            base.temperature = 0.95
            base.topP = 0.95
            return base
        case .custom:
            return nil
        }
    }
}

// MARK: - ChatSession

/// A single persisted conversation. The message list itself is stored in a
/// sibling file (sessions/<id>.json) and loaded lazily by `ChatSessionStore`.
/// The index file `chat-sessions.json` only contains the metadata below so
/// the drawer list loads in a few milliseconds even with hundreds of chats.
struct ChatSession: Identifiable, Codable, Hashable, Sendable {

    let id: UUID
    var title: String               // "" → auto-generated from first user turn
    var createdAt: Date
    var updatedAt: Date             // also the sort key for "last used"

    /// Last user/assistant message preview, cached here so the drawer list
    /// doesn't need to read each session file just to show a preview.
    var lastMessagePreview: String

    // Model (required)
    var chatModelID: String

    // Generation — initial snapshot copied from app defaults; after that the
    // session owns its own values and the global defaults don't leak in.
    var settings: GenerationSettings

    // System prompt
    var systemPromptPreset: SystemPromptPreset
    var systemPromptText: String

    // RAG
    var knowledgeBaseID: UUID?      // nil → RAG off for this chat

    // User profile
    var includeUserProfile: Bool    // inject global "Über mich" text into system prompt

    // UI
    var isPinned: Bool              // reserved for v2 sorting

    init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastMessagePreview: String = "",
        chatModelID: String,
        settings: GenerationSettings = .default,
        systemPromptPreset: SystemPromptPreset = .lokaloDefault,
        systemPromptText: String? = nil,
        knowledgeBaseID: UUID? = nil,
        includeUserProfile: Bool = true,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastMessagePreview = lastMessagePreview
        self.chatModelID = chatModelID
        self.settings = settings
        self.systemPromptPreset = systemPromptPreset
        self.systemPromptText = systemPromptText ?? systemPromptPreset.defaultText
        self.knowledgeBaseID = knowledgeBaseID
        self.includeUserProfile = includeUserProfile
        self.isPinned = isPinned
    }

    // MARK: - Codable migration

    /// Decodes gracefully when new fields are missing in persisted JSON
    /// (e.g. `includeUserProfile` added after existing sessions were saved).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        lastMessagePreview = try c.decode(String.self, forKey: .lastMessagePreview)
        chatModelID = try c.decode(String.self, forKey: .chatModelID)
        settings = try c.decode(GenerationSettings.self, forKey: .settings)
        systemPromptPreset = try c.decode(SystemPromptPreset.self, forKey: .systemPromptPreset)
        systemPromptText = try c.decode(String.self, forKey: .systemPromptText)
        knowledgeBaseID = try c.decodeIfPresent(UUID.self, forKey: .knowledgeBaseID)
        includeUserProfile = try c.decodeIfPresent(Bool.self, forKey: .includeUserProfile) ?? true
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    /// Human-readable title for the drawer list. Falls back to a trimmed
    /// version of the first user turn's content via the caller supplying a
    /// fallback, otherwise a generic placeholder.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Neue Unterhaltung" : trimmed
    }

    /// Build an auto-title from the first user message. Trims, collapses
    /// whitespace, caps at 40 characters + ellipsis. Returns a placeholder
    /// if the input is empty so `displayTitle` stays meaningful.
    static func makeAutoTitle(from firstUserMessage: String) -> String {
        let trimmed = firstUserMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= 40 { return trimmed }
        return String(trimmed.prefix(40)) + "…"
    }
}
