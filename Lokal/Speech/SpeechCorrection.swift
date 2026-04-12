//
//  SpeechCorrection.swift
//  Lokal
//
//  Persistent record of a user-corrected speech recognition error.
//  `heard`/`meant` are stored lowercase for matching;
//  `heardDisplay`/`meantDisplay` preserve original casing for replacement.
//

import Foundation

struct SpeechCorrection: Identifiable, Codable, Hashable {
    let id: UUID
    /// Lowercase phrase that was originally transcribed (matching key).
    var heard: String
    /// Lowercase phrase the user actually meant.
    var meant: String
    /// Original casing of the heard phrase.
    var heardDisplay: String
    /// Original casing of the meant phrase (used for replacement output).
    var meantDisplay: String
    /// How often this correction has been confirmed.
    var count: Int
    /// Last time this correction was applied or learned.
    var lastUsedAt: Date

    init(
        id: UUID = UUID(),
        heard: String,
        meant: String,
        heardDisplay: String,
        meantDisplay: String,
        count: Int = 1,
        lastUsedAt: Date = .now
    ) {
        self.id = id
        self.heard = heard
        self.meant = meant
        self.heardDisplay = heardDisplay
        self.meantDisplay = meantDisplay
        self.count = count
        self.lastUsedAt = lastUsedAt
    }
}
