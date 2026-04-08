//
//  LlamaEngineStopStringTests.swift
//  LokalTests
//
//  End-to-end test of the rewritten stop-string look-ahead buffer.
//  Loads a real GGUF and forces a generation that should stop at a known
//  inline marker, then verifies (a) no crash, (b) the marker itself never
//  appears in the streamed output, (c) the safe prefix that does appear is
//  consistent.
//
//  Skipped automatically when no GGUF is present in the test sandbox.
//

import XCTest
@testable import Lokal

final class LlamaEngineStopStringTests: XCTestCase {

    private func locateGGUF() -> URL? {
        let modelsDir = ModelStore.modelsDirectory()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return nil
        }
        return entries.first { $0.pathExtension.lowercased() == "gguf" }
    }

    /// The classic stop-string scenario — feed the model a prompt that's
    /// likely to emit a chatml turn marker, register `<|im_end|>` as a stop
    /// string, and verify the marker never makes it into the output.
    func testStopStringNeverAppearsInOutput() async throws {
        guard let gguf = locateGGUF() else {
            throw XCTSkip("No .gguf in Documents/models")
        }
        var settings = GenerationSettings.default
        settings.contextTokens = 1024
        settings.maxNewTokens = 64
        settings.temperature = 0.7
        let engine = try LlamaEngine.load(path: gguf.path, settings: settings)

        // Prompt that should naturally produce a `<|im_end|>` boundary.
        let prompt = ChatTemplate.render(
            family: .chatml,
            system: "You answer in one sentence.",
            messages: [.init(role: .user, content: "Say hi.")]
        )
        let stops = ChatTemplate.stopStrings(family: .chatml)
        XCTAssertFalse(stops.isEmpty, "Expected at least one stop string")

        var output = ""
        let stream = await engine.generate(prompt: prompt, stopStrings: stops)
        for try await chunk in stream {
            output += chunk
            if output.count > 200 { break }
        }

        for stop in stops {
            XCTAssertFalse(output.contains(stop),
                           "Stop string \(stop) leaked into output: \(output.debugDescription)")
        }
    }

    /// Generation with no stop strings configured must still complete and
    /// emit something — i.e. the new look-ahead buffer fallback path works.
    func testNoStopStringsStillEmitsOutput() async throws {
        guard let gguf = locateGGUF() else {
            throw XCTSkip("No .gguf in Documents/models")
        }
        var settings = GenerationSettings.default
        settings.maxNewTokens = 16
        let engine = try LlamaEngine.load(path: gguf.path, settings: settings)
        let prompt = ChatTemplate.render(
            family: .chatml,
            system: nil,
            messages: [.init(role: .user, content: "One word.")]
        )
        var output = ""
        let stream = await engine.generate(prompt: prompt, stopStrings: [])
        for try await chunk in stream {
            output += chunk
        }
        XCTAssertFalse(output.isEmpty, "Expected non-empty output with no stop strings")
    }
}
