//
//  SeedData.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import SwiftData
import Foundation
        
//
//  SeedData.swift
//  Klettrack
//
struct SeedData {
    static func loadIfNeeded(_ context: ModelContext) {
        // ---------- Catalog (idempotent upsert) ----------
        upsertCatalog(context)

        // ---------- Other seeds ----------
        SeedClimbingData.loadIfNeeded(context) // only seeds if all gym and styles and days are empty
        try? context.save()

        SeedTimerTemplates.loadIfNeeded(context)   // timer templates - only seeds if no templates exist
        seedPlanKinds(context)                     // it alwasys seeds - since it's not modifiable it's not a problem
        seedDayTypes(context)                      // only upsert missing default day types, don't overwrite custom days and don't make unhidden ones hidden
        reconcilePlanDayTypesIfNeeded(context)     // keep plans aligned
        try? context.save()
    }

    static func nukeAndReseed(_ context: ModelContext) {
        // Delete everything relevant
        try? context.delete(model: Activity.self)
        try? context.delete(model: TrainingType.self)
        try? context.delete(model: BoulderCombination.self)
        try? context.delete(model: Exercise.self)
        try? context.delete(model: Plan.self)
        try? context.delete(model: PlanDay.self)
        try? context.delete(model: Session.self)
        try? context.delete(model: SessionItem.self)
        try? context.delete(model: PlanKindModel.self)
        try? context.delete(model: DayTypeModel.self)
        try? context.save()

        SeedTimerTemplates.nukeAndReseed(context)
        loadIfNeeded(context)
    }

