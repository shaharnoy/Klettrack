//
//  PlanDayCatalogRenderPathTests.swift
//  klettrack Tests
//
//  Created by Codex on 22.02.26.
//

import XCTest
import SwiftData
@testable import klettrack

@MainActor
final class PlanDayCatalogRenderPathTests: BaseSwiftDataTestCase {

    func testGroupingFunctionalBehavior_ManualOrderLoggedAndCatalogFallback() throws {
        let strength = Activity(name: "Strength")
        context.insert(strength)
        let strengthType = TrainingType(name: "Strength Type")
        strength.types.append(strengthType)
        strengthType.exercises.append(Exercise(name: "Push", order: 2))
        strengthType.exercises.append(Exercise(name: "Pull", order: 1))
        strengthType.exercises.append(Exercise(name: "Core", order: 3))

        let conditioning = Activity(name: "Conditioning")
        context.insert(conditioning)
        let conditioningType = TrainingType(name: "Conditioning Type")
        conditioning.types.append(conditioningType)
        conditioningType.exercises.append(Exercise(name: "Zeta", order: 20))
        conditioningType.exercises.append(Exercise(name: "Alpha", order: 10))

        let day = PlanDay(date: .now)
        day.chosenExercises = ["Push", "Pull", "Core", "Zeta", "Alpha"]
        day.exerciseOrder = ["Core": 0, "Push": 1]

        let grouped = groupedChosenExercises(day: day, loggedExerciseNames: Set(["Pull"]))
        XCTAssertEqual(grouped.map { $0.activityName }, ["Conditioning", "Strength"])

        let conditioningExercises = try XCTUnwrap(grouped.first(where: { $0.activityName == "Conditioning" })?.exercises)
        let strengthExercises = try XCTUnwrap(grouped.first(where: { $0.activityName == "Strength" })?.exercises)

        // Conditioning: no manual order and no logged entries -> catalog order fallback.
        XCTAssertEqual(conditioningExercises, ["Alpha", "Zeta"])
        // Strength: manual order is used when both sides have explicit values, then logged fallback.
        XCTAssertEqual(strengthExercises, ["Core", "Push", "Pull"])
    }

    func testGroupingReflectsCatalogChangesAfterRecompute() throws {
        let activity = Activity(name: "Original")
        context.insert(activity)
        let type = TrainingType(name: "Type")
        activity.types.append(type)
        type.exercises.append(Exercise(name: "Repeaters", order: 1))

        let day = PlanDay(date: .now)
        day.chosenExercises = ["Repeaters"]

        let beforeRename = groupedChosenExercises(day: day, loggedExerciseNames: Set())
        XCTAssertEqual(beforeRename.first?.activityName, "Original")

        activity.name = "Renamed"

        let afterRename = groupedChosenExercises(day: day, loggedExerciseNames: Set())
        XCTAssertEqual(afterRename.first?.activityName, "Renamed")
    }

    func testGlobalOrderAllowsCrossActivityPlacement() throws {
        let general = Activity(name: "General Strength")
        context.insert(general)
        let generalType = TrainingType(name: "Strength Type")
        general.types.append(generalType)
        generalType.exercises.append(Exercise(name: "GS 1", order: 0))
        generalType.exercises.append(Exercise(name: "GS 2", order: 1))
        generalType.exercises.append(Exercise(name: "GS 3", order: 2))
        generalType.exercises.append(Exercise(name: "GS 4", order: 3))
        generalType.exercises.append(Exercise(name: "GS 5", order: 4))
        generalType.exercises.append(Exercise(name: "GS 6", order: 5))

        let core = Activity(name: "Core")
        context.insert(core)
        let coreType = TrainingType(name: "Core Type")
        core.types.append(coreType)
        coreType.exercises.append(Exercise(name: "Plank", order: 0))

        let day = PlanDay(date: .now)
        day.chosenExercises = ["GS 1", "GS 2", "GS 3", "GS 4", "GS 5", "GS 6", "Plank"]
        day.exerciseOrder = [
            "GS 1": 0,
            "GS 2": 1,
            "GS 3": 2,
            "Plank": 3,
            "GS 4": 4,
            "GS 5": 5,
            "GS 6": 6
        ]

        let ordered = globallyOrderedExercises(day: day, loggedExerciseNames: Set())

        XCTAssertEqual(
            ordered.map(\.name),
            ["GS 1", "GS 2", "GS 3", "Plank", "GS 4", "GS 5", "GS 6"]
        )
        XCTAssertEqual(ordered[3].activityName, "Core")
    }

