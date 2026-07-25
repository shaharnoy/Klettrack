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

    func testProgressFilterPersistenceFlagUsesDedicatedStorageKey() {
        XCTAssertEqual(FeatureFlags.persistProgressFilters, "featureFlag.persistProgressFilters")
        XCTAssertNotEqual(FeatureFlags.persistProgressFilters, FeatureFlags.forcePreferMyGradeInProgress)
        XCTAssertNotEqual(FeatureFlags.persistProgressFilters, FeatureFlags.showNotesWhenGymMissing)
        XCTAssertNotEqual(FeatureFlags.persistProgressFilters, FeatureFlags.showSyncedBoardGradesAsVScale)
    }

    func testSyncedBoardGradeFlagUsesDedicatedStorageKey() {
        XCTAssertEqual(FeatureFlags.showSyncedBoardGradesAsVScale, "featureFlag.showSyncedBoardGradesAsVScale")
        XCTAssertNotEqual(FeatureFlags.showSyncedBoardGradesAsVScale, FeatureFlags.forcePreferMyGradeInProgress)
        XCTAssertNotEqual(FeatureFlags.showSyncedBoardGradesAsVScale, FeatureFlags.showNotesWhenGymMissing)
    }

    func testBoardGradeMapperKeepsFontGradeOutput() {
        XCTAssertEqual(BoardGradeMapper.grade(of: 20), "6c")
    }

    func testBoardGradeMapperMapsDifficultyToVGrade() {
        XCTAssertEqual(BoardGradeMapper.vGrade(of: 20), "V5")
    }

    func testBoardGradeMapperMapsStoredFontGradeToVGrade() {
        XCTAssertEqual(BoardGradeMapper.vGrade(fromFontGrade: "6c"), "V5")
    }

    func testBoardGradeMapperLeavesUnknownFontGradeUnmapped() {
        XCTAssertNil(BoardGradeMapper.vGrade(fromFontGrade: "Custom"))
    }

    func testBoardGradeDisplayRulesPreserveNonBoardGradeWhenVScaleEnabled() {
        let value = BoardGradeDisplayRules.displayText(
            grade: "6c",
            feelsLikeGrade: nil,
            tb2ClimbUUID: nil,
            kilterClimbUuid: nil,
            showSyncedBoardGradesAsVScale: true
        )

        XCTAssertEqual(value, "6c")
    }

    func testBoardGradeDisplayRulesConvertSyncedBoardGradeWhenVScaleEnabled() {
        let value = BoardGradeDisplayRules.displayText(
            grade: "6c",
            feelsLikeGrade: nil,
            tb2ClimbUUID: "tb2-1",
            kilterClimbUuid: nil,
            showSyncedBoardGradesAsVScale: true
        )

        XCTAssertEqual(value, "V5")
    }

    func testBoardGradeDisplayRulesConvertSyncedBoardGradeAndFeelsLikeWhenVScaleEnabled() {
        let value = BoardGradeDisplayRules.displayText(
            grade: "6c",
            feelsLikeGrade: "6b+",
            tb2ClimbUUID: nil,
            kilterClimbUuid: "kilter-1",
            showSyncedBoardGradesAsVScale: true
        )

        XCTAssertEqual(value, "V5 (V4)")
    }

    func testBoardGradeDisplayRulesPreserveSyncedBoardGradeWhenVScaleDisabled() {
        let value = BoardGradeDisplayRules.displayText(
            grade: "6c",
            feelsLikeGrade: "6b+",
            tb2ClimbUUID: "tb2-1",
            kilterClimbUuid: nil,
            showSyncedBoardGradesAsVScale: false
        )

        XCTAssertEqual(value, "6c (6b+)")
    }

    func testBoardGradeDisplayRulesResolveAnalyticsGradeWithVScale() {
        let value = BoardGradeDisplayRules.resolvedGrade(
            grade: "6c",
            feelsLikeGrade: "6b+",
            preferFeelsLikeGrade: true,
            tb2ClimbUUID: "tb2-1",
            kilterClimbUuid: nil,
            showSyncedBoardGradesAsVScale: true
        )

        XCTAssertEqual(value, "V4")
    }
}
