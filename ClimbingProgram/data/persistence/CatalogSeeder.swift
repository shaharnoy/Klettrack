//
//  CatalogSeeder.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//

import SwiftData

struct CatalogSeeder {
    // Find or create an Activity by name
    static func ensureActivity(_ name: String, in ctx: ModelContext) -> Activity {
        // Fetch all once and filter in Swift (keeps it simple/portable)
        let all: [Activity] = (try? ctx.fetch(FetchDescriptor<Activity>())) ?? []
        if let found = all.first(where: { $0.name == name }) {
            return found
        }
        let a = Activity(name: name)
        ctx.insert(a)
        return a
    }

    // Find or create a TrainingType by name inside an Activity
    static func ensureType(_ name: String, area: String? = nil, in activity: Activity) -> TrainingType {
        if let t = activity.types.first(where: { $0.name == name }) {
            // optionally keep area up to date
            if t.area != area { t.area = area }
            return t
        }
        let t = TrainingType(name: name, area: area)
        activity.types.append(t)
        return t
    }

    // Find or create an Exercise by name inside a TrainingType
    static func ensureExercise(
        _ name: String,
        in type: TrainingType,
        reps: String? = nil,
        sets: String? = nil,
        rest: String? = nil,
        notes: String? = nil
    ) {
        if let e = type.exercises.first(where: { $0.name == name }) {
            // If you want to ship text corrections later, uncomment:
            // e.repsText = reps ?? e.repsText
            // e.setsText = sets ?? e.setsText
            // e.restText = rest ?? e.restText
            // e.notes    = notes ?? e.notes
            return
        }
        type.exercises.append(
            Exercise(name: name, repsText: reps, setsText: sets, restText: rest, notes: notes)
        )
    }
}
