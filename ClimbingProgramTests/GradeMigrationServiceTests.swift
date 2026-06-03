import SwiftData
import XCTest
@testable import klettrack

final class GradeMigrationServiceTests: ClimbingProgramTestSuite {
    @MainActor
    func testMigrationUpdatesOnlyMatchingGymAndGrade() throws {
        let matchingOne = makeClimb(gym: "Ostbloc", grade: "V4", feelsLikeGrade: "V5")
        let matchingTwo = makeClimb(gym: "Ostbloc", grade: "V4", feelsLikeGrade: nil)
        let sameGradeOtherGym = makeClimb(gym: "Bouldergarten", grade: "V4", feelsLikeGrade: "V4")
        let otherGradeSameGym = makeClimb(gym: "Ostbloc", grade: "V5", feelsLikeGrade: "V5")

        let summary = try GradeMigrationService.migrate(
            in: context,
            gym: "Ostbloc",
            oldGrade: "V4",
            newGrade: "V6",
            newFeelsLikeGrade: nil
        )

        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(matchingOne.grade, "V6")
        XCTAssertEqual(matchingTwo.grade, "V6")
        XCTAssertEqual(sameGradeOtherGym.grade, "V4")
        XCTAssertEqual(otherGradeSameGym.grade, "V5")
    }

    @MainActor
    func testMigrationUpdatesFeelsLikeGradeWhenProvided() throws {
        let climb = makeClimb(gym: "Ostbloc", grade: "6a", feelsLikeGrade: "6b")

        let summary = try GradeMigrationService.migrate(
            in: context,
            gym: "Ostbloc",
            oldGrade: "6a",
            newGrade: "6c",
            newFeelsLikeGrade: " 7a "
        )

        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(climb.grade, "6c")
        XCTAssertEqual(climb.feelsLikeGrade, "7a")
    }

    @MainActor
    func testMigrationLeavesFeelsLikeGradeUnchangedWhenBlank() throws {
        let climbWithValue = makeClimb(gym: "Ostbloc", grade: "6a", feelsLikeGrade: "6b")
        let climbWithoutValue = makeClimb(gym: "Ostbloc", grade: "6a", feelsLikeGrade: nil)

        let summary = try GradeMigrationService.migrate(
            in: context,
            gym: "Ostbloc",
            oldGrade: "6a",
            newGrade: "6c",
            newFeelsLikeGrade: " "
        )

        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(climbWithValue.grade, "6c")
        XCTAssertEqual(climbWithValue.feelsLikeGrade, "6b")
        XCTAssertEqual(climbWithoutValue.grade, "6c")
        XCTAssertNil(climbWithoutValue.feelsLikeGrade)
    }

    @MainActor
    func testMigrationReturnsZeroWhenNoEntriesMatch() throws {
        let climb = makeClimb(gym: "Ostbloc", grade: "V4", feelsLikeGrade: "V5")

        let summary = try GradeMigrationService.migrate(
            in: context,
            gym: "Ostbloc",
            oldGrade: "V3",
            newGrade: "V5",
            newFeelsLikeGrade: "V6"
        )

        XCTAssertEqual(summary.count, 0)
        XCTAssertEqual(climb.grade, "V4")
        XCTAssertEqual(climb.feelsLikeGrade, "V5")
    }

    @MainActor
    func testBulkMigrationUsesOriginalGradesAndDoesNotCascade() throws {
        let originalFour = makeClimb(gym: "Ostbloc", grade: "4")
        let originalFive = makeClimb(gym: "Ostbloc", grade: "5")
        let otherGymFour = makeClimb(gym: "Bouldergarten", grade: "4")

        let summary = try GradeMigrationService.migrateAll(
            in: context,
            gym: "Ostbloc",
            mappings: [
                .init(oldGrade: "4", newGrade: "5", newFeelsLikeGrade: nil),
                .init(oldGrade: "5", newGrade: "6", newFeelsLikeGrade: nil)
            ]
        )

        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(originalFour.grade, "5")
        XCTAssertEqual(originalFive.grade, "6")
        XCTAssertEqual(otherGymFour.grade, "4")
        XCTAssertEqual(
            summary.rows,
            [
                .init(oldGrade: "4", newGrade: "5", newFeelsLikeGrade: nil, count: 1),
                .init(oldGrade: "5", newGrade: "6", newFeelsLikeGrade: nil, count: 1)
            ]
        )
    }

    @MainActor
    func testBulkMigrationCanMapMultipleOldGradesToSameTargetGrade() throws {
        let v4 = makeClimb(gym: "Ostbloc", grade: "V4")
        let v5 = makeClimb(gym: "Ostbloc", grade: "V5")

        let summary = try GradeMigrationService.migrateAll(
            in: context,
            gym: "Ostbloc",
            mappings: [
                .init(oldGrade: "V4", newGrade: "V6", newFeelsLikeGrade: nil),
                .init(oldGrade: "V5", newGrade: "V6", newFeelsLikeGrade: nil)
            ]
        )

        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(v4.grade, "V6")
        XCTAssertEqual(v5.grade, "V6")
    }

