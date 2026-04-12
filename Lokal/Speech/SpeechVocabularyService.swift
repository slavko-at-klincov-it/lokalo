//
//  SpeechVocabularyService.swift
//  Lokal
//
//  Personal speech vocabulary — learns from user corrections to speech
//  recognition errors and auto-corrects future transcriptions.
//
//  Two-pass apply:
//  1. Exact match (case-insensitive, word-boundary regex)
//  2. Fuzzy match (normalized Levenshtein < 0.35)
//
//  Longer phrases are checked first to avoid partial replacements.
//

import Foundation

@MainActor
@Observable
final class SpeechVocabularyService {

    /// Maximum normalized Levenshtein distance for fuzzy match (0–1, lower = stricter).
    /// 0.35 catches typical phoneme confusions without false positives on random words.
    static let fuzzyThreshold: Double = 0.35

    /// Maximum number of stored corrections before pruning by lastUsedAt.
    private static let maxCorrections = 5000

    private(set) var corrections: [SpeechCorrection] = []
    /// Cached compiled regexes keyed by heard phrase. Invalidated on learn/delete.
    private var regexCache: [String: NSRegularExpression] = [:]

    // MARK: - Persistence

    private static func storageURL() -> URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        let dir = support.appendingPathComponent("LokaloSpeech", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("corrections.json")
    }

