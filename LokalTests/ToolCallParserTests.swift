//
//  ToolCallParserTests.swift
//  LokalTests
//
//  Covers the inline `<tool_call>{ ... }</tool_call>` wrapper used by the
//  chat → MCP bridge. Targets the cases the audit flagged: malformed JSON,
//  missing arguments, surrounding chatter, and the absence of a tool call.
//

import XCTest
@testable import Lokal

final class ToolCallParserTests: XCTestCase {

    func testValidToolCallParses() throws {
        let text = """
        Sure, let me check the weather for you.
        <tool_call>{"name": "weather_lookup", "arguments": {"city": "Wien"}}</tool_call>
        """
        let parsed = try XCTUnwrap(ToolCallParser.parse(text))
        XCTAssertEqual(parsed.name, "weather_lookup")
        XCTAssertEqual(parsed.arguments["city"]?.value as? String, "Wien")
        XCTAssertTrue(parsed.textBefore.contains("Sure"))
    }

    func testToolCallWithoutArgumentsParses() throws {
        let text = """
        <tool_call>{"name": "list_files", "arguments": {}}</tool_call>
        """
        let parsed = try XCTUnwrap(ToolCallParser.parse(text))
        XCTAssertEqual(parsed.name, "list_files")
        XCTAssertTrue(parsed.arguments.isEmpty)
    }

    func testMalformedJSONReturnsNil() {
        let text = """
        <tool_call>{this is not json at all}</tool_call>
        """
        XCTAssertNil(ToolCallParser.parse(text))
    }

    func testMissingNameReturnsNil() {
        let text = """
        <tool_call>{"arguments": {"foo": "bar"}}</tool_call>
        """
        XCTAssertNil(ToolCallParser.parse(text))
    }

    func testNoToolCallReturnsNil() {
        let text = "Just a normal assistant response with no tool call at all."
        XCTAssertNil(ToolCallParser.parse(text))
    }

    func testNestedJSONArgumentsParse() throws {
        let text = """
        <tool_call>{"name": "compose_email", "arguments": {"to": ["a@b.de", "c@d.de"], "body": {"subject": "Hi", "lines": 3}}}</tool_call>
        """
        let parsed = try XCTUnwrap(ToolCallParser.parse(text))
        XCTAssertEqual(parsed.name, "compose_email")
        let to = parsed.arguments["to"]?.value as? [Any]
        XCTAssertEqual(to?.count, 2)
        let body = parsed.arguments["body"]?.value as? [String: Any]
        XCTAssertEqual(body?["subject"] as? String, "Hi")
    }

    func testSystemPromptSectionContainsToolDescriptions() {
        let section = ToolCallParser.systemPromptSection(toolDescriptions: [
            "weather_lookup: get current weather for a city",
            "list_files: list files in the workspace"
        ])
        XCTAssertTrue(section.contains("weather_lookup"))
        XCTAssertTrue(section.contains("list_files"))
        XCTAssertTrue(section.contains("<tool_call>"))
    }
}
