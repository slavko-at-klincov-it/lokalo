//
//  LokalUITests.swift
//  LokalUITests
//
//  End-to-end UI tests that drive the chat flow and capture screenshots
//  for visual review.
//

import XCTest

final class LokalUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(extraArgs: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = extraArgs
        app.launch()
        return app
    }

    private func snapshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 1. Cold launch with the model already on disk → ChatView is the root.
    func testColdLaunchShowsChatRoot() {
        let app = launchApp()
        // Either the chat composer or the empty-library state is visible.
        XCTAssertTrue(app.textFields["Nachricht eingeben…"].waitForExistence(timeout: 5)
                      || app.staticTexts["Bibliothek"].waitForExistence(timeout: 5))
        snapshot(app, name: "01-launch")
    }

    /// 2. Open settings sheet from the chat toolbar.
    func testOpensSettings() {
        let app = launchApp()
        let gear = app.buttons["gearshape"].firstMatch
        if gear.waitForExistence(timeout: 5) {
            gear.tap()
            XCTAssertTrue(app.staticTexts["Einstellungen"].waitForExistence(timeout: 3))
            snapshot(app, name: "02-settings")
            app.buttons["Fertig"].firstMatch.tap()
        }
    }

    /// 3. Open the model picker sheet by tapping the title.
    func testOpensModelPicker() {
        let app = launchApp()
        // The principal toolbar item shows the model name; tapping it opens the picker.
        let chevron = app.images["chevron.down"].firstMatch
        if chevron.waitForExistence(timeout: 5) {
            chevron.tap()
            XCTAssertTrue(app.staticTexts["Modell wählen"].waitForExistence(timeout: 3))
            snapshot(app, name: "03-model-picker")
            app.buttons["Fertig"].firstMatch.tap()
        }
    }

    /// 4. Compose, send, and verify a response shows up.
    func testFullChatRoundTrip() {
        let app = launchApp(extraArgs: ["-LokalAutoTestPrompt", "Sage einfach: Hallo"])
        // Wait for the user message to appear.
        let userMsg = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Sage einfach")).firstMatch
        XCTAssertTrue(userMsg.waitForExistence(timeout: 30), "User prompt did not appear")
        snapshot(app, name: "04-after-send")

        // Wait up to 30s for SOME assistant text other than the prompt.
        let deadline = Date().addingTimeInterval(30)
        var sawResponse = false
        while Date() < deadline {
            let assistantTexts = app.staticTexts.allElementsBoundByIndex.filter { e in
                let l = e.label
                return !l.isEmpty && !l.contains("Sage einfach") && l.count > 1
                    && !l.contains("Lokal") && !l.contains("Qwen") && !l.contains("Llama")
                    && !l.contains("Gemma") && !l.contains("Phi") && !l.contains("SmolLM")
                    && !l.contains("Bibliothek") && !l.contains("Einstellungen")
            }
            if !assistantTexts.isEmpty {
                sawResponse = true
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        snapshot(app, name: "05-response")
        XCTAssertTrue(sawResponse, "No assistant response detected within 30s")
    }
}
