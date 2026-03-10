//
//  CatalogPickerModels.swift
//  Klettrack
//  Created by Shahar Noy on 10.03.26.
//
import SwiftUI
import SwiftData

struct ExerciseHit: Identifiable {
    let id: UUID
    let name: String
    let subtitle: String?
    let tint: Color
    let repsText: String?
    let setsText: String?
    let restText: String?
    let durationText: String?

    init(
        id: UUID,
        name: String,
        subtitle: String?,
        tint: Color,
        repsText: String?,
        setsText: String?,
        restText: String?,
        durationText: String?
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.tint = tint
        self.repsText = repsText
        self.setsText = setsText
        self.restText = restText
        self.durationText = durationText
    }
}

struct CatalogExerciseNode: Identifiable, Equatable {
    let id: UUID
    let name: String
    let area: String?
    let order: Int
    let subtitle: String?
    let repsText: String?
    let setsText: String?
    let restText: String?
    let durationText: String?
}

struct CatalogComboNode: Identifiable, Equatable {
    let id: UUID
    let name: String
    let comboDescription: String?
    let exercises: [CatalogExerciseNode]
}

struct CatalogTypeNode: Identifiable, Equatable {
    let id: UUID
    let name: String
    let typeDescription: String?
    let exercises: [CatalogExerciseNode]
    let combinations: [CatalogComboNode]
}

struct CatalogActivityNode: Identifiable, Equatable {
    let id: UUID
    let name: String
    let tint: Color
    let types: [CatalogTypeNode]
}

@MainActor
func makeCatalogActivityNodes(from activities: [Activity]) -> [CatalogActivityNode] {
    activities.compactMap(makeCatalogActivityNode)
}

@MainActor
private func makeCatalogActivityNode(from activity: Activity) -> CatalogActivityNode? {
    guard !activity.isSoftDeleted else { return nil }

    let types = activity.types
        .filter { !$0.isSoftDeleted }
        .map(makeCatalogTypeNode)
        .sorted(by: compareCatalogTypeNodes)

    return CatalogActivityNode(
        id: activity.id,
        name: activity.name,
        tint: activity.hue.color,
        types: types
    )
}

@MainActor
private func makeCatalogTypeNode(from trainingType: TrainingType) -> CatalogTypeNode {
    let exercises = trainingType.exercises
        .filter { !$0.isSoftDeleted }
        .map(makeCatalogExerciseNode)
        .sorted(by: compareCatalogExerciseNodes)

    let combinations = trainingType.combinations
        .filter { !$0.isSoftDeleted }
        .map(makeCatalogComboNode)
        .sorted(by: compareCatalogComboNodes)

    return CatalogTypeNode(
        id: trainingType.id,
        name: trainingType.name,
        typeDescription: trainingType.typeDescription,
        exercises: exercises,
        combinations: combinations
    )
}

@MainActor
private func makeCatalogComboNode(from combo: BoulderCombination) -> CatalogComboNode {
    let exercises = combo.exercises
        .filter { !$0.isSoftDeleted }
        .map(makeCatalogExerciseNode)
        .sorted(by: compareCatalogExerciseNodes)

    return CatalogComboNode(
        id: combo.id,
        name: combo.name,
        comboDescription: combo.comboDescription,
        exercises: exercises
    )
}

@MainActor
private func makeCatalogExerciseNode(from exercise: Exercise) -> CatalogExerciseNode {
    CatalogExerciseNode(
        id: exercise.id,
        name: exercise.name,
        area: exercise.area,
        order: exercise.order,
        subtitle: exercise.exerciseDescription?.isEmpty == false ? exercise.exerciseDescription : exercise.notes,
        repsText: exercise.repsText,
        setsText: exercise.setsText,
        restText: exercise.restText,
        durationText: exercise.durationText
    )
}

private func compareCatalogExerciseNodes(_ lhs: CatalogExerciseNode, _ rhs: CatalogExerciseNode) -> Bool {
    if lhs.order != rhs.order {
        return lhs.order < rhs.order
    }
    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
}

private func compareCatalogComboNodes(_ lhs: CatalogComboNode, _ rhs: CatalogComboNode) -> Bool {
    lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
}

private func compareCatalogTypeNodes(_ lhs: CatalogTypeNode, _ rhs: CatalogTypeNode) -> Bool {
    lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
}
