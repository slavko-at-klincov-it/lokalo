//
//  LicenseComplianceTests.swift
//  LokalTests
//
//  Build-time enforcement of the App Store distribution license rule:
//  every model that ships in the bundled `models.json` (and every model
//  that the runtime catalog filter exposes to the UI) must have a license
//  that permits commercial App Store distribution.
//
//  This file is the safety net that catches a research-only or unknown
//  license slipping into the catalog before the build reaches App Review.
//  When you add a new model entry, run the test target. If this file
//  fails, the resolution is one of:
//    1. Replace the model with a commercially-licensed alternative.
//    2. Add a new case to `ModelLicense` and document the commercial-use
//       decision in its `commercialUseAllowed` switch.
//    3. If the upstream license really does not permit commercial use,
//       drop the entry from `models.json` entirely.
//

import XCTest
@testable import Lokal

final class LicenseComplianceTests: XCTestCase {

    /// Hard requirement for App Store submission. Every entry in the bundled
    /// catalog must use a license whose `commercialUseAllowed` is true.
    func testEveryBundledModelAllowsCommercialUse() {
        XCTAssertFalse(
            ModelCatalog.all.isEmpty,
            "ModelCatalog.all is empty — bundled models.json failed to load."
        )
        for entry in ModelCatalog.all {
            XCTAssertTrue(
                entry.license.commercialUseAllowed,
                """
                Model '\(entry.id)' has license '\(entry.license.displayLabel)' \
                which does not permit commercial App Store distribution. \
                Drop this entry from Lokal/Resources/models.json or replace \
                it with a commercially-licensed alternative.
                """
            )
        }
    }

    /// Defense in depth: even if a future remote catalog update introduces
    /// a non-commercial entry, `phoneCompatible` (the filter every UI list
    /// goes through) must still be free of them.
    func testPhoneCompatibleHasNoNonCommercialEntries() {
        for entry in ModelCatalog.phoneCompatible {
            XCTAssertTrue(
                entry.license.commercialUseAllowed,
                "phoneCompatible filter let through non-commercial entry: \(entry.id)"
            )
        }
    }

    /// The conservative-default rule: an unknown license string must map to
    /// `.other(...)` and `commercialUseAllowed` must be `false`. Better to
    /// silently drop a model than ship it under an unverified license.
    func testUnknownLicenseDefaultsToBlocked() {
        let unknown = ModelLicense(rawLabel: "Some Future License That Does Not Exist")
        XCTAssertFalse(
            unknown.commercialUseAllowed,
            "Unknown licenses must default to non-commercial."
        )
        if case .other = unknown {
            // ok
        } else {
            XCTFail("Unknown licenses must map to ModelLicense.other(_)")
        }
    }

    /// Smoke test for the string → enum mapping. If the JSON author writes
    /// "Apache 2.0", the loader must produce `.apache2_0` (not `.other`),
    /// otherwise the model gets silently filtered out of the catalog by
    /// the conservative-default rule.
    func testKnownLicenseStringsMapToTypedCases() {
        XCTAssertEqual(ModelLicense(rawLabel: "Apache 2.0"), .apache2_0)
        XCTAssertEqual(ModelLicense(rawLabel: "apache-2.0"), .apache2_0)
        XCTAssertEqual(ModelLicense(rawLabel: "MIT"), .mit)
        XCTAssertEqual(ModelLicense(rawLabel: "Llama 3.2 Community"), .llamaCommunity)
        XCTAssertEqual(ModelLicense(rawLabel: "Gemma Terms"), .gemmaTerms)
        XCTAssertEqual(ModelLicense(rawLabel: "Qwen Research"), .qwenResearch)

        XCTAssertTrue(ModelLicense.apache2_0.commercialUseAllowed)
        XCTAssertTrue(ModelLicense.mit.commercialUseAllowed)
        XCTAssertTrue(ModelLicense.llamaCommunity.commercialUseAllowed)
        XCTAssertTrue(ModelLicense.gemmaTerms.commercialUseAllowed)
        XCTAssertFalse(ModelLicense.qwenResearch.commercialUseAllowed)
    }
}