    // MARK: - Catalog seeding via ensure (idempotent)
    // Upsert concept allow us to update content freely between builds without duplicating or nuking user data
    private static func upsertCatalog(_ ctx: ModelContext) {
        // ===== CORE =====
        let core = CatalogSeeder.ensureActivity("Core", in: ctx) // ensure Activity
        do {
            let anterior = CatalogSeeder.ensureType("Anterior Core", in: core)
            anterior.typeDescription = ""
            ensureEx("Abdominal Crunches", into: anterior, order: 1, reps: "25-100", sets: "2", rest: "3 min")
            ensureEx("Hanging Knee Lifts", into: anterior, order: 2, reps: "15-20", sets: "2-3", rest: "3 min")
            ensureEx("1-Arm 1-Leg Plank", into: anterior, order: 3, duration: "1 min", sets: "2", rest: "3 min")
            ensureEx("1-Arm Elbow & Side Plank", into: anterior, order: 4, duration: "2 min", sets: "1")
            ensureEx("Front Lever", into: anterior, order: 5, reps: "2-5", sets: "1-2", rest: "3 min")

            let posterior = CatalogSeeder.ensureType("Posterior Core", in: core)
            posterior.typeDescription = ""
            ensureEx("Superman", into: posterior, order: 1, reps: "20", sets: "2", rest: "3 min")
            ensureEx("Reverse Plank", into: posterior, order: 2, duration: "20-60 sec", sets: "1-2", rest: "3 min")
            ensureEx("Back Bridge", into: posterior, order: 3, reps: "15-20", sets: "1-2", rest: "3 min")
            ensureEx("Side Hip Raises", into: posterior, order: 4, reps: "10-20", sets: "2", rest: "1 min")

            let chain = CatalogSeeder.ensureType("Total Posterior Chain", in: core)
            chain.typeDescription = ""
            ensureEx("Sumo Deadlift", into: chain, order: 1, reps: "10-15", sets: "2", rest: "3 min")
            ensureEx("Dumbbell Snatch", into: chain, order: 2, reps: "5-8", sets: "2-3", rest: "3 min")
            ensureEx("Barbell Deadlift", into: chain, order: 3, reps: "3-6", sets: "2-4", rest: "3 min")
        }

        // ===== Mobility =====
        let mobility = CatalogSeeder.ensureActivity("Mobility", in: ctx) // ensure Activity
        do {
            let bottom = CatalogSeeder.ensureType("Lower body", in: mobility)
            bottom.typeDescription = ""
            ensureEx("Knee-to-chest", into: bottom, order: 1, reps: "2 each leg", duration: "30 sec")
            ensureEx("Band Hamstring Stretch", into: bottom, order: 2,reps: "3 each leg", duration: "30 sec")
            ensureEx("Butterfly Stretch", into: bottom, order: 3,reps: "2", duration: "30-60 sec")
            ensureEx("Seated Single-Leg Hip Adductor", into: bottom, order: 4,reps: "2 each leg", duration: "30 sec")
            ensureEx("Lunges", into: bottom, order: 5,reps: "2 each leg", duration: "30 sec")
            ensureEx("Kneeling Quad and Hip Flexor Stretch", into: bottom, order: 6,reps: "2 each leg", duration: "30 sec")
            ensureEx("Seated Calf Stretch with Band", into: bottom, order: 7,reps: "2 each leg", duration: "30 sec")
            ensureEx("Oblique Knees to One Side", into: bottom, order: 8,reps: "1 each side", duration: "30 sec")

        }
        // ===== ANTAGONIST & STABILIZER =====
        let ant = CatalogSeeder.ensureActivity("Antagonist & Stabilizer", in: ctx)
        do {
            let wrist = CatalogSeeder.ensureType("Wrist Stabilizers", in: ant)
            wrist.typeDescription = ""
            ensureEx("Reverse Wrist Curls", into: wrist, order: 1, reps: "15–25", sets: "2–3", rest: "3 min")
            ensureEx("Pronator Isolation", into: wrist, order: 2, reps: "20–25", sets: "2 in each hand", rest: "2 min")
            ensureEx("Wrist Extension Isometric", into: wrist, order: 3, duration: "1 min", sets: "2 each arm", rest: "2 min")
            ensureEx("Reverse Arm Curl", into: wrist, order: 4, reps: "15–20", sets: "1–2", rest: "3 min")
            ensureEx("Wide Pinch Wrist Extention", into: wrist, order: 5, duration: "30 sec", sets: "3–5", rest: "2 min")

            let cuff = CatalogSeeder.ensureType("Rotator Cuff & Scap Stabilizers", in: ant)
            cuff.typeDescription = ""
            ensureEx("DB Internal Rotation", into: cuff, order: 1, reps: "25", sets: "2 each hand")
            ensureEx("DB External Rotation", into: cuff, order: 2, reps: "25", sets: "2 each hand")
            ensureEx("Band T", into: cuff, order: 3, reps: "20", sets: "2", rest: "2 min")
            ensureEx("Band Y", into: cuff, order: 4, reps: "20", sets: "2", rest: "2 min")
            ensureEx("Scapular Push-Up", into: cuff, order: 5, reps: "15–20", sets: "1")
            ensureEx("Scapular Pull-Up", into: cuff, order: 6, reps: "8–12", sets: "1")

            let push = CatalogSeeder.ensureType("Antagonist (Push) Muscles", in: ant)
            push.typeDescription = ""
            ensureEx("Shoulder Press", into: push, order: 1, reps: "15–20", sets: "1–2", rest: "3 min")
            ensureEx("Push-Up", into: push, order: 2, reps: "15–25", sets: "1–2", rest: "3 min")
        }

        // ===== CLIMBING-SPECIFIC (non-bouldering) =====
        let climb = CatalogSeeder.ensureActivity("Climbing-Specific Exercises", in: ctx)
        do {
            let maxStrength = CatalogSeeder.ensureType("Maximum & Contact Strength", area: nil, in: climb)
            maxStrength.typeDescription = "Maximum and contact strength for fingers and pull muscles"
            // Fingers
            ensureEx("FB \"Minimum Edge\" Hangs", into: maxStrength, order: 1, area: "Fingers",
                     reps: "5", sets: "2–5", notes: "12s work, 3min rest", description: "Smallest edge you can hold ~12s")
            ensureEx("FB Max-Weight Hangs (10s, 14–20mm)", into: maxStrength, order: 2, area: "Fingers",
                     reps: "5", sets: "2–5", notes: "10s work, 50s rest")
            ensureEx("FB Max-Weight Hangs (7/53, 14–20mm)", into: maxStrength, order: 3, area: "Fingers",
                     reps: "3", sets: "2–5", notes: "7s work, 53s rest")
            ensureEx("Loading Pin Lifts — repetitions", into: maxStrength, order: 4, area: "Fingers",
                     reps: "1:50% 2:60% 3:70% 4–7:80%", sets: "8 reps (1–3); 4 reps (4–7)")
            ensureEx("Bouldering", into: maxStrength, order: 4, area: "Fingers",
                     reps: "3 ascents", sets: "3–10 problems", rest: "2 min/asc")
            // Pull
            ensureEx("Weighted Pull-Ups", into: maxStrength, order: 1, area: "Pull",
                     reps: "5", sets: "3–6", rest: "3 min")
            ensureEx("Square Pull-Ups", into: maxStrength, order: 2, area: "Pull",
                     reps: "3–6", sets: "1–2", rest: "3 min")
            ensureEx("Uneven-Grip Pull-Ups", into: maxStrength, order: 3, area: "Pull",
                     reps: "3–5 each side", sets: "2–3", rest: "2 min")
            ensureEx("System Wall Isolation", into: maxStrength, order: 4, area: "Pull",
                     reps: "3–5 each side", sets: "2–5", rest: "3 min")
            ensureEx("Steep Wall Lock-Offs", into: maxStrength, order: 5, area: "Pull",
                     reps: "4–6 each side", sets: "2–5", rest: "brief")
            ensureEx("One-Arm Lock-Offs", into: maxStrength, order: 6, area: "Pull",
                     reps: "2–3", sets: "2–3", rest: "2 min")

            let contactPower = CatalogSeeder.ensureType("Contact Strength & Power", in: climb)
            contactPower.typeDescription = "Contact strength, explosive recruitment, and pulling power"
            // Fingers
            ensureEx("Campus Board Bumps", into: contactPower, order: 1, area: "Fingers",
                     reps: "2–4 sets each side", rest: "2 min")
            ensureEx("CB Laddering (no skips, small rungs)", into: contactPower, order: 2, area: "Fingers",
                     reps: "up only", sets: "3–10", rest: "2–3 min")
            ensureEx("Campus Switch Hands", into: contactPower, order: 3, area: "Fingers",
                     reps: "12 switches", sets: "2", rest: "2 min")
            ensureEx("One-Arm Lunging", into: contactPower, order: 4, area: "Fingers",
                     reps: "6–12 moves", sets: "2–3", rest: "minimal")
            // Pull
            ensureEx("CB Laddering (larger rungs w/ skips)", into: contactPower, order: 1, area: "Pull",
                     reps: "1–3–5–7", sets: "3–10", rest: "3 min")
            ensureEx("Boulder Campusing", into: contactPower, order: 2, area: "Pull",
                     reps: "3–8 moves", sets: "3–5", rest: "3 min")
            ensureEx("Big-Move Boulder Problems", into: contactPower, order: 3, area: "Pull",
                     reps: "6–10 moves", sets: "5 ascents", rest: "3 min")

            let strengthEndurance = CatalogSeeder.ensureType("Strength-Endurance", in: climb)
            strengthEndurance.typeDescription = "Endurance work for fingers and pull muscles"
            // Fingers
            ensureEx("Short-Duration Fingerboard Repeaters", into: strengthEndurance, order: 1, area: "Fingers",
                     reps: "6", sets: "3–5", rest: "1 min",
                     notes: "level1 : 10s work/30s rest; level2 : 10s work/20s rest; level3 : 10s work/10s rest")
            ensureEx("Long-Duration Fingerboard Repeaters", into: strengthEndurance, order: 2, area: "Fingers",
                     reps: "4", sets: "3–5", rest: "1 min",
                     notes: "level1 : 30s work/30s rest; level2 : 30s work/15s rest; level3 : 60s work/30s rest")
            // Pull
            ensureEx("Pull-Up Intervals", into: strengthEndurance, order: 1, area: "Pull",
                     reps: "5", sets: "10–20", rest: "No rest",
                     notes: "5 pull-ups every minute on the minute - rest time is the remainder of the minute")
            ensureEx("Frenchies", into: strengthEndurance, order: 2, area: "Pull",
                     reps: "2–6 cycles", sets: "2–4", rest: "5 min")
        }

        // ===== BOULDERING with COMBINATIONS =====
        let boulder = CatalogSeeder.ensureActivity("Bouldering", in: ctx)
        do {
            let bMax = CatalogSeeder.ensureType("Maximum & contact Strength", in: boulder)
            bMax.typeDescription = "Bouldering"

            let comb1 = ensureCombo("Limit combo", desc: "Limit and casual bouldering; 1:30 hours", in: bMax, deletingLegacyNames: ["Combination 1"])
            ensureComboEx("3–6 near-maximal boulders", into: comb1, order: 1, duration: "30 min", rest: "3 min/asc")
            ensureComboEx("Work on 1–3 limit boulders", into: comb1, order: 2, duration: "60 min", rest: "3 min/asc")

            let comb2 = ensureCombo("Styles combo", desc: "Mixed combination, rest 8 min between blocks; 1:45 hours", in: bMax, deletingLegacyNames: ["Combination 2"])
            ensureComboEx("Big, powerful moves", into: comb2, order: 1, duration: "25 min", rest: "3 min/asc", notes:"35°–45°")
            ensureComboEx("Footless problem on big holds", into: comb2, order: 2, duration: "15 min", rest: "3 min/asc" ,notes:"20°–45°")
            ensureComboEx("Coordination / dyno", into: comb2, order: 3, duration: "20 min", rest: "3 min/asc" ,notes:"0°–30°")
            ensureComboEx("Slabs", into: comb2, order: 4, duration: "20 min", rest: "3 min/asc" ,notes:"0°–30°")

            let comb3 = ensureCombo("Grades combo", desc: "Grade blocks with 6 min rest blocks; 1:50 hours", in: bMax, deletingLegacyNames: ["Combination 3"])
            ensureComboEx("V0–V2", into: comb3, order: 1,reps:"3", rest: "1 min/asc", notes: "rest block 3 min",  deletingLegacyNames: ["1. 3 problems V0–V2"])
            ensureComboEx("V3–V4", into: comb3, order: 2,reps:"3", rest: "3 min/asc", notes: "rest block 6 min",  deletingLegacyNames: ["2. 3 problems V3–V4"])
            ensureComboEx("V4–V5 (1st)", into: comb3, order: 3, reps:"3", rest: "3 min/asc", notes: "rest block 6 min",  deletingLegacyNames: ["3. 3 problems V4–V5"])
            ensureComboEx("V5–V6", into: comb3, order: 4, reps:"5", rest: "5 min/asc", notes: "rest block 6 min",  deletingLegacyNames: ["4. 3-5 problems V5–V6, 4. 5 problems V5–V6"])
            ensureComboEx("V4–V5 (2nd)", into: comb3, order: 5, reps:"3", rest: "3 min/asc", notes: "rest block 6 min",  deletingLegacyNames: ["5. 3 problems V4–V5"])

            let comb4 = ensureCombo("Board & limit combo", desc: "Boards & limit boulders; 1:30 hours", in: bMax, deletingLegacyNames: ["Combination 4"])
            ensureComboEx("Work on 1–3 limit boulders", into: comb4, order: 1, duration: "30 min", rest: "3 min/asc")
            ensureComboEx("Board", into: comb4, order: 2, duration: "60 min", rest: "3 min/asc")

            bMax.combinations = dedupPreserveOrder(bMax.combinations)

            let bSE = CatalogSeeder.ensureType("Strength-Endurance", in: boulder)
            bSE.typeDescription = "SE circuits"

            let combSE1 = ensureCombo("Classic 4X4", in: bSE, deletingLegacyNames: ["Combination 1"])
            ensureComboEx("Bouldering 4×4s", into: combSE1, order: 1,
                          reps: "4", duration: "on the minute", sets: "4", rest: "4 min",
                          notes: "4 boulders, 4 times on the minute - rest 4 minutes between problmes")

            let combSE2 = ensureCombo("Big moves 4×4s", in: bSE, deletingLegacyNames: ["Combination 2"])
            ensureComboEx("Big-holds, big-move 4×4s", into: combSE2, order: 1,
                          reps: "4", duration: "on the minute", sets: "4", rest: "4 min",
                          notes: "4 boulders, 4 times on the minute - rest 4 minutes between problmes")

            let combSE3 = ensureCombo("Grades combo", desc: "Alternating grade blocks with no rest between sends; 1:30 hours", in: bSE, deletingLegacyNames: ["Combination 3"])
            ensureComboEx("V0–V2", into: combSE3, order: 1, reps:"6", rest: "45 sec/asc", notes: "rest block 2 min",  deletingLegacyNames: ["1. 6 problems V0–V2"])
            ensureComboEx("V3–V4 (1st)", into: combSE3, order: 2, reps:"3", rest: "no rest between ascents", notes: "rest block 6 min",  deletingLegacyNames: ["2. 3 problems V3–V4"])
            ensureComboEx("V4–V5 (1st)" , into: combSE3, order: 3, reps:"3", rest: "no rest between ascents", notes: "rest block 6 min",  deletingLegacyNames: ["3. 3 problems V4–V5"])
            ensureComboEx("V3–V4 (2nd)", into: combSE3, order: 4, reps:"3", rest: "no rest between ascents", notes: "rest block 6 min",  deletingLegacyNames: ["4. 3 problems V3–V4"])
            ensureComboEx("V4–V5 (2nd)", into: combSE3, order: 5, reps:"3", rest: "no rest between ascents", notes: "rest block 6 min",  deletingLegacyNames: ["5. 3 problems V4–V5"])
            ensureComboEx("V3–V4 (3rd)", into: combSE3, order: 6, reps:"3", rest: "no rest between ascents", notes: "rest block 6 min",  deletingLegacyNames: ["6. 3 problems V3–V4"])
            ensureComboEx("V4–V5 (3rd)", into: combSE3, order: 7, reps:"3", rest: "no rest between ascents", notes: "rest block 6 min",  deletingLegacyNames: ["7. 3 problems V4–V5"])
            ensureComboEx("V3–V4 (4th)", into: combSE3, order: 8, reps:"3", rest: "no rest between ascents", notes: "rest block 6 min",  deletingLegacyNames: ["8. 3 problems V3–V4"])

            let combSE4 = ensureCombo("Board 3×6 combo", desc: "like 4×4s but for boards and harder", in: bSE, deletingLegacyNames: ["Combination 4"])
            ensureComboEx("Board 3×6", into: combSE4, order: 1,
                          reps: "3", duration: "on the minute", sets: "6", rest: "3 min",
                          notes: "6 boulders, 3 times on the minute - rest 3 minutes between boulders")

            bSE.combinations = dedupPreserveOrder(bSE.combinations)

            try? ctx.save()
        }
    }

