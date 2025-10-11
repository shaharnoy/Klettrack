//
//  CatalogSeeder.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
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
        notes: String? = nil,
        area: String? = nil
    ) {
        // If an exercise with this name already exists, do nothing.
        if type.exercises.contains(where: { $0.name == name }) {
            return
        }
        // Otherwise insert it.
        type.exercises.append(
            Exercise(name: name, area:area, repsText: reps, setsText: sets, restText: rest, notes: notes)
        )
    }
}
