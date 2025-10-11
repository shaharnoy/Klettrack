//
//  CatalogUpdates.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import SwiftData

func applyCatalogUpdates(_ ctx: ModelContext) {
    //adding bouldering exercises
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
    //adding climbing specifc exerecises
    let c = CatalogSeeder.ensureActivity("Climbing-Specific Exercises", in: ctx)
    let maxStrength = CatalogSeeder.ensureType("Maximum & Contact Strength", in: c)
    //Pull
    CatalogSeeder.ensureExercise("One Arm Pullup", in: maxStrength, reps: "1-2", sets: "2", rest: "3 min", notes: "lockoff as a start also with a band", area: "Pull")
    
    let contactPower = CatalogSeeder.ensureType("Contact Strength & Power", in: c)
    //Fingers
    CatalogSeeder.ensureExercise("Campus board-Switch Hands", in: contactPower, reps: "up to 12 switches", sets: "2-6", rest: "2 mins", notes: "", area: "Fingers")
    //Pull
    CatalogSeeder.ensureExercise("Clap Pullups", in: contactPower, reps: "3-8", sets: "2-3", rest: "3 mins", notes: "start with only releasing hands, work towards a clap", area: "Pull")
    CatalogSeeder.ensureExercise("Campus board-Double Dynos (big rungs)", in: contactPower, reps: "3-2-4-3-5-4-6-5-7", sets: "1-5", rest: "3 mins", notes: "Advanced version - 3-2-4-2-4-2-4-2-4", area: "Pull")
    
    let strengthEndurance = CatalogSeeder.ensureType("Strength-Endurance", in: c)
    //Fingers
    CatalogSeeder.ensureExercise("Board repeaters", in: strengthEndurance, reps: "30-90 seconds", sets: "5-10", rest: "3 mins", notes: "45 degrees mirrored wall, 5 different grips (2-3 fingers,half-crimp, open hand, etc.), 1-2 sets per grip", area: "Fingers")
    //Pull
    CatalogSeeder.ensureExercise("Campus board-Ladder Laps", in: strengthEndurance, reps: "2-4 laps", sets: "2-5", rest: "3 mins", notes: "1-3-5-7-7-5-3-1 or easier:1-3-5-7-7-6-5-4-3-2-1", area: "Pull")
    CatalogSeeder.ensureExercise("Square Dance", in: strengthEndurance, reps: "up to 2 mins", sets: "2-4", rest: "double than work time", notes: "partial recovery on rest time - decrease time if needed", area: "Pull")
    
}
