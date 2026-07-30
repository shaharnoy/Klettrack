//
//  LastLoggedWeight.swift
//  Klettrack
//
//  What you lifted last time, used to seed the timer's per-set weight stepper.
//

import Foundation
import SwiftData

// `exerciseShape(named:in:)` was here too; it lives beside the enum it returns, in
// `ExerciseShape.swift`.

/// The weight most recently logged for an exercise, or nil if it has never been
/// logged with one.
///
/// Walks sessions newest-first rather than filtering `SessionItem` directly: a
/// logged item's date lives on its `session` relationship, and a `#Predicate`
/// through an optional relationship is fragile. This mirrors how
/// `QuickExerciseProgress` builds its history.
///
/// When the item carries per-set detail the *last* set's weight wins, so the value
/// matches the "Last:" label literally — the weight you finished on, not the mean
/// of a ramp.
func lastLoggedWeight(for exerciseName: String, in context: ModelContext) -> Double? {
    let descriptor = FetchDescriptor<Session>(
        sortBy: [SortDescriptor<Session>(\.date, order: .reverse)]
    )
    let sessions = (try? context.fetch(descriptor)) ?? []

    for session in sessions {
        let matches = session.items
            .filter { $0.exerciseName == exerciseName }
            .sorted { $0.sort < $1.sort }

        // Latest first within the day, so a correction later in the session wins.
        for item in matches.reversed() {
            if let last = item.loggedSets.compactMap(\.weightKg).last { return last }
            if let weight = item.weightKg { return weight }
        }
    }
    return nil
}
