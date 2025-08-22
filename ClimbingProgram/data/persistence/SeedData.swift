//
//  SeedData.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//

import SwiftData
        
struct SeedData {
            static func loadIfNeeded(_ context: ModelContext) {
                let count = (try? context.fetchCount(FetchDescriptor<Activity>())) ?? 0
                guard count == 0 else { return } // fresh-only

                // ========== CORE ==========
                let core = Activity(name: "Core")

                let anterior = TrainingType(name: "Anterior Core", typeDescription: "how many to do + short desc")
                anterior.exercises = [
                    Exercise(name: "Abdominal Crunches", repsText: "25-100", setsText: "2", restText:"3 mins"),
                    Exercise(name: "Hanging Knee Lifts", repsText: "15-20", setsText: "2-3", restText:"3 mins"),
                    Exercise(name: "1-Arm 1-Leg Plank", repsText: "1 mins", setsText: "2", restText:"3 mins"),
                    Exercise(name: "1-Arm Elbow & Side Plank", repsText: "2 mins"),
                    Exercise(name: "Front Lever", repsText: "2-5", setsText: "1-2", restText:"3 mins"),
                ]

                let posterior = TrainingType(name: "Posterior Core", typeDescription: "how many to do + short desc")
                posterior.exercises = [
                    Exercise(name: "Superman", repsText: "20", setsText: "2", restText:"3 mins"),
                    Exercise(name: "Reverse Plank", repsText: "20-60 sec.", setsText: "1-2", restText:"3 mins"),
                    Exercise(name: "Back Bridge", repsText: "15-20", setsText: "1-2", restText:"3 mins"),
                    Exercise(name: "Side Hip Raises", repsText: "10-20", setsText: "2", restText:"1 mins"),
                ]

                let chain = TrainingType(name: "Total/Posterior Chain", typeDescription: "how many to do + short desc")
                chain.exercises = [
                    Exercise(name: "Sumo Deadlift", repsText: "10-15", setsText: "2", restText:"3 mins"),
                    Exercise(name: "Dumbbell Snatch", repsText: "5-8", setsText: "2-3", restText:"3 mins"),
                    Exercise(name: "Barbell Deadlift", repsText: "3-6", setsText: "2-4", restText:"3 mins")
                ]

                core.types = [anterior, posterior, chain]

                // ========== ANTAGONIST ==========
                let ant = Activity(name: "Antagonist & Stabilizer")

                let wrist = TrainingType(name: "Wrist & Forearm Stabilizers", typeDescription: "Finger, wrist, and forearm stabilizers to balance climbing loads.")
                wrist.exercises = [
                    Exercise(name: "Reverse Wrist Curls", repsText: "15–25", setsText: "2–3", restText:"3 mins"),
                    Exercise(name: "Pronator Isolation", repsText: "20–25", setsText: "2 in each hand", restText:"2 mins"),
                    Exercise(name: "Reverse Arm Curl", repsText: "15–20", setsText: "1–2", restText:"3 mins"),
                    Exercise(name: "Wrist Extension Isometric", repsText: "45–60 sec, 2 each arm", setsText: "2", restText:"2 mins"),
                    Exercise(name: "Wide Pinch Wrist Ext.", repsText: "30 seconds", setsText: "3–5", restText:"2 mins")
                ]

                let cuff = TrainingType(name: "Rotator Cuff & Scap Stabilizers", typeDescription: "Scapular control and cuff health.")
                cuff.exercises = [
                    Exercise(name: "DB Internal Rotation", repsText: "25", setsText: "2 each hand"),
                    Exercise(name: "DB External Rotation", repsText: "25", setsText: "2 each hand"),
                    Exercise(name: "Band T", repsText: "20", setsText: "2", restText:"2 mins"),
                    Exercise(name: "Band Y", repsText: "20", setsText: "2", restText:"2 mins"),
                    Exercise(name: "Scapular Push-Up", repsText: "15–20", setsText: "1"),
                    Exercise(name: "Scapular Pull-Up", repsText: "8–12", setsText: "1")
                ]

                let push = TrainingType(name: "Antagonist (Push) Muscles", typeDescription: "Pressing patterns to balance pulling volume.")
                push.exercises = [
                    Exercise(name: "Shoulder Press", repsText: "15–20", setsText: "1–2"),
                    Exercise(name: "Push-Up", repsText: "15–25", setsText: "1–2")
                ]

                ant.types = [wrist, cuff, push]

                // ========== CLIMBING-SPECIFIC (non-bouldering) ==========
                let climb = Activity(name: "Climbing-Specific Exercises")

                let maxF = TrainingType(name: "Maximum & Contact Strength", area: "Fingers", typeDescription: "TBD")
                maxF.exercises = [
                    Exercise(name: "Bouldering", repsText: "3 ascents", setsText: "3–10 problems", restText: "2 min/asc"),
                    Exercise(name: "FB “Minimum Edge” Hangs", exerciseDescription: "Smallest edge you can hold ~12s.", repsText: "see protocol", setsText: "2–5"),
                    Exercise(name: "FB Max-Weight Hangs (10s, 14–20mm)", repsText: "see protocol", setsText: "2–5"),
                    Exercise(name: "FB Max-Weight Hangs (7/53, 14–20mm)", repsText: "see protocol", setsText: "2–5"),
                    Exercise(name: "Loading Pin Lifts — repetitions", repsText: "1:50% 2:60% 3:70% 4–7:80%", setsText: "8 reps (1–3); 4 reps (4–7)")
                ]

                let maxP = TrainingType(name: "Maximum & Contact Strength", area: "Pull", typeDescription: "Max pulling force and lockoffs.")
                maxP.exercises = [
                    Exercise(name: "Weighted Pull-Ups", repsText: "5", setsText: "3–6", restText: "3 min"),
                    Exercise(name: "Square Pull-Ups", repsText: "3–6", setsText: "1–2", restText: "3 min"),
                    Exercise(name: "System Wall Isolation", repsText: "3–5 each side", setsText: "2–5", restText: "3 min"),
                    Exercise(name: "Steep Wall Lock-Offs", repsText: "4–6 each side", setsText: "2–5", restText: "brief"),
                    Exercise(name: "Uneven-Grip Pull-Ups", repsText: "3–5 each side", setsText: "2–3", restText: "2 min"),
                    Exercise(name: "One-Arm Lock-Offs", repsText: "2–3", setsText: "2–3", restText: "2 min")
                ]

                let cpF = TrainingType(name: "Contact Strength & Power", area: "Fingers", typeDescription: "Contact strength and explosive recruitment.")
                cpF.exercises = [
                    Exercise(name: "One-Arm Lunging", repsText: "6–12 moves", setsText: "2–3", restText: "minimal"),
                    Exercise(name: "Campus Board Bumps", repsText: "2–4 sets each side", restText: "2 min"),
                    Exercise(name: "CB Laddering (no skips, small rungs)", repsText: "up only", setsText: "3–10", restText: "2–3 min"),
                    Exercise(name: "Campus Switch Hands", repsText: "12 switches", setsText: "2", restText: "2 min")
                ]

                let cpP = TrainingType(name: "Contact Strength & Power", area: "Pull", typeDescription: "Explosive pulling power.")
                cpP.exercises = [
                    Exercise(name: "Big-Move Boulder Problems", repsText: "6–10 moves", setsText: "5 sends", restText: "3 min"),
                    Exercise(name: "CB Laddering (larger rungs w/ skips)", repsText: "1–3–5–7", setsText: "3–10", restText: "3 min"),
                    Exercise(name: "Boulder Campusing", repsText: "3–8 moves", setsText: "3–5", restText: "3 min")
                ]

                let seF = TrainingType(name: "Strength-Endurance", area: "Fingers", typeDescription: "Capacity on edges with repeaters.")
                seF.exercises = [
                    Exercise(name: "Short-Duration Fingerboard Repeaters", repsText: "see protocol", setsText: "3–5"),
                    Exercise(name: "Long-Duration Fingerboard Repeaters", repsText: "see protocol", setsText: "3–5")
                ]

                let seP = TrainingType(name: "Strength-Endurance", area: "Pull", typeDescription: "SE for pulling patterns.")
                seP.exercises = [
                    Exercise(name: "Pull-Up Intervals", repsText: "see protocol", setsText: "10–20"),
                    Exercise(name: "Frenchies", repsText: "2–6 cycles", setsText: "2–4")
                ]

                climb.types = [maxF, maxP, cpF, cpP, seF, seP]

                // ========== BOULDERING with COMBINATIONS ==========
                let boulder = Activity(name: "Bouldering")

                let bMax = TrainingType(name: "Maximum & contact Strength", typeDescription: "Bouldering power / contact strength.")
                let comb1 = BoulderCombination(name: "Combination 1", comboDescription: "Near-max boulders + limit tries.")
                comb1.exercises = [
                    Exercise(name: "3–6 near‑maximal boulders", repsText: "30 min", restText: "3 min/send"),
                    Exercise(name: "Work on 1–3 limit boulders", repsText: "30 min")
                ]
                let comb2 = BoulderCombination(name: "Combination 2", comboDescription: "Big powerful moves / coordination / slab.")
                comb2.exercises = [
                    Exercise(name: "Big, powerful moves", repsText: "35–45° for 25 min", restText: "8 min to next"),
                    Exercise(name: "Footless problem on big holds", repsText: "20–45° for 15 min", restText: "8 min"),
                    Exercise(name: "Coordination / dyno", repsText: "vertical–30° for 20 min", restText: "8 min"),
                    Exercise(name: "Slabs", repsText: "vertical–30° for 20 min", restText: "8 min")
                ]
                let comb3 = BoulderCombination(name: "Combination 3", comboDescription: "V‑grade blocks with rest blocks.")
                comb3.exercises = [
                    Exercise(name: "3 problems V0–V2", restText: "1 min/send", notes: "rest block 3 min"),
                    Exercise(name: "3 problems V3–V4", restText: "3 min/send", notes: "rest block 6 min"),
                    Exercise(name: "3 problems V4–V5", restText: "3 min/send", notes: "rest block 6 min"),
                    Exercise(name: "3–5 problems V5–V6", restText: "5 min/send", notes: "rest block 6 min"),
                    Exercise(name: "3 problems V4–V5 (repeat)", restText: "3 min/send", notes: "rest block 6 min")
                ]
                let comb4 = BoulderCombination(name: "Combination 4", comboDescription: "Boards / limit work.")
                comb4.exercises = [
                    Exercise(name: "Moon/Kilter", repsText: "45 min", restText: "3 min/attempt"),
                    Exercise(name: "Work on 1–3 limit boulders", repsText: "30 min")
                ]
                bMax.combinations = [comb1, comb2, comb3, comb4]

                let bSE = TrainingType(name: "Strength-Endurance", typeDescription: "SE circuits for bouldering.")
                let combSE1 = BoulderCombination(name: "Combination 1")
                combSE1.exercises = [ Exercise(name: "Bouldering 4×4s", notes: "see protocol") ]
                let combSE2 = BoulderCombination(name: "Combination 2")
                combSE2.exercises = [ Exercise(name: "Big-holds, big-move 4×4s", notes: "see protocol") ]
                let combSE3 = BoulderCombination(name: "Combination 3", comboDescription: "Alternating V-grade blocks, no rest between sends, rest block 6 min.")
                combSE3.exercises = [
                    Exercise(name: "6 problems V0–V2", restText: "45 sec/send"),
                    Exercise(name: "3 problems V3–V4", repsText: "no rest between sends", notes: "rest block 6 min"),
                    Exercise(name: "3 problems V4–V5", repsText: "no rest between sends", notes: "rest block 6 min"),
                    Exercise(name: "3 problems V3–V4", repsText: "no rest between sends", notes: "rest block 6 min"),
                    Exercise(name: "3 problems V4–V5", repsText: "no rest between sends", notes: "rest block 6 min"),
                    Exercise(name: "3 problems V3–V4", repsText: "no rest between sends", notes: "rest block 6 min"),
                    Exercise(name: "3 problems V4–V5", repsText: "no rest between sends", notes: "rest block 6 min"),
                    Exercise(name: "3 problems V3–V4", repsText: "no rest between sends", notes: "rest block 6 min")
                ]
                let combSE4 = BoulderCombination(name: "Combination 4")
                combSE4.exercises = [ Exercise(name: "Tension board 3×6", notes: "see protocol") ]

                bSE.combinations = [combSE1, combSE2, combSE3, combSE4]

                boulder.types = [bMax, bSE]

                // Save all
                [core, ant, climb, boulder].forEach { context.insert($0) }
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
        try? context.save()
        // Seed fresh
        loadIfNeeded(context)
    }

        }



