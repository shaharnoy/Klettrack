//
//  SeedData.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import SwiftData
import Foundation
        
struct SeedData {
    static func loadIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Activity>())) ?? 0
        guard count == 0 else {
            // Ensure new models are present even on non-fresh databases
            seedPlanKinds(context)
            seedDayTypes(context)
            try? context.save()
            return
        } // fresh-only
        
        // ========== CORE ==========
        let core = Activity(name: "Core")
        
        let anterior = TrainingType(name: "Anterior Core", typeDescription: "pick 2-3 exercises per sessions")
        anterior.exercises = [
            Exercise(name: "Abdominal Crunches", order: 1, repsText: "25-100", setsText: "2", restText:"3 mins"),
            Exercise(name: "Hanging Knee Lifts", order: 2, repsText: "15-20", setsText: "2-3", restText:"3 mins"),
            Exercise(name: "1-Arm 1-Leg Plank", order: 3, repsText: "1 mins", setsText: "2", restText:"3 mins"),
            Exercise(name: "1-Arm Elbow & Side Plank", order: 4, repsText: "2 mins"),
            Exercise(name: "Front Lever", order: 5, repsText: "2-5", setsText: "1-2", restText:"3 mins"),
        ]
        
        let posterior = TrainingType(name: "Posterior Core", typeDescription: "pick 2-3 exercises per sessions ")
        posterior.exercises = [
            Exercise(name: "Superman", order: 1, repsText: "20", setsText: "2", restText:"3 mins"),
            Exercise(name: "Reverse Plank", order: 2, repsText: "20-60 sec", setsText: "1-2", restText:"3 mins"),
            Exercise(name: "Back Bridge", order: 3, repsText: "15-20", setsText: "1-2", restText:"3 mins"),
            Exercise(name: "Side Hip Raises", order: 4, repsText: "10-20", setsText: "2", restText:"1 mins"),
        ]
        
        let chain = TrainingType(name: "Total/Posterior Chain", typeDescription: "pick one of them if you're in the mood")
        chain.exercises = [
            Exercise(name: "Sumo Deadlift", order: 1, repsText: "10-15", setsText: "2", restText:"3 mins"),
            Exercise(name: "Dumbbell Snatch", order: 2, repsText: "5-8", setsText: "2-3", restText:"3 mins"),
            Exercise(name: "Barbell Deadlift", order: 3, repsText: "3-6", setsText: "2-4", restText:"3 mins")
        ]
        
        core.types = [anterior, posterior, chain]
        
        // ========== ANTAGONIST ==========
        let ant = Activity(name: "Antagonist & Stabilizer")
        
        let wrist = TrainingType(name: "Wrist Stabilizers", typeDescription: "pick 2-3 exercises per sessions")
        wrist.exercises = [
            Exercise(name: "Reverse Wrist Curls", order: 1, repsText: "15–25", setsText: "2–3", restText:"3 mins"),
            Exercise(name: "Pronator Isolation", order: 2, repsText: "20–25", setsText: "2 in each hand", restText:"2 mins"),
            Exercise(name: "Reverse Arm Curl", order: 4, repsText: "15–20", setsText: "1–2", restText:"3 mins"),
            Exercise(name: "Wrist Extension Isometric", order: 3, repsText: "45–60 sec, 2 each arm", setsText: "2", restText:"2 mins"),
            Exercise(name: "Wide Pinch Wrist Extention", order: 5, repsText: "30 seconds", setsText: "3–5", restText:"2 mins")
        ]
        
        let cuff = TrainingType(name: "Rotator Cuff & Scap Stabilizers", typeDescription: "pick 2 exercises per sessions")
        cuff.exercises = [
            Exercise(name: "DB Internal Rotation", order: 1, repsText: "25", setsText: "2 each hand"),
            Exercise(name: "DB External Rotation", order: 2, repsText: "25", setsText: "2 each hand"),
            Exercise(name: "Band T", order: 3, repsText: "20", setsText: "2", restText:"2 mins"),
            Exercise(name: "Band Y", order: 4, repsText: "20", setsText: "2", restText:"2 mins"),
            Exercise(name: "Scapular Push-Up", order: 5, repsText: "15–20", setsText: "1"),
            Exercise(name: "Scapular Pull-Up", order: 6, repsText: "8–12", setsText: "1")
        ]
        
        let push = TrainingType(name: "Antagonist (Push) Muscles", typeDescription: "pick 1 exercise per session")
        push.exercises = [
            Exercise(name: "Shoulder Press", order: 1, repsText: "15–20", setsText: "1–2",restText:"3 mins"),
            Exercise(name: "Push-Up", order: 2, repsText: "15–25", setsText: "1–2",restText:"3 mins")
        ]
        
        ant.types = [wrist, cuff, push]
        
        // ========== CLIMBING-SPECIFIC (non-bouldering) ==========
        let climb = Activity(name: "Climbing-Specific Exercises")
        
        let maxStrength = TrainingType(
            name: "Maximum & Contact Strength",
            typeDescription: "Maximum and contact strength for fingers and pull muscles"
        )
        maxStrength.exercises = [
            Exercise(name: "Bouldering", area: "Fingers", order: 4, repsText: "3 ascents", setsText: "3–10 problems", restText: "2 min/asc"),
            Exercise(name: "FB \"Minimum Edge\" Hangs", area: "Fingers", order: 1, exerciseDescription: "Smallest edge you can hold ~12s", repsText: "5", setsText: "2–5", notes: "12s work, 3mins rest"),
            Exercise(name: "FB Max-Weight Hangs (10s, 14–20mm)", area: "Fingers", order: 2, repsText: "5", setsText: "2–5", notes: "10s work, 50s rest"),
            Exercise(name: "FB Max-Weight Hangs (7/53, 14–20mm)", area: "Fingers", order: 3, repsText: "3", setsText: "2–5", notes: "7s work, 53s rest"),
            Exercise(name: "Loading Pin Lifts — repetitions", area: "Fingers", order: 4, repsText: "1:50% 2:60% 3:70% 4–7:80%", setsText: "8 reps (1–3); 4 reps (4–7)"),
            Exercise(name: "Weighted Pull-Ups", area: "Pull", order: 1, repsText: "5", setsText: "3–6", restText: "3 min"),
            Exercise(name: "Square Pull-Ups", area: "Pull", order: 2, repsText: "3–6", setsText: "1–2", restText: "3 min"),
            Exercise(name: "System Wall Isolation", area: "Pull", order: 4, repsText: "3–5 each side", setsText: "2–5", restText: "3 min"),
            Exercise(name: "Steep Wall Lock-Offs", area: "Pull", order: 5, repsText: "4–6 each side", setsText: "2–5", restText: "brief"),
            Exercise(name: "Uneven-Grip Pull-Ups", area: "Pull", order: 3, repsText: "3–5 each side", setsText: "2–3", restText: "2 min"),
            Exercise(name: "One-Arm Lock-Offs", area: "Pull", order: 6, repsText: "2–3", setsText: "2–3", restText: "2 min")
        ]
        
        let contactPower = TrainingType(name: "Contact Strength & Power", typeDescription: "Contact strength, explosive recruitment, and pulling power")
        contactPower.exercises = [
            Exercise(name: "One-Arm Lunging", area: "Fingers", order: 4, repsText: "6–12 moves", setsText: "2–3", restText: "minimal"),
            Exercise(name: "Campus Board Bumps", area: "Fingers", order: 1, repsText: "2–4 sets each side", restText: "2 min"),
            Exercise(name: "CB Laddering (no skips, small rungs)", area: "Fingers", order: 2, repsText: "up only", setsText: "3–10", restText: "2–3 min"),
            Exercise(name: "Campus Switch Hands", area: "Fingers", order: 3, repsText: "12 switches", setsText: "2", restText: "2 min"),
            //PULL//
            Exercise(name: "Big-Move Boulder Problems", area: "Pull", order: 3, repsText: "6–10 moves", setsText: "5 sends", restText: "3 min"),
            Exercise(name: "CB Laddering (larger rungs w/ skips)", area: "Pull", order: 1, repsText: "1–3–5–7", setsText: "3–10", restText: "3 min"),
            Exercise(name: "Boulder Campusing", area: "Pull", order: 2, repsText: "3–8 moves", setsText: "3–5", restText: "3 min")
        ]
        
        let strengthEndurance = TrainingType(name: "Strength-Endurance", typeDescription: "Endurance work for fingers and pull muscles")
        strengthEndurance.exercises = [
            Exercise(name: "Short-Duration Fingerboard Repeaters", area: "Fingers", order: 1, repsText: "6", setsText: "3–5", restText:"1 mins", notes: "level1 : 10s work/30s rest; level2 : 10s work/20s rest; level3 : 10s work/10s rest"),
            Exercise(name: "Long-Duration Fingerboard Repeaters", area: "Fingers", order: 2, repsText: "4", setsText: "3–5",restText:"1 mins", notes: "level1 : 30s work/30s rest; level2 : 30s work/15s rest; level3 : 60s work/30s rest"),
            //PULL//
            Exercise(name: "Pull-Up Intervals", area: "Pull", order: 1, repsText: "5", setsText: "10–20", restText:"No rest", notes: "5 pull-ups every minute on the minute - rest time is the remainder of the minute"),
            Exercise(name: "Frenchies", area: "Pull", order: 2, repsText: "2–6 cycles", setsText: "2–4",restText:"5 mins")
        ]
        
        climb.types = [maxStrength, contactPower, strengthEndurance]
        
        // ========== BOULDERING with COMBINATIONS ==========
        let boulder = Activity(name: "Bouldering")
        
        let bMax = TrainingType(name: "Maximum & contact Strength", typeDescription: "Bouldering")
        let comb1 = BoulderCombination(name: "Combination 1", comboDescription: "Limit and casual bouldering; 1:30 hours")
        comb1.exercises = [
            Exercise(name: "3–6 near‑maximal boulders", order: 1, repsText: "30 min", restText: "3 min/asc"),
            Exercise(name: "Work on 1–3 limit boulders", order: 2, repsText: "30 min", restText: "3 min/asc")
        ]
        let comb2 = BoulderCombination(name: "Combination 2", comboDescription: "Mixed combination, rest 8 mins between blocks; 1:45 hours")
        comb2.exercises = [
            Exercise(name: "Big, powerful moves", order: 1, repsText: "35–45° for 25 min", restText: "3 min/asc"),
            Exercise(name: "Footless problem on big holds", order: 2, repsText: "20–45° for 15 min", restText: "3 min/asc"),
            Exercise(name: "Coordination / dyno", order: 3, repsText: "vertical–30° for 20 min", restText: "3 min/asc"),
            Exercise(name: "Slabs", order: 4, repsText: "vertical–30° for 20 min", restText: "3 min/asc")
        ]
        let comb3 = BoulderCombination(name: "Combination 3", comboDescription: "Grade blocks with 6 mins rest blocks")
        comb3.exercises = [
            Exercise(name: "1. 3 problems V0–V2", order: 1, restText: "1 min/send", notes: "rest block 3 min"),
            Exercise(name: "2. 3 problems V3–V4", order: 2, restText: "3 min/send", notes: "rest block 6 min"),
            Exercise(name: "3. 3 problems V4–V5", order: 3, restText: "3 min/send", notes: "rest block 6 min"),
            Exercise(name: "4. 3-5 problems V5–V6", order: 4, restText: "5 min/send", notes: "rest block 6 min"),
            Exercise(name: "5. 3 problems V4–V5", order: 5, restText: "3 min/send", notes: "rest block 6 min")
        ]
        let comb4 = BoulderCombination(name: "Combination 4", comboDescription: "Boards & limit boulders")
        comb4.exercises = [
            Exercise(name: "Board", order: 2, repsText: "45 min", restText: "3 min/attempt"),
            Exercise(name: "Work on 1–3 limit boulders", order: 1, repsText: "30 min")
        ]
        bMax.combinations = [comb1, comb2, comb3, comb4]
        
        let bSE = TrainingType(name: "Strength-Endurance", typeDescription: "SE circuits for bouldering")
        let combSE1 = BoulderCombination(name: "Combination 1")
        combSE1.exercises = [ Exercise(name: "Bouldering 4×4s", order: 1, notes: "4 boulders, 4 times on the minute - rest 4 minutes between problmes") ]
        let combSE2 = BoulderCombination(name: "Combination 2")
        combSE2.exercises = [ Exercise(name: "Big-holds, big-move 4×4s", order: 1, notes: "4 boulders, 4 times on the minute - rest 4 minutes between problmes") ]
        let combSE3 = BoulderCombination(name: "Combination 3", comboDescription: "Alternating V-grade blocks, no rest between sends, rest block 6 min")
        combSE3.exercises = [
            Exercise(name: "1. 6 problems V0–V2", order: 1, restText: "45 sec/send"),
            Exercise(name: "2. 3 problems V3–V4", order: 2, repsText: "no rest between sends", notes: "rest block 6 min"),
            Exercise(name: "3. 3 problems V4–V5", order: 3, repsText: "no rest between sends", notes: "rest block 6 min"),
            Exercise(name: "4. 3 problems V3–V4", order: 4, repsText: "no rest between sends", notes: "rest block 6 min"),
            Exercise(name: "5. 3 problems V4–V5", order: 5, repsText: "no rest between sends", notes: "rest block 6 min"),
            Exercise(name: "6. 3 problems V3–V4", order: 6, repsText: "no rest between sends", notes: "rest block 6 min"),
            Exercise(name: "7. 3 problems V4–V5", order: 7, repsText: "no rest between sends", notes: "rest block 6 min"),
            Exercise(name: "8. 3 problems V3–V4", order: 8, repsText: "no rest between sends", notes: "rest block 6 min")
        ]
        let combSE4 = BoulderCombination(name: "Combination 4")
        combSE4.exercises = [ Exercise(name: "Board 3×6", order: 1, notes: "6 boulders, 3 times on the minute - rest 3 minutes between boulders") ]
        
        bSE.combinations = [combSE1, combSE2, combSE3, combSE4]
        
        boulder.types = [bMax, bSE]
        
        // Save all
        [core, ant, climb, boulder].forEach { context.insert($0) }
        
        // Seed climbing styles and gyms
        SeedClimbingData.loadIfNeeded(context)
        
        try? context.save()
        
        // Seed timer templates
        SeedTimerTemplates.loadIfNeeded(context)
        // Seed PlanKind and DayType models
        seedPlanKinds(context)
        seedDayTypes(context)
        reconcilePlanDayTypesIfNeeded(context)
        try? context.save()
    }
    
    
    static func nukeAndReseed(_ context: ModelContext) {
        // Delete everything
        try? context.delete(model: Activity.self)
        try? context.delete(model: TrainingType.self)
        try? context.delete(model: Exercise.self)
        try? context.delete(model: Plan.self)
        try? context.delete(model: PlanDay.self)
        try? context.delete(model: Session.self)
        try? context.delete(model: SessionItem.self)
        try? context.delete(model: PlanKindModel.self)
        try? context.delete(model: DayTypeModel.self)
        try? context.save()
        
        // Also nuke and reseed timer templates
        SeedTimerTemplates.nukeAndReseed(context)
        
        // Seed fresh
        loadIfNeeded(context)
    }
}


