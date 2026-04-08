//
//  Chunker.swift
//  Lokal
//
//  Sentence-aware fixed-window chunker. Uses Apple's NLTokenizer to find
//  sentence boundaries (free, multilingual), then aggregates sentences up to
//  a target token budget with a configurable overlap.
//

import Foundation
import NaturalLanguage

struct TextChunk: Hashable {
    let text: String
    let charStart: Int
    let charEnd: Int
    let pageIndex: Int?
}

enum Chunker {

    /// Crude token-count approximation: ~4 chars/token. Good enough as a
    /// stable yardstick — we don't need exact tokenization, just consistent
    /// windows for the embedding model.
    static func approxTokens(_ s: String) -> Int { max(1, s.count / 4) }

    static func chunk(_ document: ExtractedDocument,
                      targetTokens: Int = 384,
                      overlapTokens: Int = 64) -> [TextChunk] {
        var out: [TextChunk] = []
        for page in document.pages {
            out.append(contentsOf: chunkPage(text: page.text,
                                             pageIndex: page.pageIndex,
                                             targetTokens: targetTokens,
                                             overlapTokens: overlapTokens))
        }
        return out
    }

    private static func chunkPage(text: String,
                                  pageIndex: Int?,
                                  targetTokens: Int,
                                  overlapTokens: Int) -> [TextChunk] {
        let trimmed = text
        guard !trimmed.isEmpty else { return [] }

        let tok = NLTokenizer(unit: .sentence)
        tok.string = trimmed
        var sentences: [(String, Range<String.Index>)] = []
        tok.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            let s = String(trimmed[range])
            if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sentences.append((s, range))
            }
            return true
        }
        if sentences.isEmpty {
            // Fall back to the whole page as a single sentence-equivalent.
            sentences = [(trimmed, trimmed.startIndex..<trimmed.endIndex)]
        }

        var chunks: [TextChunk] = []
        var current: [(String, Range<String.Index>)] = []
        var currentTokens = 0

        func flush() {
            guard !current.isEmpty else { return }
            let combined = current.map { $0.0 }.joined(separator: " ")
            let lo = current.first!.1.lowerBound
            let hi = current.last!.1.upperBound
            chunks.append(TextChunk(
                text: combined.trimmingCharacters(in: .whitespacesAndNewlines),
                charStart: trimmed.distance(from: trimmed.startIndex, to: lo),
                charEnd: trimmed.distance(from: trimmed.startIndex, to: hi),
                pageIndex: pageIndex
            ))
        }

        for s in sentences {
            let st = approxTokens(s.0)
            if currentTokens + st > targetTokens && !current.isEmpty {
                flush()
                // Build overlap tail from the trailing sentences of the previous chunk.
                var overlap: [(String, Range<String.Index>)] = []
                var ot = 0
                for sent in current.reversed() {
                    overlap.insert(sent, at: 0)
                    ot += approxTokens(sent.0)
                    if ot >= overlapTokens { break }
                }
                current = overlap
                currentTokens = ot
            }
            current.append(s)
            currentTokens += st
        }
        flush()
        return chunks
    }
}
