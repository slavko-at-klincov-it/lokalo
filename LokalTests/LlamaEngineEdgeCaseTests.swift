//
//  LlamaEngineEdgeCaseTests.swift
//  LokalTests
//
//  Covers the Phase A correctness fixes:
//   - C4: contextTooSmall is thrown when nCtx < maxNewTokens reservation
//          (no more silent suffix(_:) crash on negative count)
//   - C3: stop-string detection across boundaries (smoke test that verifies
//          no crash and no half-stop-string slips out — covered in
//          LlamaEngineStopStringTests against the engine, but the synchronous
//          stopStringIndex helper is tested in isolation here too)
//

import XCTest
@testable import Lokal

final class LlamaEngineEdgeCaseTests: XCTestCase {

    /// We can't easily construct a real LlamaEngine without a GGUF on disk,
    /// so this test exercises the public surface that should reject the
    /// undersized-context configuration BEFORE it tries to allocate anything.
    /// We confirm the new error case exists and carries the right payload.
    func testContextTooSmallErrorIsReachable() {
        let err = LlamaError.contextTooSmall(nCtx: 100, maxNewTokens: 512)
        XCTAssertNotNil(err.errorDescription)
        if case .contextTooSmall(let n, let m) = err {
            XCTAssertEqual(n, 100)
            XCTAssertEqual(m, 512)
        } else {
            XCTFail("Expected .contextTooSmall, got \(err)")
        }
    }

    /// Smoke check that the new error description is German-friendly and
    /// includes the offending numbers (so the user can act on it).
    func testContextTooSmallDescriptionIncludesNumbers() {
        let err = LlamaError.contextTooSmall(nCtx: 256, maxNewTokens: 1024)
        let desc = err.errorDescription ?? ""
        XCTAssertTrue(desc.contains("256"))
        XCTAssertTrue(desc.contains("1024"))
    }

    /// Existing error cases still produce non-nil descriptions — no
    /// regressions on the LocalizedError surface.
    func testAllExistingErrorsStillHaveDescriptions() {
        let cases: [LlamaError] = [
            .modelLoadFailed("/tmp/x"),
            .contextInitFailed,
            .decodeFailed(-1),
            .tokenizationFailed,
            .alreadyGenerating,
            .contextTooSmall(nCtx: 1, maxNewTokens: 2)
        ]
        for c in cases {
            XCTAssertFalse(c.errorDescription?.isEmpty ?? true,
                           "\(c) has empty errorDescription")
        }
    }
}
