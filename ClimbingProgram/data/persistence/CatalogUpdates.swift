//
//  CatalogUpdates.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//

import SwiftData

/// Insert any *new* catalog items without touching user edits.
func applyCatalogUpdates(_ ctx: ModelContext) {
    // Example: ensure Bouldering exists (safe for existing users)
    let b = CatalogSeeder.ensureActivity("Bouldering", in: ctx)

    // Maximum & contact Strength (Bouldering)
    let max = CatalogSeeder.ensureType("Maximum & contact Strength", in: b)
    CatalogSeeder.ensureExercise("3–6 near-maximal boulders", in: max, reps: "30 min", rest: "3 min/send")
    CatalogSeeder.ensureExercise("Work on 1–3 “limit” boulders", in: max, reps: "30 min")
    CatalogSeeder.ensureExercise("Big, powerful moves (medium holds, small feet)", in: max, reps: "35–45° for 25 min", rest: "8 min")
    CatalogSeeder.ensureExercise("Footless problem on big holds", in: max, reps: "20–45° for 15 min", rest: "8 min")
    CatalogSeeder.ensureExercise("Coordination / dyno", in: max, reps: "vertical–30° for 20 min", rest: "8 min")
    CatalogSeeder.ensureExercise("Slabs", in: max, reps: "vertical–30° for 20 min", rest: "8 min")
    CatalogSeeder.ensureExercise("3 problems V0–V2", in: max, rest: "1 min/send", notes: "rest block 3 min")
    CatalogSeeder.ensureExercise("3 problems V3–V4", in: max, rest: "3 min/send", notes: "rest block 6 min")
    CatalogSeeder.ensureExercise("3 problems V4–V5", in: max, rest: "3 min/send", notes: "rest block 6 min")
    CatalogSeeder.ensureExercise("3–5 problems V5–V6", in: max, rest: "5 min/send", notes: "rest block 6 min")
    CatalogSeeder.ensureExercise("Board", in: max, reps: "45 min", rest: "3 min/attempt")
    CatalogSeeder.ensureExercise("Work on 1–3 “limit” boulders (again)", in: max, reps: "30 min")

    // Strength-Endurance (Bouldering)
    let se = CatalogSeeder.ensureType("Strength-Endurance", in: b)
    CatalogSeeder.ensureExercise("Bouldering 4×4s", in: se, notes: "see protocol")
    CatalogSeeder.ensureExercise("Big-holds, big-move 4×4s", in: se, notes: "see protocol")
    CatalogSeeder.ensureExercise("6 problems V0–V2", in: se, rest: "45 sec/send")
    CatalogSeeder.ensureExercise("3 problems V3–V4 (× several blocks)", in: se, reps: "no rest between sends", notes: "rest block 6 min")
    CatalogSeeder.ensureExercise("3 problems V4–V5 (× several blocks)", in: se, reps: "no rest between sends", notes: "rest block 6 min")
    CatalogSeeder.ensureExercise("Tension board 3×6", in: se, notes: "see protocol")

    try? ctx.save()
}
