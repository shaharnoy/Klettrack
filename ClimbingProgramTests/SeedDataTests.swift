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
    private enum TestFailure: Error {
        case expected
    }

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

    @MainActor
    func testManifestAndPersistedSeedKeysAreUniqueAndComplete() throws {
        let manifest = SeedData.catalogManifest()
        XCTAssertTrue(manifest.duplicateKeys().isEmpty)

        SeedData.loadIfNeeded(context)

        let persistedKeys = try context.fetch(FetchDescriptor<Activity>()).compactMap(\.seedKey)
            + context.fetch(FetchDescriptor<TrainingType>()).compactMap(\.seedKey)
            + context.fetch(FetchDescriptor<BoulderCombination>()).compactMap(\.seedKey)
            + context.fetch(FetchDescriptor<Exercise>()).compactMap(\.seedKey)
        XCTAssertEqual(Set(persistedKeys), Set(manifest.allKeys))
        XCTAssertEqual(persistedKeys.count, manifest.allKeys.count)
    }

    @MainActor
    func testLegacyRenamedExerciseIsClaimedByUniqueStructure() throws {
        let activity = Activity(name: "Core")
        let type = TrainingType(name: "Anterior Core", typeDescription: "")
        let exercise = Exercise(
            name: "Crunches personnalisés",
            order: 1,
            repsText: "25-100",
            setsText: "2",
            restText: "3 min"
        )
        type.exercises.append(exercise)
        activity.types.append(type)
        context.insert(activity)
        try context.save()
        let originalID = exercise.id

        let report = SeedData.loadIfNeeded(context)

        let claimed = try XCTUnwrap(try context.fetch(FetchDescriptor<Exercise>()).first { $0.id == originalID })
        XCTAssertEqual(claimed.seedKey, "exercise.core.anterior_core.abdominal_crunches")
        XCTAssertEqual(claimed.name, "Crunches personnalisés")
        XCTAssertGreaterThanOrEqual(report.claimed, 3)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<Exercise>()).filter {
                $0.seedKey == "exercise.core.anterior_core.abdominal_crunches"
            }.count,
            1
        )
    }

    @MainActor
    func testAmbiguousLegacyExercisesRemainUserOwned() throws {
        let activity = Activity(name: "Core")
        let type = TrainingType(name: "Anterior Core", typeDescription: "")
        let first = Exercise(name: "Custom One", order: 1, repsText: "25-100", setsText: "2", restText: "3 min")
        let second = Exercise(name: "Custom Two", order: 1, repsText: "25-100", setsText: "2", restText: "3 min")
        type.exercises = [first, second]
        activity.types.append(type)
        context.insert(activity)
        try context.save()

        SeedData.loadIfNeeded(context)

        XCTAssertNil(first.seedKey)
        XCTAssertNil(second.seedKey)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<Exercise>()).filter {
                $0.seedKey == "exercise.core.anterior_core.abdominal_crunches"
            }.count,
            1
        )
    }

    @MainActor
    func testRecognizedDefaultAndRenamedCustomRowAreNotMerged() throws {
        let activity = Activity(name: "Core")
        let type = TrainingType(name: "Anterior Core", typeDescription: "")
        let recognized = Exercise(
            name: "Abdominal Crunches",
            order: 1,
            repsText: "25-100",
            setsText: "2",
            restText: "3 min"
        )
        let custom = Exercise(
            name: "My Crunch Variation",
            order: 1,
            repsText: "25-100",
            setsText: "2",
            restText: "3 min"
        )
        type.exercises = [recognized, custom]
        activity.types.append(type)
        context.insert(activity)
        try context.save()

        SeedData.loadIfNeeded(context)

        XCTAssertEqual(recognized.seedKey, "exercise.core.anterior_core.abdominal_crunches")
        XCTAssertNil(custom.seedKey)
        XCTAssertEqual(custom.name, "My Crunch Variation")
        XCTAssertNotEqual(recognized.id, custom.id)
    }

    @MainActor
    func testRenamedContainersAreClaimedByRecognizableDescendants() throws {
        let exerciseSeed = CatalogExerciseSeed(
            key: "exercise.test.child",
            name: "Expected Exercise",
            aliases: [],
            order: 0,
            area: nil,
            exerciseDescription: nil,
            reps: nil,
            duration: nil,
            sets: nil,
            rest: nil,
            notes: nil
        )

        let activitySeed = CatalogActivitySeed(key: "activity.test.renamed", name: "Expected Activity")
        activitySeed.types.append(CatalogTypeSeed(key: "type.test.activity_child", name: "Expected Type"))

        let typeActivitySeed = CatalogActivitySeed(key: "activity.test.type_parent", name: "Type Parent")
        let renamedTypeSeed = CatalogTypeSeed(key: "type.test.renamed", name: "Expected Renamed Type")
        renamedTypeSeed.exercises.append(exerciseSeed)
        typeActivitySeed.types.append(renamedTypeSeed)

        let combinationActivitySeed = CatalogActivitySeed(key: "activity.test.combo_parent", name: "Combination Parent")
        let combinationTypeSeed = CatalogTypeSeed(key: "type.test.combo_parent", name: "Combination Type")
        let renamedCombinationSeed = CatalogCombinationSeed(key: "combination.test.renamed", name: "Expected Combination")
        renamedCombinationSeed.exercises.append(
            CatalogExerciseSeed(
                key: "exercise.test.combo_child",
                name: "Expected Combo Exercise",
                aliases: [],
                order: 0,
                area: nil,
                exerciseDescription: nil,
                reps: nil,
                duration: nil,
                sets: nil,
                rest: nil,
                notes: nil
            )
        )
        combinationTypeSeed.combinations.append(renamedCombinationSeed)
        combinationActivitySeed.types.append(combinationTypeSeed)

        let renamedActivity = Activity(name: "User Activity Name")
        renamedActivity.types.append(TrainingType(name: "Expected Type"))
        let typeParent = Activity(name: "Type Parent")
        let renamedType = TrainingType(name: "User Type Name", typeDescription: "User description")
        renamedType.exercises.append(Exercise(name: "Expected Exercise"))
        typeParent.types.append(renamedType)
        let comboParent = Activity(name: "Combination Parent")
        let comboType = TrainingType(name: "Combination Type")
        let renamedCombination = BoulderCombination(name: "User Combination Name", comboDescription: "User description")
        renamedCombination.exercises.append(Exercise(name: "Expected Combo Exercise"))
        comboType.combinations.append(renamedCombination)
        comboParent.types.append(comboType)
        context.insert(renamedActivity)
        context.insert(typeParent)
        context.insert(comboParent)
        try context.save()

        let manifest = CatalogSeedManifest(
            activities: [activitySeed, typeActivitySeed, combinationActivitySeed]
        )
        let report = CatalogSeeder.reconcile(manifest, in: context)

        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertEqual(renamedActivity.seedKey, activitySeed.key)
        XCTAssertEqual(renamedActivity.name, "User Activity Name")
        XCTAssertEqual(renamedType.seedKey, renamedTypeSeed.key)
        XCTAssertEqual(renamedType.typeDescription, "User description")
        XCTAssertEqual(renamedCombination.seedKey, renamedCombinationSeed.key)
        XCTAssertEqual(renamedCombination.comboDescription, "User description")
    }

    @MainActor
    func testCatalogReconciliationIsIdempotent() throws {
        let firstReport = SeedData.loadIfNeeded(context)
        let firstCounts = (
            try context.fetchCount(FetchDescriptor<Activity>()),
            try context.fetchCount(FetchDescriptor<TrainingType>()),
            try context.fetchCount(FetchDescriptor<BoulderCombination>()),
            try context.fetchCount(FetchDescriptor<Exercise>())
        )

        let secondReport = SeedData.loadIfNeeded(context)
        let secondCounts = (
            try context.fetchCount(FetchDescriptor<Activity>()),
            try context.fetchCount(FetchDescriptor<TrainingType>()),
            try context.fetchCount(FetchDescriptor<BoulderCombination>()),
            try context.fetchCount(FetchDescriptor<Exercise>())
        )

        XCTAssertGreaterThan(firstReport.inserted, 0)
        XCTAssertEqual(secondReport.inserted, 0)
        XCTAssertEqual(secondReport.claimed, 0)
        XCTAssertEqual(firstCounts.0, secondCounts.0)
        XCTAssertEqual(firstCounts.1, secondCounts.1)
        XCTAssertEqual(firstCounts.2, secondCounts.2)
        XCTAssertEqual(firstCounts.3, secondCounts.3)
    }

    @MainActor
    func testDeletedSeededParentsAreNotRecreated() throws {
        SeedData.loadIfNeeded(context)
        let core = try XCTUnwrap(try context.fetch(FetchDescriptor<Activity>()).first { $0.seedKey == "activity.core" })
        try CatalogDeletion.delete(.activity(core), in: context)
        SeedData.loadIfNeeded(context)
        XCTAssertNil(try context.fetch(FetchDescriptor<Activity>()).first { $0.seedKey == "activity.core" })

        let bouldering = try XCTUnwrap(try context.fetch(FetchDescriptor<Activity>()).first { $0.seedKey == "activity.bouldering" })
        let skill = try XCTUnwrap(bouldering.types.first { $0.seedKey == "type.bouldering.skill_training" })
        try CatalogDeletion.delete(.trainingType(skill), in: context)
        SeedData.loadIfNeeded(context)
        XCTAssertNil(try context.fetch(FetchDescriptor<TrainingType>()).first { $0.seedKey == "type.bouldering.skill_training" })

        let maximum = try XCTUnwrap(bouldering.types.first { $0.seedKey == "type.bouldering.maximum_contact_strength" })
        let styles = try XCTUnwrap(maximum.combinations.first { $0.seedKey == "combination.bouldering.maximum_contact.styles" })
        try CatalogDeletion.delete(.combination(styles), in: context)
        SeedData.loadIfNeeded(context)
        XCTAssertNil(try context.fetch(FetchDescriptor<BoulderCombination>()).first { $0.seedKey == "combination.bouldering.maximum_contact.styles" })
    }

    @MainActor
    func testSameNamedCustomExerciseIsNotClaimedAfterSeedDeletion() throws {
        SeedData.loadIfNeeded(context)
        let type = try XCTUnwrap(
            try context.fetch(FetchDescriptor<TrainingType>()).first { $0.seedKey == "type.core.anterior_core" }
        )
        let seeded = try XCTUnwrap(type.exercises.first { $0.seedKey == "exercise.core.anterior_core.abdominal_crunches" })
        try CatalogDeletion.deleteExercisePlacement(seeded, from: type, sourceCombination: nil, in: context)

        let custom = Exercise(name: "Abdominal Crunches")
        type.exercises.append(custom)
        try context.save()
        SeedData.loadIfNeeded(context)

        XCTAssertNil(custom.seedKey)
        XCTAssertEqual(type.exercises.filter { $0.name == "Abdominal Crunches" }.count, 1)
    }

    @MainActor
    func testTombstoneRecordingIsIdempotent() throws {
        try CatalogSeedTombstoneStore.record("exercise.test", in: context)
        try CatalogSeedTombstoneStore.record("exercise.test", in: context)
        try context.save()

        XCTAssertEqual(
            try context.fetch(FetchDescriptor<DeletedCatalogSeed>()).filter { $0.seedKey == "exercise.test" }.count,
            1
        )
    }

    @MainActor
    func testTombstoneFetchFailureStopsCatalogMutation() throws {
        let report = CatalogSeeder.reconcile(
            SeedData.catalogManifest(),
            in: context,
            loadTombstones: { _ in throw TestFailure.expected }
        )

        XCTAssertEqual(report.issues.count, 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Activity>()).isEmpty)
    }

    @MainActor
    func testSaveFailureRollsBackAffectedRootAndContinues() throws {
        let builder = CatalogSeedManifestBuilder()
        _ = builder.activity("First", key: "activity.first")
        _ = builder.activity("Second", key: "activity.second")
        var saveCount = 0

        let report = CatalogSeeder.reconcile(
            builder.manifest,
            in: context,
            save: { modelContext in
                saveCount += 1
                if saveCount == 1 { throw TestFailure.expected }
                try modelContext.save()
            }
        )

        let activities = try context.fetch(FetchDescriptor<Activity>())
        XCTAssertEqual(report.issues.count, 1)
        XCTAssertNil(activities.first { $0.seedKey == "activity.first" })
        XCTAssertNotNil(activities.first { $0.seedKey == "activity.second" })
    }
}
