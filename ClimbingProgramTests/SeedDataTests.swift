//
//  SeedDataTests.swift
//  klettrack Tests
//
//  Created by Shahar Noy on 30.09.25.
//
import XCTest
import SwiftData
@testable import klettrack

final class SeedDataTests: BaseSwiftDataTestCase {
    func testBoulderingCombinationsSeeded() throws {
        SeedData.loadIfNeeded(context)
        let activities: [Activity] = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        let boulder = try XCTUnwrap(activities.first(where: { $0.name == "Bouldering" }))
        let types = boulder.types
        XCTAssertFalse(types.isEmpty)
        // At least one type should have non-empty combinations
        XCTAssertTrue(types.contains { !$0.combinations.isEmpty })
    }
    
    func testSeedClimbingDataAndTimerTemplates() {
        SeedClimbingData.loadIfNeeded(context)
        SeedTimerTemplates.loadIfNeeded(context)
        
        let stylesCount = (try? context.fetchCount(FetchDescriptor<ClimbStyle>())) ?? 0
        let gymsCount = (try? context.fetchCount(FetchDescriptor<ClimbGym>())) ?? 0
        let templatesCount = (try? context.fetchCount(FetchDescriptor<TimerTemplate>())) ?? 0
        
        XCTAssertGreaterThan(stylesCount, 0)
        XCTAssertGreaterThan(gymsCount, 0)
        XCTAssertGreaterThan(templatesCount, 0)
    }