    func bootstrap() {
        let url = Self.storageURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let loaded = try JSONDecoder().decode([SpeechCorrection].self, from: data)
            corrections = loaded.sorted { $0.heard.count > $1.heard.count }
        } catch {
            print("[SpeechVocabulary] Failed to load: \(error)")
            corrections = []
        }
    }

    private func persist() {
        do {
            var toSave = corrections
            // Prune to maxCorrections, keeping most recently used.
            if toSave.count > Self.maxCorrections {
                toSave.sort { $0.lastUsedAt > $1.lastUsedAt }
                toSave = Array(toSave.prefix(Self.maxCorrections))
            }
            let data = try JSONEncoder().encode(toSave)
            try data.write(to: Self.storageURL(), options: .atomic)
        } catch {
            print("[SpeechVocabulary] Failed to persist: \(error)")
        }
    }

    // MARK: - Apply (synchronous, hot path)

    /// Applies known corrections to a transcription segment.
    func applyCorrections(_ text: String) -> String {
        guard !corrections.isEmpty else { return text }

        var result = text

        // Pass 1: Exact matching with word-boundary regex (cached)
        for correction in corrections {
            let regex: NSRegularExpression
            if let cached = regexCache[correction.heard] {
                regex = cached
            } else {
                let escaped = NSRegularExpression.escapedPattern(for: correction.heard)
                let pattern = "\\b\(escaped)\\b"
                guard let compiled = try? NSRegularExpression(
                    pattern: pattern,
                    options: [.caseInsensitive]
                ) else { continue }
                regexCache[correction.heard] = compiled
                regex = compiled
            }

            let range = NSRange(result.startIndex..., in: result)
            let template = NSRegularExpression.escapedTemplate(for: correction.meantDisplay)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: template
            )
        }

        // Pass 2: Fuzzy matching (one substitution per correction per pass)
        for correction in corrections {
            let heardWords = correction.heard.split(separator: " ").map(String.init)
            let heardWordCount = heardWords.count
            guard heardWordCount > 0 else { continue }

            var resultWords = result.split(separator: " ").map(String.init)
            guard resultWords.count >= heardWordCount else { continue }

            var didReplace = false
            for i in 0...(resultWords.count - heardWordCount) {
                let window = resultWords[i..<(i + heardWordCount)].joined(separator: " ")
                let windowLower = window.lowercased()

                // Skip if already matches the correction target
                if windowLower == correction.meant { continue }

                let distance = levenshtein(windowLower, correction.heard)
                let maxLen = max(windowLower.count, correction.heard.count)
                let normalized = maxLen > 0 ? Double(distance) / Double(maxLen) : 0

                if normalized > 0 && normalized <= Self.fuzzyThreshold {
                    let meantWords = correction.meantDisplay.split(separator: " ").map(String.init)
                    resultWords.replaceSubrange(i..<(i + heardWordCount), with: meantWords)
                    didReplace = true
                    break // One fuzzy correction per pass to avoid cascading
                }
            }

            if didReplace {
                result = resultWords.joined(separator: " ")
            }
        }

        return result
    }

    // MARK: - Learn

    /// Compares the original transcription with the user-edited text and stores
    /// any word-level substitutions as new corrections.
    /// Insertions and deletions are intentionally ignored — only true substitutions
    /// (both sides non-empty) are learned.
    func learnCorrections(original: String, edited: String) {
        let pairs = extractCorrections(original: original, edited: edited)
        guard !pairs.isEmpty else { return }

        for (heard, meant) in pairs {
            let heardLower = heard.lowercased()
            let meantLower = meant.lowercased()

            if heardLower == meantLower { continue }
            if heardLower.count < 2 { continue } // Skip noise

            if let idx = corrections.firstIndex(where: { $0.heard == heardLower }) {
                corrections[idx].meant = meantLower
                corrections[idx].meantDisplay = meant
                corrections[idx].count += 1
                corrections[idx].lastUsedAt = .now
            } else {
                corrections.append(SpeechCorrection(
                    heard: heardLower,
                    meant: meantLower,
                    heardDisplay: heard,
                    meantDisplay: meant
                ))
            }
            print("[SpeechVocabulary] Learned: \"\(heard)\" → \"\(meant)\"")
        }

        // Re-sort: longest phrases first for matching priority
        corrections.sort { $0.heard.count > $1.heard.count }
        regexCache.removeAll()
        persist()
    }

    /// Extracts substitution-block corrections via word-level LCS alignment.
    /// Returns only true substitutions where consecutive unmatched words exist on both sides.
    func extractCorrections(original: String, edited: String) -> [(heard: String, meant: String)] {
        let origTrimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let editTrimmed = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        if origTrimmed == editTrimmed { return [] }
        if origTrimmed.isEmpty || editTrimmed.isEmpty { return [] }

        let origWords = origTrimmed.split(separator: " ").map(String.init)
        let editWords = editTrimmed.split(separator: " ").map(String.init)

        let n = origWords.count
        let m = editWords.count
        guard n > 0 && m > 0 else { return [] }

        // LCS DP table
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                if origWords[i - 1].lowercased() == editWords[j - 1].lowercased() {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to mark matched indices on both sides
        var origMatched = Set<Int>()
        var editMatched = Set<Int>()
        var i = n
        var j = m
        while i > 0 && j > 0 {
            if origWords[i - 1].lowercased() == editWords[j - 1].lowercased() {
                origMatched.insert(i - 1)
                editMatched.insert(j - 1)
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        // Walk both arrays and collect substitution blocks
        var result: [(heard: String, meant: String)] = []
        var oi = 0
        var ei = 0

        while oi < n || ei < m {
            if oi < n && origMatched.contains(oi) && ei < m && editMatched.contains(ei) {
                oi += 1
                ei += 1
                continue
            }

            var heardWords: [String] = []
            var meantWords: [String] = []

            while oi < n && !origMatched.contains(oi) {
                heardWords.append(origWords[oi])
                oi += 1
            }
            while ei < m && !editMatched.contains(ei) {
                meantWords.append(editWords[ei])
                ei += 1
            }

            // Only true substitutions count (both sides non-empty)
            if !heardWords.isEmpty && !meantWords.isEmpty {
                result.append((
                    heard: heardWords.joined(separator: " "),
                    meant: meantWords.joined(separator: " ")
                ))
            }
        }

        return result
    }

    // MARK: - Management

    func deleteCorrection(_ correction: SpeechCorrection) {
        corrections.removeAll { $0.id == correction.id }
        regexCache.removeAll()
        persist()
    }

    func clearAll() {
        corrections = []
        regexCache.removeAll()
        persist()
    }

    // MARK: - Levenshtein

    /// Character-level Levenshtein edit distance with O(min(m,n)) memory.
    private func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count
        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = Swift.min(
                    prev[j] + 1,       // deletion
                    curr[j - 1] + 1,   // insertion
                    prev[j - 1] + cost // substitution
                )
            }
            swap(&prev, &curr)
        }

        return prev[n]
    }
}
