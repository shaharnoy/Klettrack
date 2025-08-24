//
//  Models.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//

import Foundation
import SwiftData

@Model
final class Activity {
    @Attribute(.unique) var id: UUID
    var name: String
    var types: [TrainingType] = []

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

@Model
final class TrainingType {
    @Attribute(.unique) var id: UUID
    var name: String
    var area: String?
    /// NEW: rich description for this training type
    var typeDescription: String?

    /// Default path: exercises belong directly to a TrainingType
    var exercises: [Exercise] = []

    /// Bouldering-only path: extra level between type and exercises
    /// If non-empty, UI will present these combinations instead of `exercises`.
    var combinations: [BoulderCombination] = []

    init(
        id: UUID = UUID(),
        name: String,
        area: String? = nil,
        typeDescription: String? = nil
    ) {
        self.id = id
        self.name = name
        self.area = area
        self.typeDescription = typeDescription
    }
}

@Model
final class BoulderCombination {
    @Attribute(.unique) var id: UUID
    var name: String
    var comboDescription: String?
    var exercises: [Exercise] = []

    init(id: UUID = UUID(), name: String, comboDescription: String? = nil) {
        self.id = id
        self.name = name
        self.comboDescription = comboDescription
    }
}

@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var area: String?

    /// NEW: rich description for the exercise
    var exerciseDescription: String?

    /// Display fields
    var repsText: String?
    var setsText: String?
    var restText: String?
    var notes: String?

    init(
        id: UUID = UUID(),
        name: String,
        area: String? = nil,
        exerciseDescription: String? = nil,
        repsText: String? = nil,
        setsText: String? = nil,
        restText: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.area = area
        self.exerciseDescription = exerciseDescription
        self.repsText = repsText
        self.setsText = setsText
        self.restText = restText
        self.notes = notes
    }
}


// User logging (sessions & what they did)
@Model
final class Session {
    @Attribute(.unique) var id: UUID
    var date: Date
    var items: [SessionItem] = []   // links to catalog exercises with performed values
    init(id: UUID = UUID(), date: Date = .now) { self.id = id; self.date = date }
}

@Model
final class SessionItem {
    @Attribute(.unique) var id: UUID
    @Attribute var sourceTag: String?
    var exerciseName: String
    
    // Plan source tracking
    var planSourceId: UUID?
    var planName: String?

    // Structured metrics
    var reps: Int?
    var sets: Int?
    var weightKg: Double?
    var grade: String?  // For bouldering grades (e.g., "6a+", "7b")
    var notes: String?

    init(
        id: UUID = UUID(),
        exerciseName: String,
        planSourceId: UUID? = nil,
        planName: String? = nil,
        reps: Int? = nil,
        sets: Int? = nil,
        weightKg: Double? = nil,
        grade: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.planSourceId = planSourceId
        self.planName = planName
        self.reps = reps
        self.sets = sets
        self.weightKg = weightKg
        self.grade = grade
        self.notes = notes
    }
}
