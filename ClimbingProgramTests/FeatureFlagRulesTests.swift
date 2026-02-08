import XCTest
@testable import klettrack

final class FeatureFlagRulesTests: XCTestCase {
    func testRowDetailTextUsesGymWhenAvailable() {
        let value = FeatureFlagRules.rowDetailText(
            gym: "My Gym",
            notes: "Fallback notes",
            showNotesWhenGymMissing: true
        )
        XCTAssertEqual(value, "My Gym")
    }

    func testRowDetailTextUsesNotesWhenGymMissingAndFlagEnabled() {
        let value = FeatureFlagRules.rowDetailText(
            gym: "Unknown",
            notes: "  Use this note  ",
            showNotesWhenGymMissing: true
        )
        XCTAssertEqual(value, "Use this note")
    }

    func testRowDetailTextHidesNotesWhenFlagDisabled() {
        let value = FeatureFlagRules.rowDetailText(
            gym: "",
            notes: "Some note",
            showNotesWhenGymMissing: false
        )
        XCTAssertNil(value)
    }
}