private func seedPlanKinds(_ context: ModelContext) {
    struct KindSeed { let key: String; let name: String; let totalWeeks: Int?; let isRepeating: Bool; let order: Int }
    let seeds: [KindSeed] = [
        .init(key: "daily",   name: "Daily",              totalWeeks: 0,  isRepeating: false, order: 0),
        .init(key: "weekly",  name: "Weekly",             totalWeeks: nil,isRepeating: true,  order: 1),
        .init(key: "3-2-1",   name: "3-2-1 (6 weeks)",    totalWeeks: 6,  isRepeating: false, order: 2),
        .init(key: "4-3-2-1", name: "4-3-2-1 (10 weeks)", totalWeeks: 10, isRepeating: false, order: 3)
    ]
    for s in seeds {
        let key = s.key
        let fetch = FetchDescriptor<PlanKindModel>(predicate: #Predicate { $0.key == key })
        let existing = (try? context.fetch(fetch))?.first
        if let k = existing {
            k.name = s.name
            k.totalWeeks = s.totalWeeks
            k.isRepeating = s.isRepeating
            k.order = s.order
        } else {
            context.insert(PlanKindModel(key: s.key, name: s.name, totalWeeks: s.totalWeeks, isRepeating: s.isRepeating, order: s.order))
        }
    }
}

func seedDayTypes(_ context: ModelContext) {
    struct DaySeed {
        let key: String
        let name: String
        let colorKey: String
        let order: Int
        let ishidden: Bool = false   // default seed types are visible
    }

    let seeds: [DaySeed] = [
        .init(key: "climbingFull",    name: "Climb + Hi-Vol. exercises", colorKey: "green",  order: 0),
        .init(key: "climbingSmall",   name: "Climb + Lo-Vol. exercises", colorKey: "blue",   order: 1),
        .init(key: "climbingReduced", name: "Climb Low-Vol. ",           colorKey: "brown",  order: 2),
        .init(key: "Perclimbing",     name: "Performance Climbing",      colorKey: "pink",   order: 3),
        .init(key: "core",            name: "Core",                       colorKey: "orange", order: 4),
        .init(key: "antagonist",      name: "Antagonist",                 colorKey: "cyan",   order: 5),
        .init(key: "rest",            name: "Rest",                       colorKey: "purple", order: 6),
        .init(key: "vacation",        name: "Vacation",                   colorKey: "yellow", order: 7),
        .init(key: "sick",            name: "Sick",                       colorKey: "red",    order: 8)
    ]

    // Fetch all existing DayTypeModel rows once
    let allExisting: [DayTypeModel] = (try? context.fetch(FetchDescriptor<DayTypeModel>())) ?? []
    var existingByKey: [String: DayTypeModel] = .init(uniqueKeysWithValues: allExisting.map { ($0.key, $0) })

    let seedKeys = Set(seeds.map { $0.key })

    // Upsert seed types and explicitly unhide them
    for s in seeds {
        if let d = existingByKey[s.key] {
            d.name = s.name
            d.colorKey = DayTypeModel.allowedColorKeys.contains(s.colorKey) ? s.colorKey : "gray"
            d.order = s.order
            // Unhide defaults
            d.isHidden = s.ishidden == false ? false : true
        } else {
            // Insert with safe color + default visibility
            let safeColor = DayTypeModel.allowedColorKeys.contains(s.colorKey) ? s.colorKey : "gray"
            let new = DayTypeModel(key: s.key, name: s.name, order: s.order, colorKey: safeColor)
            // If your init doesn't expose isHidden, set it after init:
            new.isHidden = s.ishidden == false ? false : true
            context.insert(new)
            existingByKey[s.key] = new
        }
    }

    // Hide any non-seed custom types instead of deleting
    for d in allExisting where !seedKeys.contains(d.key) {
        d.isHidden = true
    }
    try? context.save()
}


private func reconcilePlanDayTypesIfNeeded(_ context: ModelContext) {
    // Fetch all plan days
    let dayFetch = FetchDescriptor<PlanDay>()
    let allDays = (try? context.fetch(dayFetch)) ?? []
    // Filter those missing a type
    let nilTypeDays = allDays.filter { $0.type == nil }
    guard !nilTypeDays.isEmpty else { return }
    // Fetch the 'rest' DayTypeModel as a safe default
    let restFetch = FetchDescriptor<DayTypeModel>(predicate: #Predicate { $0.key == "rest" })
    let restType = (try? context.fetch(restFetch))?.first
    // If rest exists, assign it; otherwise, do nothing (keep nil)
    guard let restType else { return }
    for d in nilTypeDays { d.type = restType }
    try? context.save()
}
