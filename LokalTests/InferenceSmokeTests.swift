//
//  InferenceSmokeTests.swift
//  LokalTests
//
//  End-to-end smoke test: load a real GGUF and generate tokens.
//  Skipped automatically when no GGUF is present in the test sandbox.
//

import XCTest
@testable import Lokal

final class InferenceSmokeTests: XCTestCase {

    /// Locate any .gguf file in the host app's Documents/models directory.
    private func locateGGUF() -> URL? {
        let modelsDir = ModelStore.modelsDirectory()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return nil
        }
        return entries.first { $0.pathExtension.lowercased() == "gguf" }
    }

    func testEngineLoadsAndGeneratesAtLeastOneToken() async throws {
        guard let gguf = locateGGUF() else {
            throw XCTSkip("No .gguf in Documents/models — copy a model in to run this test.")
        }

        var settings = GenerationSettings.default
        settings.contextTokens = 1024
        settings.maxNewTokens = 24
        settings.temperature = 0.7

        let engine = try LlamaEngine.load(path: gguf.path, settings: settings)

        // Use the chatml template (Qwen / SmolLM) which is the most common small-model template.
        let prompt = ChatTemplate.render(
            family: .chatml,
            system: "You are a helpful assistant.",
            messages: [.init(role: .user, content: "Say hi in one word.")]
        )

        var collected = ""
        let stream = await engine.generate(prompt: prompt, stopStrings: ChatTemplate.stopStrings(family: .chatml))
        for try await chunk in stream {
            collected += chunk
            if collected.count > 80 { break }
        }

        XCTAssertFalse(collected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "Expected at least one token from the model, got empty string")
        // The model is well-trained — it should produce *something* sensible.
        // Don't assert on content, just that it's not garbage.
        let printable = collected.unicodeScalars.filter { $0.value >= 32 || $0.value == 10 }.count
        XCTAssertGreaterThan(printable, 0, "Expected printable characters, got \(collected.debugDescription)")
        print("INFERENCE OUTPUT: \(collected)")
    }

    func testReuseEngineForMultipleGenerations() async throws {
        guard let gguf = locateGGUF() else {
            throw XCTSkip("No .gguf in Documents/models")
        }
        var settings = GenerationSettings.default
        settings.maxNewTokens = 16
        let engine = try LlamaEngine.load(path: gguf.path, settings: settings)

        for i in 0..<2 {
            let prompt = ChatTemplate.render(
                family: .chatml,
                system: nil,
                messages: [.init(role: .user, content: "Count to \(i + 2)")]
            )
            var out = ""
            let stream = await engine.generate(prompt: prompt, stopStrings: ChatTemplate.stopStrings(family: .chatml))
            for try await chunk in stream {
                out += chunk
            }
            XCTAssertFalse(out.isEmpty, "Generation \(i) was empty")
            print("GENERATION \(i): \(out)")
        }
    }
}
