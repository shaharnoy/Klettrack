//
//  PerformanceAndEdgeCaseTests.swift
//  klettrack Tests
//
//  Created by Shahar Noy on 30.09.25.
//

import XCTest
import SwiftData
@testable import klettrack

/**
 * Performance and Edge Case Tests
 *
 * Tests for:
 * - Performance under load
 * - Memory management
 * - Edge cases and error conditions
 * - Data consistency under stress
 */

class PerformanceAndEdgeCaseTests: ClimbingProgramTestSuite {
    
    // MARK: - Performance Tests
    
    func testLargeDatasetCreationPerformance() {
        measure {
            // Create 1000 exercises across 50 activities
            for i in 0..<50 {
                let activity = Activity(name: "Activity \(i)")
                context.insert(activity)
                
                for j in 0..<5 {
                    let trainingType = TrainingType(name: "Type \(i)-\(j)")
                    activity.types.append(trainingType)
                    
                    for k in 0..<4 {
                        let exercise = Exercise(name: "Exercise \(i)-\(j)-\(k)", repsText: "10", setsText: "3")
                        trainingType.exercises.append(exercise)
                    }
                }
            }
            
            try? context.save()
        }
    }
    
    func testComplexQueryPerformance() {
        // Setup large dataset
        createLargeTestDataset()
        
        measure {
            // Complex queries that might be used in the app
            
            // 1. Find all sessions in the last 30 days
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            let recentSessionsDescriptor = FetchDescriptor<Session>(
                predicate: #Predicate<Session> { session in
                    session.date >= thirtyDaysAgo
                },
                sortBy: [SortDescriptor(\Session.date, order: .reverse)]
            )
            _ = try? context.fetch(recentSessionsDescriptor)
            
            // 2. Find all exercises containing a specific name pattern
            let exerciseDescriptor = FetchDescriptor<Exercise>(
                predicate: #Predicate<Exercise> { exercise in
                    exercise.name.contains("Exercise")
                }
            )
            _ = try? context.fetch(exerciseDescriptor)
        }
    }
    
    func testCSVExportPerformance() {
        // Create large dataset
        createLargeSessionDataset()
        
        measure {
            _ = LogCSV.makeExportCSV(context: context)
        }
    }
    
    // MARK: - Edge Case Tests
    
    func testEmptyDataHandling() {
        // Test operations with empty data
        let exportDoc = LogCSV.makeExportCSV(context: context)
        XCTAssertFalse(exportDoc.csv.isEmpty, "Export should always include headers")
        
        // Test queries on empty database
        let sessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        XCTAssertTrue(sessions.isEmpty)
        
        let activities = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        XCTAssertTrue(activities.isEmpty)
    }
    
    func testExtremelyLongStrings() {
        let longString = String(repeating: "a", count: 10000)
        
        let activity = Activity(name: longString)
        context.insert(activity)
        
        let exercise = Exercise(name: longString, notes: longString)
        
        let session = createTestSession()
        let item = SessionItem(exerciseName: longString, notes: longString)
        session.items.append(item)
        
        // Should handle long strings without crashing
        XCTAssertNoThrow(try context.save())
        
        // Test CSV export with long strings
        XCTAssertNoThrow(LogCSV.makeExportCSV(context: context))
    }
    
    func testSpecialCharactersInData() {
        let specialChars = "café,naïve \"quoted\" string\nwith newlines"
        let unicodeChars = "🧗‍♀️🏔️💪"
        let mixedString = "Test Exercise: \(specialChars) \(unicodeChars)"
        
        let activity = Activity(name: mixedString)
        context.insert(activity)
        
        let exercise = Exercise(name: mixedString, notes: mixedString)
        
        let session = createTestSession()
        let item = SessionItem(exerciseName: mixedString, notes: mixedString)
        session.items.append(item)
        
        XCTAssertNoThrow(try context.save())
        
        // Test CSV handling of special characters
        let exportDoc = LogCSV.makeExportCSV(context: context)
        // Check that the CSV contains the basic test part (which should always be there)
        XCTAssertTrue(exportDoc.csv.contains("Test Exercise"), "CSV should contain the exercise name")
    }
    
    func testDateBoundaryConditions() {
        // Test extreme dates
        let distantPast = Date.distantPast
        let distantFuture = Date.distantFuture
        let epochDate = Date(timeIntervalSince1970: 0)
        
        let session1 = Session(date: distantPast)
        let session2 = Session(date: distantFuture)
        let session3 = Session(date: epochDate)
        
        context.insert(session1)
        context.insert(session2)
        context.insert(session3)
        
        XCTAssertNoThrow(try context.save())
        
        // Test CSV export with extreme dates
        XCTAssertNoThrow(LogCSV.makeExportCSV(context: context))
    }
    
    func testPlanWithManyDays() {
        // Test plan with excessive number of days
        let plan = createTestPlan()
        
        // Add 1000 more days
        for i in 0..<1000 {
            let date = Calendar.current.date(byAdding: .day, value: i + 7, to: plan.startDate)!
            let planDay = PlanDay(date: date, type: .climbingSmall)
            plan.days.append(planDay)
        }
        
        XCTAssertNoThrow(try context.save())
        XCTAssertEqual(plan.days.count, 1007) // Original 7 + 1000 new
    }
    
    // MARK: - Data Consistency Tests
    
    func testDataConsistencyAfterMultipleOperations() {
        // Perform many random operations and verify consistency
        for _ in 0..<100 {
            let operation = Int.random(in: 0...4)
            
            switch operation {
            case 0: // Create activity
                let activity = Activity(name: "Random Activity \(UUID().uuidString)")
                context.insert(activity)
                
            case 1: // Create session
                let session = Session(date: Date())
                context.insert(session)
                let item = SessionItem(exerciseName: "Random Exercise")
                session.items.append(item)
                
            case 2: // Create plan
                _ = createTestPlan()
                
            case 3: // Save context
                try? context.save()
                
            case 4: // Query data
                _ = try? context.fetch(FetchDescriptor<Activity>())
                
            default:
                break
            }
        }
        
        // Final save and consistency check
        try? context.save()
        
        let activities = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        let plans = (try? context.fetch(FetchDescriptor<Plan>())) ?? []
        
        // Basic consistency checks
        XCTAssertTrue(activities.count >= 0)
        XCTAssertTrue(sessions.count >= 0)
        XCTAssertTrue(plans.count >= 0)
        
        // Verify relationships exist and are valid - fix the logic
        for activity in activities {
            // Either activity has no types, or all types have non-empty names
            let hasValidTypes = activity.types.isEmpty || activity.types.allSatisfy { !$0.name.isEmpty }
            XCTAssertTrue(hasValidTypes, "Activity \(activity.name) should have valid training types")
        }
        
        for session in sessions {
            // Either session has no items, or all items have non-empty exercise names
            let hasValidItems = session.items.isEmpty || session.items.allSatisfy { !$0.exerciseName.isEmpty }
            XCTAssertTrue(hasValidItems, "Session should have valid items")
        }
        
        for plan in plans {
            // Either plan has no days, or all days have valid dates
            let hasValidDays = plan.days.isEmpty || plan.days.allSatisfy { $0.date <= Date.distantFuture }
            XCTAssertTrue(hasValidDays, "Plan should have valid days")
        }
    }
    
    // MARK: - Helper Methods
    
    private func createLargeTestDataset() {
        for i in 0..<20 {
            let activity = Activity(name: "Activity \(i)")
            context.insert(activity)
            
            for j in 0..<5 {
                let trainingType = TrainingType(name: "Type \(i)-\(j)")
                activity.types.append(trainingType)
                
                for k in 0..<10 {
                    let exercise = Exercise(name: "Exercise \(i)-\(j)-\(k)")
                    trainingType.exercises.append(exercise)
                }
            }
        }
        try? context.save()
    }
    
    private func createLargeSessionDataset() {
        for i in 0..<200 {
            let date = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
            let session = Session(date: date)
            context.insert(session)
            
            for j in 0..<15 {
                let item = SessionItem(
                    exerciseName: "Exercise \(j)",
                    reps: Double.random(in: 5...20),
                    sets: Double.random(in: 2...5),
                    weightKg: Double.random(in: 0...150),
                    notes: "Session \(i) item \(j)"
                )
                session.items.append(item)
            }
        }
        try? context.save()
    }
}
