import XCTest
import SwiftData
@testable import klettrack

@MainActor
final class CatalogPersistenceTests: BaseSwiftDataTestCase {
    func testNewExercisePersistsAllDisplayFieldsAcrossRefetch() throws {
        let activity = createTestActivity(name: "Core")
        let trainingType = createTestTrainingType(activity: activity, name: "Test Type")
        let draft = CatalogExerciseDraft(
            name: "  Timed Set  ",
            area: "",
            reps: "8-10",
            sets: "3",
            duration: "45 sec",
            rest: "2 min",
            notes: "controlled",
            description: "test exercise"
        )
        let exercise = draft.makeExercise(order: 1)
        trainingType.exercises.append(exercise)

        try CatalogExercisePersistence.saveNew(exercise, in: context)

        let reloadedContext = ModelContext(container)
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.name == "Timed Set" }
        )
        let reloaded = try XCTUnwrap(try reloadedContext.fetch(descriptor).first)

        XCTAssertEqual(reloaded.repsText, "8-10")
        XCTAssertEqual(reloaded.setsText, "3")
        XCTAssertEqual(reloaded.durationText, "45 sec")
        XCTAssertEqual(reloaded.restText, "2 min")
        XCTAssertEqual(reloaded.notes, "controlled")
        XCTAssertEqual(reloaded.exerciseDescription, "test exercise")
    }

    func testEditingExercisePersistsDurationWhenSetsAreEmpty() throws {
        let exercise = Exercise(name: "Existing", durationText: "10 sec", setsText: "3")
        context.insert(exercise)
        try context.save()

        let draft = CatalogExerciseDraft(
            name: "Existing",
            area: "",
            reps: "",
            sets: "",
            duration: "60 sec",
            rest: "90 sec",
            notes: "",
            description: ""
        )
        draft.apply(to: exercise)
        try CatalogExercisePersistence.saveExisting(exercise, in: context)

        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.id == exerciseID }
        )
        let reloaded = try XCTUnwrap(try context.fetch(descriptor).first)
        XCTAssertNil(reloaded.setsText)
        XCTAssertEqual(reloaded.durationText, "60 sec")
        XCTAssertEqual(reloaded.restText, "90 sec")
    }

    func testCatalogColorResolverFindsExerciseAddedAfterWarmSnapshot() {
        let activity = createTestActivity(name: "Core")
        let trainingType = createTestTrainingType(activity: activity, name: "Test Type")
        let initial = Exercise(name: "Initial")
        trainingType.exercises.append(initial)

        let warmSnapshot = CatalogColorResolver.hueByExerciseName(from: [activity])
        XCTAssertEqual(warmSnapshot["Initial"], .core)
        XCTAssertNil(warmSnapshot["Added Later"])

        trainingType.exercises.append(Exercise(name: "Added Later"))
        let refreshedSnapshot = CatalogColorResolver.hueByExerciseName(from: [activity])

        XCTAssertEqual(refreshedSnapshot["Added Later"], .core)
    }
}
