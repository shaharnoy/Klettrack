//
//  CatalogSeeder.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import Foundation
import SwiftData

struct CatalogSeeder {
    // Find or create an Activity by immutable seed key. The name fallback is
    // intentionally retained for existing installs created before seed keys.
    static func ensureActivity(_ name: String, seedKey: String? = nil, in ctx: ModelContext) -> Activity {
        let seedKey = seedKey ?? "activity.\(slug(name))"
        let all: [Activity] = (try? ctx.fetch(FetchDescriptor<Activity>())) ?? []
        if let found = all.first(where: { $0.seedKey == seedKey }) {
            return found
        }
        if let legacy = all.first(where: { $0.name == name }) {
            legacy.seedKey = seedKey
            return legacy
        }
        let a = Activity(seedKey: seedKey, name: name)
        guard !isDeleted(seedKey, in: ctx) else { return a }
        ctx.insert(a)
        return a
    }

    // Find or create a TrainingType by immutable seed key. Existing unchanged
    // rows are claimed by exact name once, without changing their fields.
    static func ensureType(_ name: String, seedKey: String? = nil, area: String? = nil, typeDescription: String? = nil, in activity: Activity) -> TrainingType {
        let seedKey = seedKey ?? "\(activity.seedKey ?? "activity.\(slug(activity.name))").type.\(slug(name))"
        if let t = activity.types.first(where: { $0.seedKey == seedKey }) {
            return t
        }
        if let legacy = activity.types.first(where: { $0.name == name }) {
            legacy.seedKey = seedKey
            return legacy
        }
        let t = TrainingType(seedKey: seedKey, name: name, area: area, typeDescription: typeDescription)
        guard !isDeleted(seedKey, in: activity.modelContext) else { return t }
        activity.types.append(t)
        return t
    }

    // Find or create an Exercise by immutable seed key. Existing exercises are
    // never overwritten; their display and training fields belong to the user.
    static func ensureExercise(
        _ name: String,
        in type: TrainingType,
        seedKey: String? = nil,
        reps: String? = nil,
        duration: String? = nil,
        sets: String? = nil,
        rest: String? = nil,
        notes: String? = nil,
        area: String? = nil
    ) -> Exercise {
        let seedKey = seedKey ?? "\(type.seedKey ?? "type.\(slug(type.name))").exercise.\(slug(name))"
        if let found = type.exercises.first(where: { $0.seedKey == seedKey }) {
            return found
        }
        if let found = existingExercise(seedKey: seedKey, in: type.modelContext) {
            return found
        }
        if let legacy = type.exercises.first(where: { $0.name == name }) {
            legacy.seedKey = seedKey
            return legacy
        }
        let exercise = Exercise(seedKey: seedKey, name: name, area: area, repsText: reps, durationText: duration, setsText: sets, restText: rest, notes: notes)
        guard !isDeleted(seedKey, in: type.modelContext) else { return exercise }
        type.exercises.append(exercise)
        return exercise
    }

    private static func isDeleted(_ seedKey: String, in context: ModelContext?) -> Bool {
        guard let context else { return false }
        let descriptor = FetchDescriptor<DeletedCatalogSeed>(predicate: #Predicate { $0.seedKey == seedKey })
        return (try? context.fetch(descriptor).isEmpty == false) ?? false
    }

    private static func existingExercise(seedKey: String, in context: ModelContext?) -> Exercise? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.seedKey == seedKey })
        return try? context.fetch(descriptor).first
    }

    private static func slug(_ value: String) -> String {
        let allowed = value.lowercased().unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_"
        }.joined()
        return allowed.split(separator: "_").joined(separator: "_")
    }
}
