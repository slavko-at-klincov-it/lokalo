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

    func testBundledManifestLoadsFromJSON() {
        // The catalog used to be a hardcoded Swift array; it's now loaded
        // from `Resources/models.json`. If the bundle resource is missing
        // or malformed, `manifest` collapses to `.empty` and every
        // user-facing list is silently empty. Catch that here.
        let manifest = ModelCatalog.manifest
        XCTAssertGreaterThan(manifest.version, 0, "Bundled manifest version must be > 0")
        XCTAssertGreaterThan(manifest.entries.count, 0, "Bundled manifest must have entries")
        XCTAssertGreaterThan(manifest.maxEffectiveBillion, 0)
    }

    func testQwen35IsPresent() throws {
        let entry = try XCTUnwrap(
            ModelCatalog.entry(id: "qwen-3.5-0.8b-instruct-q4km"),
            "Qwen 3.5 0.8B must exist in the bundled catalog"
        )
        XCTAssertEqual(entry.publisher, "Alibaba")
        XCTAssertEqual(entry.chatTemplate, .qwen3)
        XCTAssertEqual(entry.sizeBytes, 556_982_432,
                       "Size must match the exact Content-Length from HF CDN")
    }

    func testFourSmallestIncludeQwen35() {
        // The onboarding picker shows the four smallest phone-compatible
        // entries. Qwen 3.5 0.8B (557 MB) must be in that set.
        let smallest4 = ModelCatalog.phoneCompatible
            .sorted { $0.sizeBytes < $1.sizeBytes }
            .prefix(4)
            .map(\.id)
        XCTAssertTrue(smallest4.contains("qwen-3.5-0.8b-instruct-q4km"),
                      "Qwen 3.5 0.8B must be among the four smallest. Got: \(smallest4)")
    }

    func testEveryEntryUsesAKnownChatTemplate() {
        // Catches stale JSON that references a removed Family case.
        // Custom Decodable already fails at load time, but this test
        // gives a clearer failure message if it ever fires.
        let validFamilies = Set(ChatTemplate.Family.allCases)
        for entry in ModelCatalog.all {
            XCTAssertTrue(validFamilies.contains(entry.chatTemplate),
                          "\(entry.id) uses unknown chat template family")
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
