//
//  SeedData.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//

import SwiftData

struct SeedData {
    static func loadIfNeeded(_ context: ModelContext) {
        let count = try? context.fetch(FetchDescriptor<Activity>()).count
        guard (count ?? 0) == 0 else { return } // already seeded
        
        // Activity: Core
        let core = Activity(name: "Core")
        let anterior = TrainingType(name: "Anterior Core")
        anterior.exercises = [
            Exercise(name: "Abdominal Crunches", repsText: "25 - 100", setsText: "2"),
            Exercise(name: "Hanging Knee Lifts", repsText: "15 - 20", setsText: "1 - 3"),
            Exercise(name: "1-Arm 1-Leg Plank", repsText: "20 - 60 sec.", setsText: "1 - 2"),
            Exercise(name: "1-Arm Elbow & Side Plank", repsText: "10 - 25", setsText: "1 - 2"),
            Exercise(name: "Front Lever", repsText: "2 - 5", setsText: "2 - 3"),
        ]
        let posterior = TrainingType(name: "Posterior Core")
        posterior.exercises = [
            Exercise(name: "Superman", repsText: "20 - 25", setsText: "2"),
            Exercise(name: "Reverse Plank", repsText: "20 - 60 sec.", setsText: "2 - 3"),
            Exercise(name: "Back Bridge", repsText: "15 - 20", setsText: "1 - 2"),
            Exercise(name: "Side Hip Raises", repsText: "10 - 20", setsText: "2"),
        ]
        let totalChain = TrainingType(name: "Total/Posterior Chain")
        totalChain.exercises = [
            Exercise(name: "Sumo Deadlift", repsText: "10 - 15", setsText: "2"),
            Exercise(name: "Dumbbell Snatch", repsText: "5 - 8", setsText: "2 - 3"),
            Exercise(name: "Barbell Deadlift", repsText: "3 - 6", setsText: "2 - 4"),
        ]
        core.types = [anterior, posterior, totalChain]
        
        // Activity: Antagonist & Stabilizer
        let antago = Activity(name: "Antagonist & Stabilizer")
        let wristForearm = TrainingType(name: "Wrist & Forearm Stabilizers")
        wristForearm.exercises = [
            Exercise(name: "Band Finger Extension", repsText: "15 - 25", setsText: "1 - 2"),
            Exercise(name: "Reverse Wrist Curls", repsText: "15 - 25", setsText: "2 - 3"),
            Exercise(name: "Pronator isolation", repsText: "20 - 25", setsText: "2"),
            Exercise(name: "Reverse Arm Curl", repsText: "15 - 20", setsText: "1 - 2"),
            Exercise(name: "Wrist Extension Isometric", repsText: "45 - 90 sec.", setsText: "2"),
            Exercise(name: "Wide Pinch w/ Wrist Ext.", repsText: "10 - 20 sec.", setsText: "3 - 5"),
        ]
        let rotator = TrainingType(name: "Rotator Cuff & Scap Stabilizers")
        rotator.exercises = [
            Exercise(name: "DB Internal Rotation", repsText: "20 - 25", setsText: "2"),
            Exercise(name: "DB External Rotation", repsText: "20 - 25", setsText: "2"),
            Exercise(name: "Band T", repsText: "10 - 20", setsText: "2"),
            Exercise(name: "Band Y", repsText: "10 - 20", setsText: "2"),
            Exercise(name: "Scapular Push-Up", repsText: "15 - 20", setsText: "2"),
            Exercise(name: "Scapular Pull-Up", repsText: "6 - 12", setsText: "2"),
        ]
        let antagonists = TrainingType(name: "Antagonist Push Muscles")
        antagonists.exercises = [
            Exercise(name: "Shoulder Press", repsText: "15 - 20", setsText: "1 - 2"),
            Exercise(name: "Push-Up", repsText: "15 - 25", setsText: "1 - 2"),
        ]
        antago.types = [wristForearm, rotator, antagonists]
        
        // Activity: Climbing-Specific (split by areas/types you gave)
        let climb = Activity(name: "Climbing-Specific Exercises")
        
        // Maximum & Contact Strength – Fingers
        let maxContactFingers = TrainingType(name: "Maximum & Contact Strength — Fingers", area: "Fingers")
        maxContactFingers.exercises = [
            Exercise(name: "Bouldering", repsText: "3 ascents", setsText: "3–10 problems", restText: "2 min/asc"),
            Exercise(name: "FB “Minimum Edge” Hangs", repsText: "see protocol", setsText: "2 - 5", notes: "smallest possible for 12 sec"),
            Exercise(name: "FB Max-Weight Hangs 10s (14–20mm)", repsText: "see protocol", setsText: "2 - 5"),
            Exercise(name: "FB Max-Weight Hangs 7/53 (14–20mm)", repsText: "see protocol", setsText: "2 - 5"),
            Exercise(name: "Loading pin lifts - repetitions", repsText: "1:50% 2:60% 3:70% 4–7:80%", setsText: "1–3: 8 reps; 4–7: 4 reps"),
        ]
        
        // Maximum & Contact Strength – Pull Muscle
        let maxContactPull = TrainingType(name: "Maximum & Contact Strength — Pull Muscle", area: "Pull")
        maxContactPull.exercises = [
            Exercise(name: "Weighted Pull-Ups", repsText: "5", setsText: "3 - 6", restText: "3 min rest"),
            Exercise(name: "Square Pull-Ups", repsText: "3 - 6", setsText: "1 - 2", restText: "3 min rest"),
            Exercise(name: "System Wall “Isolation”", repsText: "3 - 5 each side", setsText: "2 - 5", restText: "3 min rest"),
            Exercise(name: "Steep Wall “Lock-Offs”", repsText: "4 - 6 each side", setsText: "2 - 5", restText: "brief rest"),
            Exercise(name: "Uneven-Grip Pull-Ups", repsText: "3 - 5 each side", setsText: "2 - 3", restText: "2 min rest"),
            Exercise(name: "One-Arm Lock-Offs", repsText: "2 - 3", setsText: "2 - 3", restText: "2 min rest"),
        ]
        
        // Contact Strength & Power – Fingers
        let contactPowerFingers = TrainingType(name: "Contact Strength & Power — Fingers", area: "Fingers")
        contactPowerFingers.exercises = [
            Exercise(name: "One-Arm Lunging", repsText: "6 - 12 moves", setsText: "2 - 3", restText: "minimal rest"),
            Exercise(name: "Campus Board “Bumps”", repsText: "2 - 4 sets each side", restText: "2 min rest"),
            Exercise(name: "CB Laddering (no skips, small rungs)", repsText: "up only", setsText: "3 - 10", restText: "2–3 min rest"),
            Exercise(name: "Campus Switch hands", repsText: "12 switches", setsText: "2", restText: "2 min rest"),
        ]
        
        // Contact Strength & Power – Pull
        let contactPowerPull = TrainingType(name: "Contact Strength & Power — Pull", area: "Pull")
        contactPowerPull.exercises = [
            Exercise(name: "Big-Move Boulder Problems", repsText: "6 - 10 moves", setsText: "5 sends", restText: "3 min rest"),
            Exercise(name: "CB Laddering (larger rungs w/ skips)", repsText: "1-3-5-7", setsText: "3 - 10", restText: "3 min rest"),
            Exercise(name: "Boulder Campusing", repsText: "3 - 8 moves", setsText: "3 - 5", restText: "3 min rest"),
        ]
        
        // Strength-Endurance – Fingers
        let seFingers = TrainingType(name: "Strength-Endurance — Fingers", area: "Fingers")
        seFingers.exercises = [
            Exercise(name: "Short-Duration Fingerboard Repeaters", repsText: "see protocol", setsText: "3 - 5"),
            Exercise(name: "Long-Duration Fingerboard Repeaters", repsText: "see protocol", setsText: "3 - 5"),
        ]
        
        // Strength-Endurance – Pull
        let sePull = TrainingType(name: "Strength-Endurance — Pull", area: "Pull")
        sePull.exercises = [
            Exercise(name: "Pull-Up Intervals", repsText: "see protocol", setsText: "10 - 20"),
            Exercise(name: "Frenchies", repsText: "2 - 6 cycles", setsText: "2 - 4"),
        ]
        
        
        climb.types = [maxContactFingers, maxContactPull, contactPowerFingers, contactPowerPull, seFingers, sePull]
        
        // Activity: Climbing-Specific (split by areas/types you gave)
        let actbouldering = Activity(name: "Bouldering")
        // Strength-Endurance — Bouldering
        let seBouldering = TrainingType(name: "Strength-Endurance — Bouldering")
        seBouldering.exercises = [
            Exercise(name: "Bouldering 4x4s", notes: "see protocol"),
            Exercise(name: "Big-Holds, Big-Move 4x4s", notes: "see protocol"),
            Exercise(name: "Combo 3 variants (v0–v5)", notes: "as per your sets/rest blocks"),
            Exercise(name: "Combo 4: Tension board 3x6", notes: "see protocol"),
        ]
        // Bouldering — Multiple combinations
        let bouldering = TrainingType(name: "Bouldering — Combinations")
        bouldering.exercises = [
            Exercise(name: "Combo 1: 3–6 near-max boulders", repsText: "30 min", restText: "3 min/send"),
            Exercise(name: "Work on 1–3 limit boulders", repsText: "30 min"),
            Exercise(name: "Combo 2: Big powerful moves", repsText: "35–45° for 25 min", restText: "8 min to next combo"),
            Exercise(name: "Footless problem on big holds", repsText: "20–45° for 15 min", restText: "8 min"),
            Exercise(name: "Coordination / dyno", repsText: "vertical–30° for 20 min", restText: "8 min"),
            Exercise(name: "Slabs", repsText: "vertical–30° for 20 min", restText: "8 min"),
            Exercise(name: "Combo 3: V-grade blocks", notes: "Follow your listed V-grade blocks with rests"),
            Exercise(name: "Combo 4: Moon/Kilter", repsText: "45 min", restText: "3 min/attempt"),
            Exercise(name: "Work on 1–3 limit boulders", repsText: "30 min"),
        ]
        actbouldering.types = [ seBouldering,bouldering]
        
        // Save all
        [core, antago, climb, actbouldering].forEach { context.insert($0) }
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
