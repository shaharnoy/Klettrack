import XCTest

@testable import klettrack

final class PlanDayExerciseOrderingTests: XCTestCase {
    func testManualOrderOverridesCatalogOrderAfterReload() {
        let ordered = PlanDayExerciseOrdering.sortedNames(
            ["Hangboard", "Pull-ups", "Push-ups"],
            manualOrder: ["Push-ups": 0, "Hangboard": 1, "Pull-ups": 2],
            catalogOrder: ["Hangboard": 0, "Pull-ups": 1, "Push-ups": 2],
            isQuickLogged: { _ in false }
        )

        XCTAssertEqual(ordered, ["Push-ups", "Hangboard", "Pull-ups"])
    }

    func testCatalogOrderIsUsedWhenNoManualOrderExists() {
        let ordered = PlanDayExerciseOrdering.sortedNames(
            ["Push-ups", "Hangboard", "Pull-ups"],
            manualOrder: [:],
            catalogOrder: ["Hangboard": 0, "Pull-ups": 1, "Push-ups": 2],
            isQuickLogged: { _ in false }
        )

        XCTAssertEqual(ordered, ["Hangboard", "Pull-ups", "Push-ups"])
    }
}