    // MARK: - Helpers
    /// Upsert Exercise by name under a TrainingType, then update fields `order`, text fields, etc.
    @discardableResult
    private static func ensureEx(
        _ name: String,
        into type: TrainingType,
        order: Int,
        area: String? = nil,
        reps: String? = nil,
        duration: String? = nil,
        sets: String? = nil,
        rest: String? = nil,
        notes: String? = nil,
        description: String? = nil
    ) -> Exercise {
        CatalogSeeder.ensureExercise(
            name, in: type, reps: reps, duration: duration, sets: sets, rest: rest, notes: notes, area: area
        ) // insert if missing

        // Find it and update fields
        if let ex = type.exercises.first(where: { $0.name == name }) {
            ex.order = order
            ex.exerciseDescription = description
            ex.area = area
            ex.repsText = reps
            ex.durationText = duration
            ex.setsText = sets
            ex.restText = rest
            ex.notes = notes
            return ex
        } else {
            // Safety: create if somehow not present
            let ex = Exercise(
                name: name, area: area, order: order, exerciseDescription: description,
                repsText: reps, durationText: duration, setsText: sets, restText: rest, notes: notes
            )
            type.exercises.append(ex)
            return ex
        }
    }

    /// Upsert a BoulderCombination by name
    @discardableResult
    private static func ensureCombo(
        _ name: String,
        desc: String? = nil,
        in type: TrainingType,
        deletingLegacyNames legacyNames: [String] = [],
        context: ModelContext? = nil
    ) -> BoulderCombination {
        //Optionally remove legacy combos first
        if !legacyNames.isEmpty {
            func norm(_ s: String) -> String {
                s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            let legacy = Set(legacyNames.map(norm))

            // collect matches
            let toDelete = type.combinations.filter { legacy.contains(norm($0.name)) }
            if !toDelete.isEmpty {
                // detach from relationship
                type.combinations.removeAll { combo in
                    toDelete.contains(where: { $0 === combo })
                }
                // hard-delete if context provided (SwiftData)
                if let ctx = context {
                    toDelete.forEach { ctx.delete($0) }
                }
            }
        }
        if let c = type.combinations.first(where: { $0.name == name }) {
            if c.comboDescription != desc { c.comboDescription = desc }
            return c
        }
        let c = BoulderCombination(name: name, comboDescription: desc)
        type.combinations.append(c)
        return c
    }

    /// Upsert an Exercise inside a BoulderCombination by name and then update fields
    @discardableResult
    private static func ensureComboEx(
        _ name: String,
        into combo: BoulderCombination,
        order: Int,
        reps: String? = nil,
        duration: String? = nil,
        sets: String? = nil,
        rest: String? = nil,
        notes: String? = nil,
        description: String? = nil,
        deletingLegacyNames legacyNames: [String] = [],
        context: ModelContext? = nil
    ) -> Exercise {
        //Optionally remove legacy exercises first
        if !legacyNames.isEmpty {
            func norm(_ s: String) -> String {
                s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            let legacy = Set(legacyNames.map(norm))
            let toDelete = combo.exercises.filter { legacy.contains(norm($0.name)) }

            if !toDelete.isEmpty {
                // detach from relationship
                combo.exercises.removeAll { ex in
                    toDelete.contains(where: { $0 === ex })
                }
                // hard-delete if context provided (SwiftData)
                if let ctx = context {
                    toDelete.forEach { ctx.delete($0) }
                }
            }
        }
        if let ex = combo.exercises.first(where: { $0.name == name }) {
            ex.order = order
            ex.repsText = reps
            ex.durationText = duration
            ex.setsText = sets
            ex.restText = rest
            ex.notes = notes
            ex.exerciseDescription = description
            return ex
        }
        let ex = Exercise(
            name: name, order: order, exerciseDescription: description,
            repsText: reps, durationText: duration, setsText: sets, restText: rest, notes: notes
        )
        combo.exercises.append(ex)
        return ex
    }

    /// Simple de-dup by name, keeping first occurrence order
    private static func dedupPreserveOrder<T: AnyObject>(_ items: [T]) -> [T] {
        var seen = Set<ObjectIdentifier>()
        var out: [T] = []
        for x in items {
            let id = ObjectIdentifier(x)
            if !seen.contains(id) {
                out.append(x)
                seen.insert(id)
            }
        }
        return out
    }
}

// MARK: - PlanKind seeding
private func seedPlanKinds(_ context: ModelContext) {
    struct KindSeed { let key: String; let name: String; let totalWeeks: Int?; let isRepeating: Bool; let order: Int }

    let seeds: [KindSeed] = [
        .init(key: "daily",   name: "Daily",              totalWeeks: 0,  isRepeating: false, order: 0),
        .init(key: "weekly",  name: "Weekly",             totalWeeks: nil,isRepeating: true,  order: 1),
        .init(key: "3-2-1",   name: "3-2-1 (6 weeks)",    totalWeeks: 6,  isRepeating: false, order: 2),
        .init(key: "4-3-2-1", name: "4-3-2-1 (10 weeks)", totalWeeks: 10, isRepeating: false, order: 3)
    ]
    for s in seeds {
        let key = s.key  // capture as a plain value
        let fetch = FetchDescriptor<PlanKindModel>(
            predicate: #Predicate<PlanKindModel> { $0.key == key }
        );
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

// MARK: - DayType seeding
func seedDayTypes(_ context: ModelContext) {
    struct DaySeed {
        let key: String
        let name: String
        let colorKey: String
        let order: Int
        let isdefault: Bool
        let ishidden: Bool = false
    }

    let seeds: [DaySeed] = [
        .init(key: "climbingFull",    name: "Climb + Hi-Vol. exercises", colorKey: "green",  order: 0, isdefault: true),
        .init(key: "climbingSmall",   name: "Climb + Lo-Vol. exercises", colorKey: "blue",   order: 1, isdefault: true),
        .init(key: "climbingReduced", name: "Climb Low-Vol. ",           colorKey: "brown",  order: 2, isdefault: true),
        .init(key: "Perclimbing",     name: "Performance Climbing",      colorKey: "pink",   order: 3, isdefault: true),
        .init(key: "core",            name: "Core",                       colorKey: "orange", order: 4, isdefault: true),
        .init(key: "antagonist",      name: "Antagonist",                 colorKey: "cyan",   order: 5, isdefault: true),
        .init(key: "rest",            name: "Rest",                       colorKey: "purple", order: 6, isdefault: true),
        .init(key: "vacation",        name: "Vacation",                   colorKey: "yellow", order: 7, isdefault: true),
        .init(key: "sick",            name: "Sick",                       colorKey: "red",    order: 8, isdefault: true)]

    // Existing by key (includes hidden + visible)
    let existing: [DayTypeModel] = (try? context.fetch(FetchDescriptor<DayTypeModel>())) ?? []
    let existingByKey = Dictionary(
        existing.map { ($0.key, $0) },
        uniquingKeysWith: { a, b in
            // prefer non-hidden entry if duplicate keys exist
            if a.isHidden && !b.isHidden { return b }
            if !a.isHidden && b.isHidden { return a }
            return a
        }
    )
    
    // Insert only those seeds whose key is missing; leave all existing rows untouched
    for s in seeds where existingByKey[s.key] == nil {
        let safeColor = DayTypeModel.allowedColorKeys.contains(s.colorKey) ? s.colorKey : "gray"
        let new = DayTypeModel(
            key: s.key,
            name: s.name,
            order: s.order,
            colorKey: safeColor
        )
        // Seed visibility default; not touching existing rows’ visibility
        new.isHidden = s.ishidden ? true : false
        new.isdefault = s.isdefault
        context.insert(new)
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