    @MainActor
    func testCatalogReseedingPreservesRenamesAndUserFields() throws {
        SeedData.loadIfNeeded(context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let exercise = try XCTUnwrap(exercises.first(where: { $0.name == "Abdominal Crunches" }))
        let type = try XCTUnwrap(
            try context.fetch(FetchDescriptor<TrainingType>()).first(where: { $0.name == "Anterior Core" })
        )
        let originalID = exercise.id
        let seedKey = try XCTUnwrap(exercise.seedKey)

        exercise.name = "Crunches en français"
        exercise.repsText = "5"
        exercise.setsText = "9"
        type.typeDescription = "Description personnalisée"
        try context.save()

        SeedData.loadIfNeeded(context)

        let reloaded = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Exercise>()).first(where: { $0.id == originalID })
        )
        XCTAssertEqual(reloaded.seedKey, seedKey)
        XCTAssertEqual(reloaded.name, "Crunches en français")
        XCTAssertEqual(reloaded.repsText, "5")
        XCTAssertEqual(reloaded.setsText, "9")
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<TrainingType>()).first(where: { $0.id == type.id })?.typeDescription,
            "Description personnalisée"
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<Exercise>()).filter { $0.seedKey == seedKey }.count,
            1
        )
    }

    @MainActor
    func testDeletedSeededExerciseIsNotRecreated() throws {
        SeedData.loadIfNeeded(context)

        let activity = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Activity>()).first(where: { $0.name == "Core" })
        )
        let type = try XCTUnwrap(activity.types.first(where: { $0.name == "Anterior Core" }))
        let exercise = try XCTUnwrap(type.exercises.first(where: { $0.name == "Abdominal Crunches" }))
        let seedKey = try XCTUnwrap(exercise.seedKey)

        try CatalogDeletion.deleteExercisePlacement(exercise, from: type, sourceCombination: nil, in: context)
        SeedData.loadIfNeeded(context)

        XCTAssertTrue(
            try context.fetch(FetchDescriptor<Exercise>()).filter { $0.seedKey == seedKey }.isEmpty
        )
        XCTAssertNotNil(
            try context.fetch(FetchDescriptor<DeletedCatalogSeed>()).first(where: { $0.seedKey == seedKey })
        )
    }

    @MainActor
    func testHingeExercisesHaveDistinctStableKeys() throws {
        SeedData.loadIfNeeded(context)

        let hinge = try XCTUnwrap(
            try context.fetch(FetchDescriptor<TrainingType>()).first(where: { $0.seedKey == "type.general_strength.hinge" })
        )
        let seated = try XCTUnwrap(hinge.exercises.first(where: { $0.name == "Seated Straddle Good Mornings" }))
        let bulgarian = try XCTUnwrap(hinge.exercises.first(where: { $0.name == "Bulgarian Deadlift" }))
        let seatedKey = try XCTUnwrap(seated.seedKey)
        let bulgarianKey = try XCTUnwrap(bulgarian.seedKey)

        XCTAssertNotEqual(seatedKey, bulgarianKey)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<Exercise>()).filter { $0.seedKey == seatedKey || $0.seedKey == bulgarianKey }.count,
            2
        )

        SeedData.loadIfNeeded(context)

        XCTAssertEqual(hinge.exercises.filter { $0.name == "Seated Straddle Good Mornings" }.count, 1)
        XCTAssertEqual(hinge.exercises.filter { $0.name == "Bulgarian Deadlift" }.count, 1)
    }

    @MainActor
    func testBuiltInExerciseSeedKeysAreUnique() throws {
        SeedData.loadIfNeeded(context)

        let keys = try context.fetch(FetchDescriptor<Exercise>()).compactMap(\.seedKey)

        XCTAssertFalse(keys.isEmpty)
        XCTAssertEqual(keys.count, Set(keys).count)
    }

    @MainActor
    func testMovedBuiltInExerciseIsNotRecreatedInOriginalType() throws {
        SeedData.loadIfNeeded(context)

        let core = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Activity>()).first(where: { $0.seedKey == "activity.core" })
        )
        let anterior = try XCTUnwrap(core.types.first(where: { $0.seedKey == "type.core.anterior_core" }))
        let posterior = try XCTUnwrap(core.types.first(where: { $0.seedKey == "type.core.posterior_core" }))
        let exercise = try XCTUnwrap(
            anterior.exercises.first(where: { $0.seedKey == "exercise.core.anterior_core.abdominal_crunches" })
        )
        let destination = CatalogReassignment.Destination(
            id: posterior.id,
            activityName: core.name,
            typeName: posterior.name,
            name: posterior.name,
            kind: .trainingType,
            type: posterior,
            combination: nil
        )

        try CatalogReassignment.move(
            exercise,
            from: anterior,
            sourceCombination: nil,
            to: destination,
            in: context
        )
        SeedData.loadIfNeeded(context)

        XCTAssertFalse(anterior.exercises.contains(where: { $0.id == exercise.id }))
        XCTAssertTrue(posterior.exercises.contains(where: { $0.id == exercise.id }))
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<Exercise>()).filter {
                $0.seedKey == "exercise.core.anterior_core.abdominal_crunches"
            }.count,
            1
        )
    }

    @MainActor
    func testMovedBuiltInCombinationExerciseIsNotRecreated() throws {
        SeedData.loadIfNeeded(context)

        let boulder = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Activity>()).first(where: { $0.seedKey == "activity.bouldering" })
        )
        let maximumStrength = try XCTUnwrap(
            boulder.types.first(where: { $0.seedKey == "type.bouldering.maximum_contact_strength" })
        )
        let strengthEndurance = try XCTUnwrap(
            boulder.types.first(where: { $0.seedKey == "type.bouldering.strength_endurance" })
        )
        let limitCombination = try XCTUnwrap(
            maximumStrength.combinations.first(where: { $0.seedKey == "combination.bouldering.maximum_contact.limit" })
        )
        let exercise = try XCTUnwrap(
            limitCombination.exercises.first(where: {
                $0.seedKey == "exercise.bouldering.maximum_contact.limit.near_maximal_boulders"
            })
        )
        let destination = CatalogReassignment.Destination(
            id: strengthEndurance.id,
            activityName: boulder.name,
            typeName: strengthEndurance.name,
            name: strengthEndurance.name,
            kind: .trainingType,
            type: strengthEndurance,
            combination: nil
        )

        try CatalogReassignment.move(
            exercise,
            from: nil,
            sourceCombination: limitCombination,
            to: destination,
            in: context
        )
        SeedData.loadIfNeeded(context)

        XCTAssertFalse(limitCombination.exercises.contains(where: { $0.id == exercise.id }))
        XCTAssertTrue(strengthEndurance.exercises.contains(where: { $0.id == exercise.id }))
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<Exercise>()).filter {
                $0.seedKey == "exercise.bouldering.maximum_contact.limit.near_maximal_boulders"
            }.count,
            1
        )
    }
}
