//
//  SeedTimerTemplates.swift
//  ClimbingProgram
//
//  Created by AI Assistant on 26.08.25.
//

import SwiftData

struct SeedTimerTemplates {
    
    static func loadIfNeeded(_ context: ModelContext) {
        // Check if timer templates already exist
        let count = (try? context.fetchCount(FetchDescriptor<TimerTemplate>())) ?? 0
        guard count == 0 else { return } // Only seed if no templates exist
        
        // Create the "Daily Basic" template
        let dailyBasic = TimerTemplate(
            name: "Daily Basic",
            templateDescription: "Basic daily training session with 1 minute work and 30 second rest",
            totalTimeSeconds: nil,
            isRepeating: false,
            repeatCount: nil,
            restTimeBetweenIntervals: nil
        )
        
        let basicInterval = TimerInterval(
            name: "Basic Interval",
            workTimeSeconds: 60,     // 1 minute work
            restTimeSeconds: 30,     // 30 seconds rest
            repetitions: 5,          // 5 repetitions
            order: 0
        )
        dailyBasic.intervals.append(basicInterval)
        
        // Create the 3mins rest template
        let threerest = TimerTemplate(
            name: "3mins Rest",
            templateDescription: "Just rest for 3 mins",
            totalTimeSeconds: 180,
            isRepeating: false,
            repeatCount: nil,
            restTimeBetweenIntervals: nil
        )
        
        // Create "One-Arm, One-Leg" template
        let oneArmOneLeg = TimerTemplate(
            name: "One-Arm, One-Leg",
            templateDescription: "Single set endurance hold with 3 minute rest",
            totalTimeSeconds: nil,
            isRepeating: true,
            repeatCount: 2,
            restTimeBetweenIntervals: 180 // 3 mins rest between sets
        )
        
        let oneArmInterval = TimerInterval(
            name: "One-Arm Hold",
            workTimeSeconds: 60,     // 1 min work
            restTimeSeconds: 0,      // no rest
            repetitions: 1,          // 1 repeat
            order: 0
        )
        oneArmOneLeg.intervals.append(oneArmInterval)
        
        // Create "Minimum Edge FB" template
        let minEdgeFB = TimerTemplate(
            name: "Minimum Edge FB",
            templateDescription: "Minimum edge fingerboard protocol - 12s hangs with 3min rest, 5 sets",
            totalTimeSeconds: nil,
            isRepeating: true,
            repeatCount: 5,          // 5 sets
            restTimeBetweenIntervals: 300 // 5 mins rest between sets
        )
        
        let minEdgeInterval = TimerInterval(
            name: "Min Edge Set",
            workTimeSeconds: 12,     // 12 seconds work
            restTimeSeconds: 180,    // 3 mins rest
            repetitions: 5,          // 5 repeats per set
            order: 0
        )
        minEdgeFB.intervals.append(minEdgeInterval)
        
        // Create "Max-Weight 10 seconds protocol" template
        let maxWeight10 = TimerTemplate(
            name: "Max-Weight 10 seconds protocal",
            templateDescription: "Maximum weight protocol - 10s hangs with 3min rest, 5 sets",
            totalTimeSeconds: nil,
            isRepeating: true,
            repeatCount: 5,          // 5 sets
            restTimeBetweenIntervals: 300 // 5 mins rest between sets
        )
        
        let maxWeight10Interval = TimerInterval(
            name: "Max Weight Set",
            workTimeSeconds: 10,     // 10 seconds work
            restTimeSeconds: 180,    // 3 mins rest
            repetitions: 5,          // 5 repeats per set
            order: 0
        )
        maxWeight10.intervals.append(maxWeight10Interval)
        
        // Create "Max-Weight 7-53 protocol" template
        let maxWeight753 = TimerTemplate(
            name: "Max-Weight 7-53  protocal",
            templateDescription: "Maximum weight protocol - 7s work, 53s rest, 5 sets",
            totalTimeSeconds: nil,
            isRepeating: true,
            repeatCount: 5,          // 5 sets
            restTimeBetweenIntervals: 300 // 5 mins rest between sets
        )
        
        let maxWeight753Interval = TimerInterval(
            name: "7-53 Set",
            workTimeSeconds: 7,      // 7 seconds work
            restTimeSeconds: 53,     // 53 seconds rest
            repetitions: 3,          // 3 repeats per set
            order: 0
        )
        maxWeight753.intervals.append(maxWeight753Interval)
        
        // Create "Short duration repeaters (Level 2)" template
        let shortRepeaters = TimerTemplate(
            name: "Short duration repeaters (Level 2)",
            templateDescription: "Level 2 repeaters - 10s work, 20s rest, 5 sets",
            totalTimeSeconds: nil,
            isRepeating: true,
            repeatCount: 5,          // 5 sets
            restTimeBetweenIntervals: 60 // 1 min rest between sets
        )
        
        let shortRepeatersInterval = TimerInterval(
            name: "Short Repeater Set",
            workTimeSeconds: 10,     // 10 seconds work
            restTimeSeconds: 20,     // 20 seconds rest
            repetitions: 6,          // 6 repeats per set
            order: 0
        )
        shortRepeaters.intervals.append(shortRepeatersInterval)
        
        // Create "Long duration repeaters (Level 1)" template
        let longRepeaters = TimerTemplate(
            name: "Long duration repeaters (Level 1)",
            templateDescription: "Level 1 repeaters - 30s work, 30s rest, 5 sets",
            totalTimeSeconds: nil,
            isRepeating: true,
            repeatCount: 5,          // 5 sets
            restTimeBetweenIntervals: 60 // 1 min rest between sets
        )
        
        let longRepeatersInterval = TimerInterval(
            name: "Long Repeater Set",
            workTimeSeconds: 30,     // 30 seconds work
            restTimeSeconds: 30,     // 30 seconds rest
            repetitions: 4,          // 4 repeats per set
            order: 0
        )
        longRepeaters.intervals.append(longRepeatersInterval)
        
        // Create "Bouldering 4x4" template
        let bouldering4x4 = TimerTemplate(
            name: "Bouldering 4x4",
            templateDescription: "4x4 bouldering protocol - 30s work, 30s rest, 4 sets",
            totalTimeSeconds: nil,
            isRepeating: true,
            repeatCount: 4,          // 4 sets
            restTimeBetweenIntervals: 240 // 4 mins rest between sets
        )
        
        let bouldering4x4Interval = TimerInterval(
            name: "Boulder Set",
            workTimeSeconds: 30,     // 30 seconds work
            restTimeSeconds: 30,     // 30 seconds rest
            repetitions: 4,          // 4 repeats per set
            order: 0
        )
        bouldering4x4.intervals.append(bouldering4x4Interval)
        
        // Create "Pull-Up Interval" template
        let pullUpInterval = TimerTemplate(
            name: "Pull-Up Interval",
            templateDescription: "Pull-up interval training - 15s work, 45s rest",
            totalTimeSeconds: nil,
            isRepeating: false,
            repeatCount: nil,
            restTimeBetweenIntervals: nil // No rest between sets
        )
        
        let pullUpInt = TimerInterval(
            name: "Pull-Up Interval",
            workTimeSeconds: 15,     // 15 seconds work
            restTimeSeconds: 45,     // 45 seconds rest
            repetitions: 20,         // 20 repeats
            order: 0
        )
        pullUpInterval.intervals.append(pullUpInt)
        
        // Create Wide pinch wrist extension template
        let wpwextention = TimerTemplate(
            name: "Wide Pinch Wrist",
            templateDescription: "Wrist extension with wide pinch grip",
            totalTimeSeconds: nil,
            isRepeating: true,
            repeatCount: 5,
            restTimeBetweenIntervals: 90 // 90 seconds
        )
        
        let wpwextentionint = TimerInterval(
            name: "Wide Pinch Wrist interval",
            workTimeSeconds: 30,     // 30 seconds work
            restTimeSeconds: 5,     // 5 seconds to switch hands
            repetitions: 2,         // 20 repeats
            order: 0
        )
        wpwextention.intervals.append(wpwextentionint)
        
        // Insert all templates and intervals into the context
        let templates = [dailyBasic,threerest, oneArmOneLeg, minEdgeFB, maxWeight10, maxWeight753,
                        shortRepeaters,wpwextention ,longRepeaters, bouldering4x4, pullUpInterval]
        
        for template in templates {
            context.insert(template)
            for interval in template.intervals {
                context.insert(interval)
            }
        }
        
        // Save the context
        try? context.save()
    }
    
    static func nukeAndReseed(_ context: ModelContext) {
        // Delete all timer templates and intervals
        try? context.delete(model: TimerTemplate.self)
        try? context.delete(model: TimerInterval.self)
        try? context.delete(model: TimerSession.self)
        try? context.save()
        
        // Seed fresh templates
        loadIfNeeded(context)
    }
}
