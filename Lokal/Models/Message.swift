//
//  Message.swift
//  Lokal
//

import Foundation

struct ChatMessage: Identifiable, Hashable, Codable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant, system }

    let id: UUID
    let role: Role
    var content: String
    let createdAt: Date

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = .now) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}