    func testGroupingHeavyLoadPerformance() throws {
        let allExerciseNames = seedLargeCatalogForRenderPathStress(
            activityCount: 40,
            typesPerActivity: 4,
            exercisesPerType: 8
        )

        let day = PlanDay(date: .now)
        day.chosenExercises = Array(allExerciseNames.prefix(320))
        day.exerciseOrder = Dictionary(uniqueKeysWithValues: day.chosenExercises.prefix(40).enumerated().map { idx, name in
            (name, idx)
        })
        let logged = Set(day.chosenExercises.suffix(80))

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            var totalGroupedCount = 0
            for _ in 0..<15 {
                totalGroupedCount += groupedChosenExercises(day: day, loggedExerciseNames: logged).count
            }
            XCTAssertGreaterThan(totalGroupedCount, 0)
        }
    }

    // MARK: - Helpers

    private typealias GroupedExercises = (activityName: String, exercises: [String])
    private typealias OrderedExercise = (name: String, activityName: String)

    private func groupedChosenExercises(day: PlanDay, loggedExerciseNames: Set<String>) -> [GroupedExercises] {
        let activityDescriptor = FetchDescriptor<Activity>()
        let allActivities = (try? context.fetch(activityDescriptor)) ?? []

        var exerciseToActivityMap: [String: (activityName: String, order: Int)] = [:]

        for activity in allActivities {
            for trainingType in activity.types {
                for exercise in trainingType.exercises {
                    upsertExerciseMapping(
                        map: &exerciseToActivityMap,
                        exerciseName: exercise.name,
                        activityName: activity.name,
                        order: exercise.order
                    )
                }

                for combination in trainingType.combinations {
                    for exercise in combination.exercises {
                        upsertExerciseMapping(
                            map: &exerciseToActivityMap,
                            exerciseName: exercise.name,
                            activityName: activity.name,
                            order: exercise.order
                        )
                    }
                }
            }
        }

        let groupedByActivity = Dictionary(grouping: day.chosenExercises) { exerciseName in
            exerciseToActivityMap[exerciseName]?.activityName ?? "Unknown"
        }

        var result: [GroupedExercises] = []
        for (activityName, exerciseNames) in groupedByActivity {
            let sortedExercises = exerciseNames.sorted { lhs, rhs in
                let manualLeft = day.exerciseOrder[lhs]
                let manualRight = day.exerciseOrder[rhs]
                if let manualLeft, let manualRight, manualLeft != manualRight {
                    return manualLeft < manualRight
                }

                let leftIsLogged = loggedExerciseNames.contains(lhs)
                let rightIsLogged = loggedExerciseNames.contains(rhs)
                if leftIsLogged != rightIsLogged {
                    return !leftIsLogged
                }

                let orderLeft = exerciseToActivityMap[lhs]?.order ?? Int.max
                let orderRight = exerciseToActivityMap[rhs]?.order ?? Int.max
                return orderLeft < orderRight
            }
            result.append((activityName: activityName, exercises: sortedExercises))
        }

        return result.sorted { $0.activityName < $1.activityName }
    }

    private func globallyOrderedExercises(day: PlanDay, loggedExerciseNames: Set<String>) -> [OrderedExercise] {
        let activityDescriptor = FetchDescriptor<Activity>()
        let allActivities = (try? context.fetch(activityDescriptor)) ?? []

        var exerciseToActivityMap: [String: (activityName: String, order: Int)] = [:]

        for activity in allActivities {
            for trainingType in activity.types {
                for exercise in trainingType.exercises {
                    upsertExerciseMapping(
                        map: &exerciseToActivityMap,
                        exerciseName: exercise.name,
                        activityName: activity.name,
                        order: exercise.order
                    )
                }

                for combination in trainingType.combinations {
                    for exercise in combination.exercises {
                        upsertExerciseMapping(
                            map: &exerciseToActivityMap,
                            exerciseName: exercise.name,
                            activityName: activity.name,
                            order: exercise.order
                        )
                    }
                }
            }
        }

        let orderedNames = day.chosenExercises.sorted { lhs, rhs in
            let manualLeft = day.exerciseOrder[lhs]
            let manualRight = day.exerciseOrder[rhs]
            if let manualLeft, let manualRight, manualLeft != manualRight {
                return manualLeft < manualRight
            }
            if manualLeft != nil { return true }
            if manualRight != nil { return false }

            let leftIsLogged = loggedExerciseNames.contains(lhs)
            let rightIsLogged = loggedExerciseNames.contains(rhs)
            if leftIsLogged != rightIsLogged {
                return !leftIsLogged
            }

            let orderLeft = exerciseToActivityMap[lhs]?.order ?? Int.max
            let orderRight = exerciseToActivityMap[rhs]?.order ?? Int.max
            if orderLeft != orderRight {
                return orderLeft < orderRight
            }

            let activityLeft = exerciseToActivityMap[lhs]?.activityName ?? "Unknown"
            let activityRight = exerciseToActivityMap[rhs]?.activityName ?? "Unknown"
            if activityLeft != activityRight {
                return activityLeft < activityRight
            }

            return lhs < rhs
        }

        return orderedNames.map { name in
            (name: name, activityName: exerciseToActivityMap[name]?.activityName ?? "Unknown")
        }
    }

    private func upsertExerciseMapping(
        map: inout [String: (activityName: String, order: Int)],
        exerciseName: String,
        activityName: String,
        order: Int
    ) {
        if let existing = map[exerciseName], existing.order <= order {
            return
        }
        map[exerciseName] = (activityName: activityName, order: order)
    }

    private func seedLargeCatalogForRenderPathStress(
        activityCount: Int,
        typesPerActivity: Int,
        exercisesPerType: Int
    ) -> [String] {
        var names: [String] = []
        var order = 0

        for activityIndex in 0..<activityCount {
            let activity = Activity(name: "Activity \(activityIndex)")
            context.insert(activity)

            for typeIndex in 0..<typesPerActivity {
                let type = TrainingType(name: "Type \(activityIndex)-\(typeIndex)")
                activity.types.append(type)

                for exerciseIndex in 0..<exercisesPerType {
                    let name = "Exercise \(activityIndex)-\(typeIndex)-\(exerciseIndex)"
                    type.exercises.append(Exercise(name: name, order: order))
                    names.append(name)
                    order += 1
                }
            }
        }

        try? context.save()
        return names
    }
}
