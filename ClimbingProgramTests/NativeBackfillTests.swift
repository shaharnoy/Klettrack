import SwiftData
import XCTest
@testable import klettrack

@MainActor
final class NativeBackfillTests: BaseSwiftDataTestCase {
    func testBackfillClimbEntryAttemptsDefaultsMissingValuesToOne() throws {
        let missingAttempts = ClimbEntry(
            climbType: .boulder,
            grade: "V4",
            style: "Power",
            attempts: nil,
            gym: "Ostbloc"
        )
        let blankAttempts = ClimbEntry(
            climbType: .boulder,
            grade: "V5",
            style: "Technical",
            attempts: "   ",
            gym: "Ostbloc"
        )
        let existingAttempts = ClimbEntry(
            climbType: .boulder,
            grade: "V6",
            style: "Slab",
            attempts: "3",
            gym: "Ostbloc"
        )

        context.insert(missingAttempts)
        context.insert(blankAttempts)
        context.insert(existingAttempts)
        try context.save()

        backfillClimbEntryAttempts(context)

        XCTAssertEqual(missingAttempts.attempts, "1")
        XCTAssertEqual(blankAttempts.attempts, "1")
        XCTAssertEqual(existingAttempts.attempts, "3")
    }

    func testBackfillPlanDayExerciseIDFieldsPreservesLegacyOrder() throws {
        let activity = createTestActivity(name: "Strength")
        let trainingType = createTestTrainingType(activity: activity, name: "Board")
        let hang = createTestExercise(trainingType: trainingType, name: "Hangboard")
        let campus = createTestExercise(trainingType: trainingType, name: "Campus Board")

        let plan = Plan(name: "ID Backfill", kind: nil, startDate: .now)
        let day = PlanDay(date: .now)
        day.chosenExercises = ["Campus Board", "Hangboard"]
        day.exerciseOrder = [
            "Campus Board": 0,
            "Hangboard": 1
        ]
        plan.days = [day]
        context.insert(plan)
        context.insert(day)
        try context.save()

        backfillPlanDayExerciseIDFields(context)

        XCTAssertEqual(day.chosenExerciseIDs, [campus.id, hang.id])
        XCTAssertEqual(day.exerciseOrderByID[campus.id.uuidString], 0)
        XCTAssertEqual(day.exerciseOrderByID[hang.id.uuidString], 1)
    }
}
