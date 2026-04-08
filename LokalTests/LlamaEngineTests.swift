//
//  LlamaEngineTests.swift
//  LokalTests
//

import XCTest
@testable import Lokal

final class ChatTemplateTests: XCTestCase {

    func testLlama3FormatsConversation() {
        let messages: [ChatMessage] = [
            .init(role: .user, content: "Hi"),
            .init(role: .assistant, content: "Hello!")
        ]
        let s = ChatTemplate.render(family: .llama3, system: "You are nice.", messages: messages)
        XCTAssertTrue(s.contains("<|begin_of_text|>"))
        XCTAssertTrue(s.contains("<|start_header_id|>system<|end_header_id|>"))
        XCTAssertTrue(s.contains("You are nice."))
        XCTAssertTrue(s.contains("<|start_header_id|>user<|end_header_id|>"))
        XCTAssertTrue(s.contains("Hi"))
        XCTAssertTrue(s.contains("<|start_header_id|>assistant<|end_header_id|>"))
        XCTAssertTrue(s.contains("Hello!"))
        XCTAssertTrue(s.hasSuffix("<|start_header_id|>assistant<|end_header_id|>\n\n"))
    }

    func testChatMLFormatsConversation() {
        let messages: [ChatMessage] = [.init(role: .user, content: "Hi")]
        let s = ChatTemplate.render(family: .chatml, system: nil, messages: messages)
        XCTAssertTrue(s.contains("<|im_start|>user\nHi<|im_end|>"))
        XCTAssertTrue(s.hasSuffix("<|im_start|>assistant\n"))
    }

    func testGemmaInjectsSystemIntoFirstUser() {
        let messages: [ChatMessage] = [
            .init(role: .user, content: "Hello"),
            .init(role: .assistant, content: "Hi back"),
            .init(role: .user, content: "Again")
        ]
        let s = ChatTemplate.render(family: .gemma, system: "Be friendly.", messages: messages)
        XCTAssertTrue(s.contains("Be friendly.\n\nHello"))
        // System should NOT be injected into the second user message.
        XCTAssertFalse(s.contains("Be friendly.\n\nAgain"))
        XCTAssertTrue(s.hasSuffix("<start_of_turn>model\n"))
    }

    func testStopStringsExist() {
        XCTAssertEqual(ChatTemplate.stopStrings(family: .llama3), ["<|eot_id|>", "<|end_of_text|>"])
        XCTAssertEqual(ChatTemplate.stopStrings(family: .chatml), ["<|im_end|>", "<|endoftext|>"])
        XCTAssertEqual(ChatTemplate.stopStrings(family: .gemma), ["<end_of_turn>", "<eos>"])
    }
}

final class ModelCatalogTests: XCTestCase {

    func testCatalogIsNonEmptyAndUnique() {
        XCTAssertGreaterThanOrEqual(ModelCatalog.all.count, 10)
        let ids = ModelCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Model IDs must be unique")
    }

    func testAllURLsAreHTTPS() {
        for entry in ModelCatalog.all {
            XCTAssertEqual(entry.downloadURL.scheme, "https", "Model \(entry.id) URL must be HTTPS")
            XCTAssertTrue(entry.downloadURL.host?.contains("huggingface.co") == true)
        }
    }

    func testFilenamesEndInGGUF() {
        for entry in ModelCatalog.all {
            XCTAssertTrue(entry.filename.hasSuffix(".gguf"), "\(entry.id) filename must be .gguf")
        }
    }

    func testEverySuggestedIDExists() {
        for id in ModelCatalog.suggested {
            XCTAssertNotNil(ModelCatalog.entry(id: id), "suggested ID \(id) not in catalog")
        }
    }

    func testSizesArePlausible() {
        for entry in ModelCatalog.all {
            XCTAssertGreaterThan(entry.sizeBytes, 100_000_000, "\(entry.id) size suspiciously small")
            XCTAssertLessThan(entry.sizeBytes, 8_000_000_000, "\(entry.id) too big for phone")
        }
    }
}

@MainActor
final class ModelStoreTests: XCTestCase {

    /// We can't always assume an empty sandbox (the smoke test pre-populates a GGUF).
    /// Skip the empty-state assertions when something is on disk.
    private func sandboxIsEmpty() -> Bool {
        let dir = ModelStore.modelsDirectory()
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return entries.filter { $0.pathExtension.lowercased() == "gguf" }.isEmpty
    }

    func testActiveModelDefaultsToNilOnEmptyStore() async throws {
        try XCTSkipUnless(sandboxIsEmpty(), "Sandbox already has models")
        let store = ModelStore()
        await store.bootstrap()
        XCTAssertFalse(store.hasInstalledModels)
        XCTAssertNil(store.activeID)
    }

    func testMarkInstalledExpandsTheSet() async {
        let store = ModelStore()
        await store.bootstrap()
        let before = store.installedIDs.count
        store.markInstalled("tinyllama-1.1b-chat-q4km")
        XCTAssertTrue(store.installedIDs.contains("tinyllama-1.1b-chat-q4km"))
        XCTAssertEqual(store.installedIDs.count, before + 1)
        XCTAssertNotNil(store.activeID)
    }
}