    @MainActor
    func testBulkMigrationLeavesUnmappedGradesUnchanged() throws {
        let mapped = makeClimb(gym: "Ostbloc", grade: "V4", feelsLikeGrade: "V5")
        let unmapped = makeClimb(gym: "Ostbloc", grade: "V5", feelsLikeGrade: "V6")

        let summary = try GradeMigrationService.migrateAll(
            in: context,
            gym: "Ostbloc",
            mappings: [
                .init(oldGrade: "V4", newGrade: "V6", newFeelsLikeGrade: "V7")
            ]
        )

        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(mapped.grade, "V6")
        XCTAssertEqual(mapped.feelsLikeGrade, "V7")
        XCTAssertEqual(unmapped.grade, "V5")
        XCTAssertEqual(unmapped.feelsLikeGrade, "V6")
    }

    @MainActor
    func testBulkMigrationIgnoresBlankTargetsAndNoOpMappings() throws {
        let noTarget = makeClimb(gym: "Ostbloc", grade: "V4", feelsLikeGrade: "V5")
        let noChange = makeClimb(gym: "Ostbloc", grade: "V5", feelsLikeGrade: "V6")

        let summary = try GradeMigrationService.migrateAll(
            in: context,
            gym: "Ostbloc",
            mappings: [
                .init(oldGrade: "V4", newGrade: " ", newFeelsLikeGrade: nil),
                .init(oldGrade: "V5", newGrade: "V5", newFeelsLikeGrade: " ")
            ]
        )

        XCTAssertEqual(summary.count, 0)
        XCTAssertEqual(noTarget.grade, "V4")
        XCTAssertEqual(noTarget.feelsLikeGrade, "V5")
        XCTAssertEqual(noChange.grade, "V5")
        XCTAssertEqual(noChange.feelsLikeGrade, "V6")
    }

    @MainActor
    func testBulkMigrationAllowsFeelsLikeOnlyForSameGrade() throws {
        let climb = makeClimb(gym: "Ostbloc", grade: "V5", feelsLikeGrade: "V6")

        let summary = try GradeMigrationService.migrateAll(
            in: context,
            gym: "Ostbloc",
            mappings: [
                .init(oldGrade: "V5", newGrade: "V5", newFeelsLikeGrade: "V7")
            ]
        )

        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(climb.grade, "V5")
        XCTAssertEqual(climb.feelsLikeGrade, "V7")
    }

    @MainActor
    func testAvailableOldGradesReturnsDistinctSortedGradesForSelectedGym() {
        makeClimb(gym: "Ostbloc", grade: "V5")
        makeClimb(gym: "Ostbloc", grade: "V3")
        makeClimb(gym: "Ostbloc", grade: "V5")
        makeClimb(gym: "Bouldergarten", grade: "V1")

        let grades = GradeMigrationService.availableOldGrades(in: context, gym: "Ostbloc")

        XCTAssertEqual(grades, ["V3", "V5"])
    }

    @MainActor
    func testGradeCountsReturnsDistinctSortedGradesWithCountsForSelectedGym() {
        makeClimb(gym: "Ostbloc", grade: "V5")
        makeClimb(gym: "Ostbloc", grade: "V3")
        makeClimb(gym: "Ostbloc", grade: "V5")
        makeClimb(gym: "Bouldergarten", grade: "V1")

        let counts = GradeMigrationService.gradeCounts(in: context, gym: "Ostbloc")

        XCTAssertEqual(
            counts,
            [
                .init(grade: "V3", count: 1),
                .init(grade: "V5", count: 2)
            ]
        )
    }

    @MainActor
    func testMatchingCountUsesExactGymAndGrade() {
        makeClimb(gym: "Ostbloc", grade: "V4")
        makeClimb(gym: "Ostbloc", grade: "V4")
        makeClimb(gym: "ostbloc", grade: "V4")
        makeClimb(gym: "Ostbloc", grade: "v4")

        let count = GradeMigrationService.matchingCount(in: context, gym: "Ostbloc", oldGrade: "V4")

        XCTAssertEqual(count, 2)
    }

    @MainActor
    @discardableResult
    private func makeClimb(
        gym: String,
        grade: String,
        feelsLikeGrade: String? = nil
    ) -> ClimbEntry {
        let climb = ClimbEntry(
            climbType: .boulder,
            grade: grade,
            feelsLikeGrade: feelsLikeGrade,
            style: "Technical",
            attempts: "1",
            gym: gym
        )
        context.insert(climb)
        return climb
    }
}
