//
//  ToolCallParser.swift
//  Lokal
//
//  Tiny parser that lets non-function-calling LLMs talk to MCP servers via
//  a universal XML-style tool-call wrapper:
//
//      <tool_call>{"name": "tool_name", "arguments": {"arg": "value"}}</tool_call>
//
//  Returns the parsed name + arguments and the surrounding text so we can
//  splice it back together for the chat history.
//

import Foundation

struct ParsedToolCall: Hashable {
    let name: String
    let arguments: [String: AnyCodable]
    let textBefore: String
    let textAfter: String
}

/// Type-erased Codable wrapper used in tool arguments. Carries through
/// any JSON value (string, number, bool, dict, array, null) without losing
/// fidelity to either the LLM that produced it or the MCP server that consumes it.
struct AnyCodable: Codable, Hashable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = NSNull()
        } else if let b = try? container.decode(Bool.self) {
            self.value = b
        } else if let i = try? container.decode(Int.self) {
            self.value = i
        } else if let d = try? container.decode(Double.self) {
            self.value = d
        } else if let s = try? container.decode(String.self) {
            self.value = s
        } else if let arr = try? container.decode([AnyCodable].self) {
            self.value = arr.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            self.value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:           try container.encodeNil()
        case let b as Bool:       try container.encode(b)
        case let i as Int:        try container.encode(i)
        case let d as Double:     try container.encode(d)
        case let s as String:     try container.encode(s)
        case let arr as [Any]:    try container.encode(arr.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:                  try container.encodeNil()
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: value))
    }
}

enum ToolCallParser {

    static func parse(_ text: String) -> ParsedToolCall? {
        guard let openRange = text.range(of: "<tool_call>"),
              let closeRange = text.range(of: "</tool_call>", range: openRange.upperBound..<text.endIndex)
        else { return nil }
        let json = String(text[openRange.upperBound..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = json.data(using: .utf8) else { return nil }
        struct ToolPayload: Decodable {
            let name: String
            let arguments: [String: AnyCodable]?
        }
        guard let payload = try? JSONDecoder().decode(ToolPayload.self, from: data) else {
            return nil
        }
        return ParsedToolCall(
            name: payload.name,
            arguments: payload.arguments ?? [:],
            textBefore: String(text[text.startIndex..<openRange.lowerBound]),
            textAfter: String(text[closeRange.upperBound..<text.endIndex])
        )
    }

    static func systemPromptSection(toolDescriptions: [String]) -> String {
        guard !toolDescriptions.isEmpty else { return "" }
        let list = toolDescriptions.map { "- \($0)" }.joined(separator: "\n")
        return """

        Du hast Zugriff auf die folgenden Tools. Wenn du eines aufrufen möchtest, antworte AUSSCHLIESSLICH mit:
        <tool_call>{"name": "tool_name", "arguments": {"arg": "value"}}</tool_call>
        Schreibe NICHTS ausser dem Tool-Call. Das System ruft das Tool auf und gibt dir das Ergebnis zurück.

        Verfügbare Tools:
        \(list)
        """
    }
}
