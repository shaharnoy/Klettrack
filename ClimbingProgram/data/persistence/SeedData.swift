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
    @discardableResult
    static func loadIfNeeded(_ context: ModelContext) -> CatalogSeedReport {
        // ---------- Catalog (idempotent upsert) ----------
        let report = CatalogSeeder.reconcile(catalogManifest(), in: context)

        // ---------- Other seeds ----------
        SeedClimbingData.loadIfNeeded(context) // only seeds if all gym and styles and days are empty
        try? context.save()

        SeedTimerTemplates.loadIfNeeded(context)   // timer templates - only seeds if no templates exist
        seedPlanKinds(context)                     // it alwasys seeds - since it's not modifiable it's not a problem
        seedDayTypes(context)                      // only upsert missing default day types, don't overwrite custom days and don't make unhidden ones hidden
        reconcilePlanDayTypesIfNeeded(context)     // keep plans aligned
        try? context.save()
        return report
    }

    static func nukeAndReseed(_ context: ModelContext) {
        // Delete everything relevant
        try? context.delete(model: Activity.self)
        try? context.delete(model: TrainingType.self)
        try? context.delete(model: BoulderCombination.self)
        try? context.delete(model: Exercise.self)
        try? context.delete(model: DeletedCatalogSeed.self)
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
    static func catalogManifest() -> CatalogSeedManifest {
        let builder = CatalogSeedManifestBuilder()
        // ===== CORE =====
        let core = builder.activity("Core", key: "activity.core")
        do {
            let anterior = core.type("Anterior Core", key: "type.core.anterior_core", typeDescription: "")
            ensureEx("Abdominal Crunches", into: anterior, seedKey: "exercise.core.anterior_core.abdominal_crunches", order: 1, reps: "25-100", sets: "2", rest: "3 min")
            ensureEx("Hanging Knee Lifts", into: anterior, seedKey: "exercise.core.anterior_core.hanging_knee_lifts", order: 2, reps: "15-20", sets: "2-3", rest: "3 min")
            ensureEx("1-Arm 1-Leg Plank", into: anterior, seedKey: "exercise.core.anterior_core.one_arm_one_leg_plank", order: 3, duration: "1 min", sets: "2", rest: "3 min")
            ensureEx("1-Arm Elbow & Side Plank", into: anterior, seedKey: "exercise.core.anterior_core.one_arm_elbow_side_plank", order: 4, duration: "2 min", sets: "1")
            ensureEx("Front Lever", into: anterior, seedKey: "exercise.core.anterior_core.front_lever", order: 5, reps: "2-5", sets: "1-2", rest: "3 min")

            let posterior = core.type("Posterior Core", key: "type.core.posterior_core", typeDescription: "")
            ensureEx("Superman", into: posterior, seedKey: "exercise.core.posterior_core.superman", order: 1, reps: "20", sets: "2", rest: "3 min")
            ensureEx("Reverse Plank", into: posterior, seedKey: "exercise.core.posterior_core.reverse_plank", order: 2, duration: "20-60 sec", sets: "1-2", rest: "3 min")
            ensureEx("Back Bridge", into: posterior, seedKey: "exercise.core.posterior_core.back_bridge", order: 3, reps: "15-20", sets: "1-2", rest: "3 min")
            ensureEx("Side Hip Raises", into: posterior, seedKey: "exercise.core.posterior_core.side_hip_raises", order: 4, reps: "10-20", sets: "2", rest: "1 min")

            let chain = core.type("Total Posterior Chain", key: "type.core.total_posterior_chain", typeDescription: "")
            ensureEx("Sumo Deadlift", into: chain, seedKey: "exercise.core.total_posterior_chain.sumo_deadlift", order: 1, reps: "10-15", sets: "2", rest: "3 min")
            ensureEx("Dumbbell Snatch", into: chain, seedKey: "exercise.core.total_posterior_chain.dumbbell_snatch", order: 2, reps: "5-8", sets: "2-3", rest: "3 min")
            ensureEx("Barbell Deadlift", into: chain, seedKey: "exercise.core.total_posterior_chain.barbell_deadlift", order: 3, reps: "3-6", sets: "2-4", rest: "3 min")
        }

        // ===== Mobility =====
        let mobility = builder.activity("Mobility", key: "activity.mobility")
        do {
            let bottom = mobility.type("Lower body", key: "type.mobility.lower_body", typeDescription: "")
            ensureEx("Knee-to-chest", into: bottom, seedKey: "exercise.mobility.lower_body.knee_to_chest", order: 1, reps: "2 each leg", duration: "30 sec")
            ensureEx("Band Hamstring Stretch", into: bottom, seedKey: "exercise.mobility.lower_body.band_hamstring_stretch", order: 2,reps: "3 each leg", duration: "30 sec")
            ensureEx("Butterfly Stretch", into: bottom, seedKey: "exercise.mobility.lower_body.butterfly_stretch", order: 3,reps: "2", duration: "30-60 sec")
            ensureEx("Seated Single-Leg Hip Adductor", into: bottom, seedKey: "exercise.mobility.lower_body.seated_single_leg_hip_adductor", order: 4,reps: "2 each leg", duration: "30 sec")
            ensureEx("Lunges", into: bottom, seedKey: "exercise.mobility.lower_body.lunges", order: 5,reps: "2 each leg", duration: "30 sec")
            ensureEx("Kneeling Quad and Hip Flexor Stretch", into: bottom, seedKey: "exercise.mobility.lower_body.kneeling_quad_hip_flexor_stretch", order: 6,reps: "2 each leg", duration: "30 sec")
            ensureEx("Seated Calf Stretch with Band", into: bottom, seedKey: "exercise.mobility.lower_body.seated_calf_stretch_band", order: 7,reps: "2 each leg", duration: "30 sec")
            ensureEx("Oblique Knees to One Side", into: bottom, seedKey: "exercise.mobility.lower_body.oblique_knees_one_side", order: 8,reps: "1 each side", duration: "30 sec")

        }
        // ===== ANTAGONIST & STABILIZER =====
        let ant = builder.activity("Antagonist & Stabilizer", key: "activity.antagonist_stabilizer")
        do {
            let wrist = ant.type("Wrist Stabilizers", key: "type.antagonist_stabilizer.wrist_stabilizers", typeDescription: "")
            ensureEx("Reverse Wrist Curls", into: wrist, seedKey: "exercise.antagonist_stabilizer.wrist_stabilizers.reverse_wrist_curls", order: 1, reps: "15–25", sets: "2–3", rest: "3 min")
            ensureEx("Pronator Isolation", into: wrist, seedKey: "exercise.antagonist_stabilizer.wrist_stabilizers.pronator_isolation", order: 2, reps: "20–25", sets: "2 in each hand", rest: "2 min")
            ensureEx("Wrist Extension Isometric", into: wrist, seedKey: "exercise.antagonist_stabilizer.wrist_stabilizers.wrist_extension_isometric", order: 3, duration: "1 min", sets: "2 each arm", rest: "2 min")
            ensureEx("Reverse Arm Curl", into: wrist, seedKey: "exercise.antagonist_stabilizer.wrist_stabilizers.reverse_arm_curl", order: 4, reps: "15–20", sets: "1–2", rest: "3 min")
            ensureEx("Wide Pinch Wrist Extention", into: wrist, seedKey: "exercise.antagonist_stabilizer.wrist_stabilizers.wide_pinch_wrist_extention", order: 5, duration: "30 sec", sets: "3–5", rest: "2 min")

            let cuff = ant.type("Rotator Cuff & Scap Stabilizers", key: "type.antagonist_stabilizer.rotator_cuff_scap_stabilizers", typeDescription: "")
            ensureEx("DB Internal Rotation", into: cuff, seedKey: "exercise.antagonist_stabilizer.rotator_cuff_scap_stabilizers.db_internal_rotation", order: 1, reps: "25", sets: "2 each hand")
            ensureEx("DB External Rotation", into: cuff, seedKey: "exercise.antagonist_stabilizer.rotator_cuff_scap_stabilizers.db_external_rotation", order: 2, reps: "25", sets: "2 each hand")
            ensureEx("Band T", into: cuff, seedKey: "exercise.antagonist_stabilizer.rotator_cuff_scap_stabilizers.band_t", order: 3, reps: "20", sets: "2", rest: "2 min")
            ensureEx("Band Y", into: cuff, seedKey: "exercise.antagonist_stabilizer.rotator_cuff_scap_stabilizers.band_y", order: 4, reps: "20", sets: "2", rest: "2 min")
            ensureEx("Scapular Push-Up", into: cuff, seedKey: "exercise.antagonist_stabilizer.rotator_cuff_scap_stabilizers.scapular_push_up", order: 5, reps: "15–20", sets: "1")
            ensureEx("Scapular Pull-Up", into: cuff, seedKey: "exercise.antagonist_stabilizer.rotator_cuff_scap_stabilizers.scapular_pull_up", order: 6, reps: "8–12", sets: "1")

            let push = ant.type("Antagonist (Push) Muscles", key: "type.antagonist_stabilizer.antagonist_push_muscles", typeDescription: "")
            ensureEx("Shoulder Press", into: push, seedKey: "exercise.antagonist_stabilizer.antagonist_push_muscles.shoulder_press", order: 1, reps: "15–20", sets: "1–2", rest: "3 min")
            ensureEx("Push-Up", into: push, seedKey: "exercise.antagonist_stabilizer.antagonist_push_muscles.push_up", order: 2, reps: "15–25", sets: "1–2", rest: "3 min")
        }
       
        // ===== GENERAL STRENGTH =====
        let strength = builder.activity("General Strength", key: "activity.general_strength")
        do {
            let pull = strength.type("Pull", key: "type.general_strength.pull")
            let push = strength.type("Push", key: "type.general_strength.push")
            let hinge = strength.type("Hinge", key: "type.general_strength.hinge")
            let squat = strength.type("Squat", key: "type.general_strength.squat")

            // Hinge
            ensureEx("Deadlift", into: hinge, seedKey: "exercise.general_strength.hinge.deadlift", order: 1, reps: "4", duration: nil, sets: "3", rest: "3-5 mins", notes: "RPE 6-7-8 after two warmup sets")
            ensureEx("Frog Stretch", into: hinge, seedKey: "exercise.general_strength.hinge.frog_stretch", order: 6, reps: nil , duration: "45 sec", sets: "3", rest: "3 mins", notes: "Mobility")
            ensureEx("Jefferson Curl", into: hinge, seedKey: "exercise.general_strength.hinge.jefferson_curl", order: 7, reps: "6", duration: nil, sets: "3", rest: "3 mins", notes: "Mobility")
            ensureEx("Seated Straddle Good Mornings", into: hinge, seedKey: "exercise.general_strength.hinge.seated_straddle_good_mornings", order: 4, reps: "6", duration: nil, sets: "3", rest: "3 mins", notes: "Mobility")
            ensureEx("Hip Thrust", into: hinge, seedKey: "exercise.general_strength.hinge.hip_thrust", order: 2, reps: "4", duration: nil, sets: "3", rest: "3-5 mins", notes: "RPE 6-7-8 after two warmup sets")
            ensureEx("RDLs", into: hinge, seedKey: "exercise.general_strength.hinge.rdls", order: 3, reps: "4", duration: nil, sets: "3", rest: "3-5 mins", notes: "RPE 6-7-8 after two warmup sets")
            ensureEx("Bulgarian Deadlift", into: hinge, seedKey: "exercise.general_strength.hinge.bulgarian_deadlift", order: 4, reps: "4", duration: nil, sets: "3", rest: "3-5 mins", notes: "RPE 6-7-8 after two warmup sets")
            ensureEx("Single-Leg Romanian Deadlift", into: hinge, seedKey: "exercise.general_strength.hinge.single_leg_romanian_deadlift", order: 5, reps: "4", duration: nil, sets: "3", rest: "3-5 mins", notes: "RPE 6-7-8 after two warmup sets")

            // Pull
            ensureEx("External Shoulder Rotations", into: pull, seedKey: "exercise.general_strength.pull.external_shoulder_rotations", order: 3, reps: "10", duration: nil, sets: "3", rest: "3 mins", notes: "Accessory Lifts")
            ensureEx("Single Straight Arm Cable/Band Pull Down", into: pull, seedKey: "exercise.general_strength.pull.single_straight_arm_cable_band_pull_down", order: 4, reps: "10", duration: nil, sets: "3", rest: "3 mins", notes: "Accessory Lifts")
            ensureEx("Bent Over Row", into: pull, seedKey: "exercise.general_strength.pull.bent_over_row", order: 1, reps: "4", duration: nil, sets: "3", rest: "3-5 mins", notes: "RPE 6-7-8 after two warmup sets")
            ensureEx("Weighted Pull Ups", into: pull, seedKey: "exercise.general_strength.pull.weighted_pull_ups", order: 2, reps: "4", duration: nil, sets: "3", rest: "3-5 mins", notes: "RPE 6-7-8 after two warmup sets")

            // Squat
            ensureEx("Back Squat", into: squat, seedKey: "exercise.general_strength.squat.back_squat", order: 1, reps: "4", duration: nil, sets: "3", rest: "3-5 mins", notes: "RPE 6-7-8 after two warmup sets")
            ensureEx("Squats", into: squat, seedKey: "exercise.general_strength.squat.squats", order: 4, reps: "4", duration: nil, sets: "3", rest: "3-5 mins", notes: "RPE 6-7-8 after two warmup sets")
            ensureEx("Split Squats", into: squat, seedKey: "exercise.general_strength.squat.split_squats", order: 2, reps: "4", duration: nil, sets: "3", rest: "3-5 mins", notes: "RPE 6-7-8 after two warmup sets")
            ensureEx("Bulgarian Split Squats", into: squat, seedKey: "exercise.general_strength.squat.bulgarian_split_squats", order: 3, reps: "4", duration: nil, sets: "3", rest: "3-5 mins", notes: "RPE 6-7-8 after two warmup sets")
            ensureEx("Cossack Squat", into: squat, seedKey: "exercise.general_strength.squat.cossack_squat", order: 5, reps: "6", duration: nil, sets: "3", rest: "3 mins", notes: "Mobility")

            // Push
            ensureEx("Bench Press", into: push, seedKey: "exercise.general_strength.push.bench_press", order: 1, reps: "4", duration: nil, sets: "3", rest: "3-5 mins", notes: "RPE 6-7-8 after two warmup sets")
            ensureEx("Incline Press", into: push, seedKey: "exercise.general_strength.push.incline_press", order: 2, reps: "4", duration: nil, sets: "3", rest: "3-5 mins", notes: "RPE 6-7-8 after two warmup sets")
            ensureEx("Overhead Press", into: push, seedKey: "exercise.general_strength.push.overhead_press", order: 3, reps: "4", duration: nil, sets: "3", rest: "3-5 mins", notes: "RPE 6-7-8 after two warmup sets")
            ensureEx("Prone Military Press", into: push, seedKey: "exercise.general_strength.push.prone_military_press", order: 4, reps: "10", duration: nil, sets: "3", rest: "3 mins", notes: "Accessory Lifts")
            ensureEx("Lateral Raise", into: push, seedKey: "exercise.general_strength.push.lateral_raise", order: 5, reps: "10", duration: nil, sets: "3", rest: "3 mins", notes: "Accessory Lifts")
        }

        // ===== CLIMBING-SPECIFIC (non-bouldering) =====
        let climb = builder.activity("Climbing-Specific Exercises", key: "activity.climbing_specific")
        do {
            let maxStrength = climb.type("Maximum & Contact Strength", key: "type.climbing_specific.maximum_contact_strength", area: nil, typeDescription: "Maximum and contact strength for fingers and pull muscles")
            // Fingers
            ensureEx("FB \"Minimum Edge\" Hangs", into: maxStrength, seedKey: "exercise.climbing_specific.maximum_contact_strength.fb_minimum_edge_hangs", order: 1, area: "Fingers",
                     reps: "5", sets: "2–5", notes: "12s work, 3min rest", description: "Smallest edge you can hold ~12s")
            ensureEx("FB Max-Weight Hangs (10s, 14–20mm)", into: maxStrength, seedKey: "exercise.climbing_specific.maximum_contact_strength.fb_max_weight_hangs_10s", order: 2, area: "Fingers",
                     reps: "5", sets: "2–5", notes: "")
            ensureEx("FB Max-Weight Hangs (7/53, 14–20mm)", into: maxStrength, seedKey: "exercise.climbing_specific.maximum_contact_strength.fb_max_weight_hangs_7_53", order: 3, area: "Fingers",
                     reps: "3", sets: "2–5", notes: "7s work, 53s rest")
            ensureEx("One Arm Hangs", into: maxStrength, seedKey: "exercise.climbing_specific.maximum_contact_strength.one_arm_hangs", order: 4, area: "Fingers",
                     reps: "1 each hand", sets: "3", notes: "5s work, 3min rest; assist with band if needed", description: "4 finger edge (20mm)")
            ensureEx("Loading Pin Lifts — repetitions", into: maxStrength, seedKey: "exercise.climbing_specific.maximum_contact_strength.loading_pin_lifts", order: 5, area: "Fingers",
                     reps: "1:50% 2:60% 3:70% 4–7:80%", sets: "8 reps (1–3); 4 reps (4–7)")
            ensureEx("Bouldering", into: maxStrength, seedKey: "exercise.climbing_specific.maximum_contact_strength.bouldering", order: 6, area: "Fingers",
                     reps: "3 ascents", sets: "3–10 problems", rest: "2 min/asc")
            // Pull
            ensureEx("Weighted Pull-Ups", into: maxStrength, seedKey: "exercise.climbing_specific.maximum_contact_strength.weighted_pull_ups", order: 1, area: "Pull",
                     reps: "5", sets: "3–6", rest: "3 min")
            ensureEx("Square Pull-Ups", into: maxStrength, seedKey: "exercise.climbing_specific.maximum_contact_strength.square_pull_ups", order: 2, area: "Pull",
                     reps: "3–6", sets: "1–2", rest: "3 min")
            ensureEx("Uneven-Grip Pull-Ups", into: maxStrength, seedKey: "exercise.climbing_specific.maximum_contact_strength.uneven_grip_pull_ups", order: 3, area: "Pull",
                     reps: "3–5 each side", sets: "2–3", rest: "2 min")
            ensureEx("System Wall Isolation", into: maxStrength, seedKey: "exercise.climbing_specific.maximum_contact_strength.system_wall_isolation", order: 4, area: "Pull",
                     reps: "3–5 each side", sets: "2–5", rest: "3 min")
            ensureEx("Steep Wall Lock-Offs", into: maxStrength, seedKey: "exercise.climbing_specific.maximum_contact_strength.steep_wall_lock_offs", order: 5, area: "Pull",
                     reps: "4–6 each side", sets: "2–5", rest: "brief")
            ensureEx("One-Arm Lock-Offs", into: maxStrength, seedKey: "exercise.climbing_specific.maximum_contact_strength.one_arm_lock_offs", order: 6, area: "Pull",
                     reps: "2–3", sets: "2–3", rest: "2 min")

            let contactPower = climb.type("Contact Strength & Power", key: "type.climbing_specific.contact_strength_power", typeDescription: "Contact strength, explosive recruitment, and pulling power")
            // Fingers
            ensureEx("Campus Board Bumps", into: contactPower, seedKey: "exercise.climbing_specific.contact_strength_power.campus_board_bumps", order: 1, area: "Fingers",
                     reps: "2–4 sets each side", rest: "2 min")
            ensureEx("CB Laddering (no skips, small rungs)", into: contactPower, seedKey: "exercise.climbing_specific.contact_strength_power.cb_laddering_small_rungs", order: 2, area: "Fingers",
                     reps: "up only", sets: "3–10", rest: "2–3 min")
            ensureEx("Campus Switch Hands", into: contactPower, seedKey: "exercise.climbing_specific.contact_strength_power.campus_switch_hands", order: 3, area: "Fingers",
                     reps: "12 switches", sets: "2", rest: "2 min")
            ensureEx("One-Arm Lunging", into: contactPower, seedKey: "exercise.climbing_specific.contact_strength_power.one_arm_lunging", order: 4, area: "Fingers",
                     reps: "6–12 moves", sets: "2–3", rest: "minimal")
            // Pull
            ensureEx("CB Laddering (larger rungs w/ skips)", into: contactPower, seedKey: "exercise.climbing_specific.contact_strength_power.cb_laddering_large_rungs", order: 1, area: "Pull",
                     reps: "1–3–5–7", sets: "3–10", rest: "3 min")
            ensureEx("Boulder Campusing", into: contactPower, seedKey: "exercise.climbing_specific.contact_strength_power.boulder_campusing", order: 2, area: "Pull",
                     reps: "3–8 moves", sets: "3–5", rest: "3 min")
            ensureEx("Big-Move Boulder Problems", into: contactPower, seedKey: "exercise.climbing_specific.contact_strength_power.big_move_boulder_problems", order: 3, area: "Pull",
                     reps: "6–10 moves", sets: "5 ascents", rest: "3 min")

            let strengthEndurance = climb.type("Strength-Endurance", key: "type.climbing_specific.strength_endurance", typeDescription: "Endurance work for fingers and pull muscles")
            // Fingers
            ensureEx("Short-Duration Fingerboard Repeaters", into: strengthEndurance, seedKey: "exercise.climbing_specific.strength_endurance.short_duration_fingerboard_repeaters", order: 1, area: "Fingers",
                     reps: "6", sets: "3–5", rest: "1 min",
                     notes: "level1 : 10s work/30s rest; level2 : 10s work/20s rest; level3 : 10s work/10s rest")
            ensureEx("Long-Duration Fingerboard Repeaters", into: strengthEndurance, seedKey: "exercise.climbing_specific.strength_endurance.long_duration_fingerboard_repeaters", order: 2, area: "Fingers",
                     reps: "4", sets: "3–5", rest: "1 min",
                     notes: "level1 : 30s work/30s rest; level2 : 30s work/15s rest; level3 : 60s work/30s rest")
            // Pull
            ensureEx("Pull-Up Intervals", into: strengthEndurance, seedKey: "exercise.climbing_specific.strength_endurance.pull_up_intervals", order: 1, area: "Pull",
                     reps: "5", sets: "10–20", rest: "No rest",
                     notes: "5 pull-ups every minute on the minute - rest time is the remainder of the minute")
            ensureEx("Frenchies", into: strengthEndurance, seedKey: "exercise.climbing_specific.strength_endurance.frenchies", order: 2, area: "Pull",
                     reps: "2–6 cycles", sets: "2–4", rest: "5 min")
        }

        // ===== BOULDERING with COMBINATIONS =====
        let boulder = builder.activity("Bouldering", key: "activity.bouldering")
        do {
            let bMax = boulder.type("Maximum & contact Strength", key: "type.bouldering.maximum_contact_strength", typeDescription: "Bouldering")

            let comb1 = ensureCombo("Limit combo", seedKey: "combination.bouldering.maximum_contact.limit", desc: "Limit and casual bouldering; 1:30 hours", in: bMax, deletingLegacyNames: ["Combination 1"])
            ensureComboEx("3–6 near-maximal boulders", into: comb1, seedKey: "exercise.bouldering.maximum_contact.limit.near_maximal_boulders", order: 1, duration: "30 min", rest: "3 min/asc")
            ensureComboEx("Work on 1–3 limit boulders", into: comb1, seedKey: "exercise.bouldering.maximum_contact.limit.work_limit_boulders", order: 2, duration: "60 min", rest: "3 min/asc")

            let comb2 = ensureCombo("Styles combo", seedKey: "combination.bouldering.maximum_contact.styles", desc: "Mixed combination, rest 8 min between blocks; 1:45 hours", in: bMax, deletingLegacyNames: ["Combination 2"])
            ensureComboEx("Big, powerful moves", into: comb2, seedKey: "exercise.bouldering.maximum_contact.styles.big_powerful_moves", order: 1, duration: "25 min", rest: "3 min/asc", notes:"35°–45°")
            ensureComboEx("Footless problem on big holds", into: comb2, seedKey: "exercise.bouldering.maximum_contact.styles.footless_big_holds", order: 2, duration: "15 min", rest: "3 min/asc" ,notes:"20°–45°")
            ensureComboEx("Coordination / dyno", into: comb2, seedKey: "exercise.bouldering.maximum_contact.styles.coordination_dyno", order: 3, duration: "20 min", rest: "3 min/asc" ,notes:"0°–30°")
            ensureComboEx("Slabs", into: comb2, seedKey: "exercise.bouldering.maximum_contact.styles.slabs", order: 4, duration: "20 min", rest: "3 min/asc" ,notes:"0°–30°")

            let comb3 = ensureCombo("Grades combo", seedKey: "combination.bouldering.maximum_contact.grades", desc: "Grade blocks with 6 min rest blocks; 1:50 hours", in: bMax, deletingLegacyNames: ["Combination 3"])
            ensureComboEx("V0–V2", into: comb3, seedKey: "exercise.bouldering.maximum_contact.grades.v0_v2", order: 1,reps:"3", rest: "1 min/asc", notes: "rest block 3 min",  deletingLegacyNames: ["1. 3 problems V0–V2"])
            ensureComboEx("V3–V4", into: comb3, seedKey: "exercise.bouldering.maximum_contact.grades.v3_v4", order: 2,reps:"3", rest: "3 min/asc", notes: "rest block 6 min",  deletingLegacyNames: ["2. 3 problems V3–V4"])
            ensureComboEx("V4–V5 (1st)", into: comb3, seedKey: "exercise.bouldering.maximum_contact.grades.v4_v5_first", order: 3, reps:"3", rest: "3 min/asc", notes: "rest block 6 min",  deletingLegacyNames: ["3. 3 problems V4–V5"])
            ensureComboEx("V5–V6", into: comb3, seedKey: "exercise.bouldering.maximum_contact.grades.v5_v6", order: 4, reps:"5", rest: "5 min/asc", notes: "rest block 6 min",  deletingLegacyNames: ["4. 3-5 problems V5–V6, 4. 5 problems V5–V6"])
            ensureComboEx("V4–V5 (2nd)", into: comb3, seedKey: "exercise.bouldering.maximum_contact.grades.v4_v5_second", order: 5, reps:"3", rest: "3 min/asc", notes: "rest block 6 min",  deletingLegacyNames: ["5. 3 problems V4–V5"])

            let comb4 = ensureCombo("Board & limit combo", seedKey: "combination.bouldering.maximum_contact.board_limit", desc: "Boards & limit boulders; 1:30 hours", in: bMax, deletingLegacyNames: ["Combination 4"])
            ensureComboEx("Work on 1–3 limit boulders", into: comb4, seedKey: "exercise.bouldering.maximum_contact.board_limit.work_limit_boulders", order: 1, duration: "30 min", rest: "3 min/asc")
            ensureComboEx("Board", into: comb4, seedKey: "exercise.bouldering.maximum_contact.board_limit.board", order: 2, duration: "60 min", rest: "3 min/asc")

            let bSE = boulder.type("Strength-Endurance", key: "type.bouldering.strength_endurance", typeDescription: "SE circuits")

            let combSE3 = ensureCombo("Grades combo", seedKey: "combination.bouldering.strength_endurance.grades", desc: "Alternating grade blocks with no rest between sends; 1:30 hours", in: bSE, deletingLegacyNames: ["Combination 3"])
            ensureComboEx("V0–V2", into: combSE3, seedKey: "exercise.bouldering.strength_endurance.grades.v0_v2", order: 1, reps:"6", rest: "45 sec/asc", notes: "rest block 2 min",  deletingLegacyNames: ["1. 6 problems V0–V2"])
            ensureComboEx("V3–V4 (1st)", into: combSE3, seedKey: "exercise.bouldering.strength_endurance.grades.v3_v4_first", order: 2, reps:"3", rest: "no rest between ascents", notes: "rest block 6 min",  deletingLegacyNames: ["2. 3 problems V3–V4"])
            ensureComboEx("V4–V5 (1st)" , into: combSE3, seedKey: "exercise.bouldering.strength_endurance.grades.v4_v5_first", order: 3, reps:"3", rest: "no rest between ascents", notes: "rest block 6 min",  deletingLegacyNames: ["3. 3 problems V4–V5"])
            ensureComboEx("V3–V4 (2nd)", into: combSE3, seedKey: "exercise.bouldering.strength_endurance.grades.v3_v4_second", order: 4, reps:"3", rest: "no rest between ascents", notes: "rest block 6 min",  deletingLegacyNames: ["4. 3 problems V3–V4"])
            ensureComboEx("V4–V5 (2nd)", into: combSE3, seedKey: "exercise.bouldering.strength_endurance.grades.v4_v5_second", order: 5, reps:"3", rest: "no rest between ascents", notes: "rest block 6 min",  deletingLegacyNames: ["5. 3 problems V4–V5"])
            ensureComboEx("V3–V4 (3rd)", into: combSE3, seedKey: "exercise.bouldering.strength_endurance.grades.v3_v4_third", order: 6, reps:"3", rest: "no rest between ascents", notes: "rest block 6 min",  deletingLegacyNames: ["6. 3 problems V3–V4"])
            ensureComboEx("V4–V5 (3rd)", into: combSE3, seedKey: "exercise.bouldering.strength_endurance.grades.v4_v5_third", order: 7, reps:"3", rest: "no rest between ascents", notes: "rest block 6 min",  deletingLegacyNames: ["7. 3 problems V4–V5"])
            ensureComboEx("V3–V4 (4th)", into: combSE3, seedKey: "exercise.bouldering.strength_endurance.grades.v3_v4_fourth", order: 8, reps:"3", rest: "no rest between ascents", notes: "rest block 6 min",  deletingLegacyNames: ["8. 3 problems V3–V4"])
            
            ensureEx(
                "Classic 4×4",
                into: bSE,
                seedKey: "exercise.bouldering.strength_endurance.classic_4x4",
                order: 1,
                reps: "4",
                duration: "on the minute",
                sets: "4",
                rest: "4 min",
                notes: "4 boulders, 4 times on the minute – rest 4 minutes between problems"
            )

            ensureEx(
                "Big moves 4×4",
                into: bSE,
                seedKey: "exercise.bouldering.strength_endurance.big_moves_4x4",
                order: 2,
                reps: "4",
                duration: "on the minute",
                sets: "4",
                rest: "4 min",
                notes: "4 boulders, 4 times on the minute – rest 4 minutes between problems"
            )

            ensureEx(
                "Board 3×6",
                into: bSE,
                seedKey: "exercise.bouldering.strength_endurance.board_3x6",
                order: 3,
                reps: "3",
                duration: "on the minute",
                sets: "6",
                rest: "3 min",
                notes: "6 boulders, 3 times on the minute – rest 3 minutes between boulders"
            )

            ensureEx("10 moves boulder 3 times in a row", into: bSE, seedKey: "exercise.bouldering.strength_endurance.ten_moves_boulder_three_times", order: 4, reps: "3", duration: nil, sets: "1", rest: "no rest between ascents", notes: "As the name suggests, do 10 moves boulder in a row with only a brief rest between. Make sure you find a problem that you can send")
            
            // ===== SKILL TRAINING =====
            let skill = boulder.type("Skill training", key: "type.bouldering.skill_training", typeDescription: "")

            ensureEx("Same Problem-Different Solution", into: skill, seedKey: "exercise.bouldering.skill_training.same_problem_different_solution", order: 1, reps: nil, duration: nil, sets: nil, rest: nil, notes: nil)

            ensureEx("One Leg", into: skill, seedKey: "exercise.bouldering.skill_training.one_leg", order: 2, reps: nil, duration: nil, sets: nil, rest: nil, notes: "https://www.youtube.com/watch?v=N_K0uSUuz_4")

            ensureEx("One Size Fits All", into: skill, seedKey: "exercise.bouldering.skill_training.one_size_fits_all", order: 3, reps: nil, duration: nil, sets: nil, rest: nil, notes: "https://www.youtube.com/watch?v=IuYm8k17-vA")

            ensureEx("Sloth Monkey", into: skill, seedKey: "exercise.bouldering.skill_training.sloth_monkey", order: 4, reps: nil, duration: nil, sets: nil, rest: nil, notes: "https://www.youtube.com/watch?v=AGjQ_U-5iuk")

            ensureEx("Hover", into: skill, seedKey: "exercise.bouldering.skill_training.hover", order: 5, reps: nil, duration: nil, sets: nil, rest: nil, notes: "https://www.youtube.com/watch?v=LBFvKsIqNUw")

            ensureEx("Flash Execution", into: skill, seedKey: "exercise.bouldering.skill_training.flash_execution", order: 6, reps: nil, duration: nil, sets: nil, rest: nil, notes: nil)

            ensureEx("Rooting", into: skill, seedKey: "exercise.bouldering.skill_training.rooting", order: 7, reps: nil, duration: nil, sets: nil, rest: nil, notes: "https://www.youtube.com/watch?v=MjtTQYZGMeE")

            ensureEx("Dead Stop", into: skill, seedKey: "exercise.bouldering.skill_training.dead_stop", order: 8, reps: nil, duration: nil, sets: nil, rest: nil, notes: "https://www.youtube.com/watch?v=ovnBGz5fD4Q")

            ensureEx("False Start", into: skill, seedKey: "exercise.bouldering.skill_training.false_start", order: 9, reps: nil, duration: nil, sets: nil, rest: nil, notes: "https://www.youtube.com/watch?v=1i8SNRkUwhI")

            ensureEx("Hip Shapes", into: skill, seedKey: "exercise.bouldering.skill_training.hip_shapes", order: 10, reps: nil, duration: nil, sets: nil, rest: nil, notes: "https://www.youtube.com/watch?v=QF0OxJk1xs4")

            ensureEx("Heavy Fit", into: skill, seedKey: "exercise.bouldering.skill_training.heavy_fit", order: 11, reps: nil, duration: nil, sets: nil, rest: nil, notes: "https://www.youtube.com/watch?v=yYlaFzuotoE")

            ensureEx("Hand Foot Matching", into: skill, seedKey: "exercise.bouldering.skill_training.hand_foot_matching", order: 12, reps: nil, duration: nil, sets: nil, rest: nil, notes: "https://www.youtube.com/watch?v=mI8KcGhVCoY")

            ensureEx("Matched Breathing", into: skill, seedKey: "exercise.bouldering.skill_training.matched_breathing", order: 13, reps: nil, duration: nil, sets: nil, rest: nil, notes: "https://youtu.be/epkmqDd_tH4?t=619&si=GRFODM7vEzgmmeut")

            ensureEx("One Touch", into: skill, seedKey: "exercise.bouldering.skill_training.one_touch", order: 14, reps: nil, duration: nil, sets: nil, rest: nil, notes: "https://www.youtube.com/watch?v=OPVvZCRToLo")

            ensureEx("10 Mins Takedown", into: skill, seedKey: "exercise.bouldering.skill_training.ten_mins_takedown", order: 15, reps: nil, duration: nil, sets: nil, rest: nil, notes: "https://www.youtube.com/watch?v=WtxZElPjzZ8")

        }
        return builder.manifest
    }

    // MARK: - Manifest helpers
    @discardableResult
    private static func ensureEx(
        _ name: String,
        into type: CatalogTypeSeed,
        seedKey explicitSeedKey: String? = nil,
        order: Int,
        area: String? = nil,
        reps: String? = nil,
        duration: String? = nil,
        sets: String? = nil,
        rest: String? = nil,
        notes: String? = nil,
        description: String? = nil
    ) -> CatalogExerciseSeed {
        let seed = CatalogExerciseSeed(
            key: explicitSeedKey ?? "\(type.key).exercise.\(stableSegment(area ?? "default")).\(order)",
            name: name,
            aliases: [],
            order: order,
            area: area,
            exerciseDescription: description,
            reps: reps,
            duration: duration,
            sets: sets,
            rest: rest,
            notes: notes
        )
        type.exercises.append(seed)
        return seed
    }

    @discardableResult
    private static func ensureCombo(
        _ name: String,
        seedKey: String? = nil,
        desc: String? = nil,
        in type: CatalogTypeSeed,
        deletingLegacyNames legacyNames: [String] = []
    ) -> CatalogCombinationSeed {
        let seed = CatalogCombinationSeed(
            key: seedKey ?? "\(type.key).combination.\(stableSegment(name))",
            name: name,
            aliases: legacyNames,
            combinationDescription: desc
        )
        type.combinations.append(seed)
        return seed
    }

    @discardableResult
    private static func ensureComboEx(
        _ name: String,
        into combo: CatalogCombinationSeed,
        seedKey explicitSeedKey: String? = nil,
        order: Int,
        reps: String? = nil,
        duration: String? = nil,
        sets: String? = nil,
        rest: String? = nil,
        notes: String? = nil,
        description: String? = nil,
        deletingLegacyNames legacyNames: [String] = []
    ) -> CatalogExerciseSeed {
        let seed = CatalogExerciseSeed(
            key: explicitSeedKey ?? "\(combo.key).exercise.\(order)",
            name: name,
            aliases: legacyNames,
            order: order,
            area: nil,
            exerciseDescription: description,
            reps: reps,
            duration: duration,
            sets: sets,
            rest: rest,
            notes: notes
        )
        combo.exercises.append(seed)
        return seed
    }

    private static func stableSegment(_ value: String) -> String {
        value.lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }
            .joined()
            .split(separator: "_")
            .joined(separator: "_")
    }

}

// MARK: - PlanKind seeding
private func seedPlanKinds(_ context: ModelContext) {
    struct KindSeed { let key: String; let name: String; let totalWeeks: Int?; let isRepeating: Bool; let order: Int }

    let seeds: [KindSeed] = [
        .init(key: "daily",   name: "Daily",              totalWeeks: nil,isRepeating: false, order: 0),
        .init(key: "weekly",  name: "Weekly",             totalWeeks: nil,isRepeating: true,  order: 1),
        .init(key: "3-2-1",   name: "3-2-1 (6 weeks)",    totalWeeks: 6,  isRepeating: false, order: 2),
        .init(key: "4-3-2-1", name: "4-3-2-1 (10 weeks)", totalWeeks: 10, isRepeating: false, order: 3),
        .init(key: "4+1", name: "4 Weeks work, 1 Week deload", totalWeeks: 5, isRepeating: false, order: 4)
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
