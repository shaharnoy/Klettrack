//
//  CatalogExercisePickerSnapshotTests.swift
//  klettrack Tests
//
//  Created by Shahar Noy on 10.03.26.
//

import XCTest
import SwiftData
@testable import klettrack

@MainActor
final class CatalogExercisePickerSnapshotTests: BaseSwiftDataTestCase {

    func testSnapshotBuilderFiltersSoftDeletedContent() throws {
        let activity = Activity(name: "Strength")
        context.insert(activity)

        let activeType = TrainingType(name: "Pull")
        let deletedType = TrainingType(name: "Deleted Type")
        deletedType.isSoftDeleted = true

        activity.types.append(activeType)
        activity.types.append(deletedType)

        let activeExercise = Exercise(name: "Pull-up", order: 1)
        let deletedExercise = Exercise(name: "Removed", order: 2)
        deletedExercise.isSoftDeleted = true
        activeType.exercises.append(activeExercise)
        activeType.exercises.append(deletedExercise)

        let combo = BoulderCombination(name: "Combo")
        let comboExercise = Exercise(name: "Lock Off", order: 0)
        let deletedComboExercise = Exercise(name: "Ghost", order: 1)
        deletedComboExercise.isSoftDeleted = true
        combo.exercises.append(comboExercise)
        combo.exercises.append(deletedComboExercise)
        activeType.combinations.append(combo)

        let snapshots = makeCatalogActivityNodes(from: [activity])

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].types.map(\.name), ["Pull"])
        XCTAssertEqual(snapshots[0].types[0].exercises.map(\.name), ["Pull-up"])
        XCTAssertEqual(snapshots[0].types[0].combinations.map(\.name), ["Combo"])
        XCTAssertEqual(snapshots[0].types[0].combinations[0].exercises.map(\.name), ["Lock Off"])
    }

    func testSnapshotBuilderKeepsExerciseOrderingStable() throws {
        let activity = Activity(name: "Climbing")
        context.insert(activity)

        let type = TrainingType(name: "Board")
        activity.types.append(type)

        type.exercises.append(Exercise(name: "Zeta", area: "Pull", order: 3))
        type.exercises.append(Exercise(name: "Alpha", area: "Pull", order: 1))
        type.exercises.append(Exercise(name: "Beta", area: "Pull", order: 1))

        let snapshots = makeCatalogActivityNodes(from: [activity])
        let names = try XCTUnwrap(snapshots.first?.types.first?.exercises.map(\.name))

        XCTAssertEqual(names, ["Alpha", "Beta", "Zeta"])
    }
}
