//
//  ExerciseShape.swift
//  Klettrack
//
//  What you record for an exercise — and so which fields the log shows.
//

import Foundation
import SwiftData

/// What you record for an exercise, and whether "+ kg" is one of the things you record.
///
/// One field, not two. "What you count" (a timed hold vs reps) is already carried by
/// `Exercise.durationText` vs `restText`, and already read in
/// `ExerciseTimerDefaults.plan(for:in:)` — storing it again would be two sources of
/// truth for one fact. The only count the guidance text cannot express is *attempts*,
/// and attempts always means no added load, so three states cover every behaviour the
/// UI branches on:
///
/// | | no load | load |
/// |---|---|---|
/// | timed hold | `.bodyweight` (stretches, front lever) | `.weighted` (max hangs) |
/// | reps | `.bodyweight` (push-ups) | `.weighted` (weighted pull-ups) |
/// | attempts | `.attempts` (limit boulders, 4×4) | — no book protocol loads wall work |
enum ExerciseShape: String, CaseIterable {
    /// Reps or a timed hold that can take added load.
    case weighted
    /// Reps or a timed hold with nothing to add.
    case bodyweight
    /// Tries at a problem: no load, count tries, grade the problem at the end.
    case attempts

    var takesLoad: Bool { self == .weighted }

    var label: String {
        switch self {
        case .weighted: return "Weighted"
        case .bodyweight: return "Bodyweight"
        case .attempts: return "Attempts"
        }
    }
}

extension Exercise {
    /// Absent ⇒ `.weighted`: what every exercise did before this field existed, and the
    /// safe default for a user-created one — an unused weight field beats a missing one.
    var shape: ExerciseShape {
        ExerciseShape(rawValue: shapeKey ?? "") ?? .weighted
    }
}

/// The shape recorded for a catalog exercise, looked up by name.
///
/// By name, and not by passing an `Exercise`, because the log forms only ever hold a
/// `SessionItem.exerciseName` — logged data is decoupled from the catalog. Duplicate
/// names all agree, since the seed table is itself name-keyed, so the first match is
/// the answer rather than an arbitrary pick.
///
/// `.weighted` when the name isn't in the catalog (imported, renamed, since deleted),
/// so a weight field never silently vanishes from an item that has one.
func exerciseShape(named name: String, in context: ModelContext) -> ExerciseShape {
    var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == name })
    descriptor.fetchLimit = 1
    return (try? context.fetch(descriptor))?.first?.shape ?? .weighted
}
