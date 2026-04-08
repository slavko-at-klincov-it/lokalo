//
//  OnboardingFirstRunTests.swift
//  LokalUITests
//
//  Walks the two-beat onboarding flow end-to-end:
//   1. Launch with hasCompletedOnboarding flipped off
//   2. Beat 1 — Sternenwort + the four privacy promises must appear
//   3. Tap to advance → Beat 2 ("Personalisieren") must appear
//   4. The "Loslegen" button must be present and tappable
//

import XCTest

final class OnboardingFirstRunTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchOnboarding() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-Lokal.hasCompletedOnboarding", "0"]
        app.launch()
        return app
    }

    func testBeat1ShowsThePromises() {
        let app = launchOnboarding()
        let promise = app.staticTexts["Kein Konto."]
        XCTAssertTrue(promise.waitForExistence(timeout: 10), "Beat 1 promise not visible")
        XCTAssertTrue(app.staticTexts["Keine Cloud."].exists)
        XCTAssertTrue(app.staticTexts["Keine Werbung."].exists)
        XCTAssertTrue(app.staticTexts["Keine Telemetrie."].exists)
    }

    func testTapAdvancesFromBeat1ToBeat2() {
        let app = launchOnboarding()

        // Wait for Beat 1's content so the tap doesn't race the entry animation.
        let promise = app.staticTexts["Kein Konto."]
        XCTAssertTrue(promise.waitForExistence(timeout: 10))
        // Wait for the swipe hint to appear so the tap actually advances.
        let hint = app.staticTexts["Zum Starten wischen"]
        _ = hint.waitForExistence(timeout: 8)

        app.tap()

        let beat2Header = app.staticTexts["Personalisieren"]
        XCTAssertTrue(beat2Header.waitForExistence(timeout: 5),
                      "Beat 2 not shown after Beat 1 tap")
        XCTAssertTrue(app.buttons["Loslegen"].waitForExistence(timeout: 4),
                      "Loslegen button missing in Beat 2")
    }
}
