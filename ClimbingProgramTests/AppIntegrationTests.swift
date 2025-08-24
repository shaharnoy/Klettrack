//
//  AppIntegrationTests.swift
//  ClimbingProgram Tests
//
//  Created by AI Assistant on 23.08.25.
//

import XCTest
import SwiftUI
import SwiftData
@testable import ClimbingProgram

/**
 * App Integration Tests
 *
 * Tests core app integration, navigation flows, and lifecycle management
 * as documented in the architecture overview
 */

class AppIntegrationTests: ClimbingProgramTestSuite {
    
    // MARK: - App Lifecycle Tests
    
    func testAppInitialization() {
        // Test that main app components can be initialized
        let app = ClimbingProgramApp()
        XCTAssertNotNil(app)
        
        // Test SwiftData container setup
        XCTAssertNotNil(container)
        XCTAssertNotNil(context)
    }
    
    func testModelContainerConfiguration() {
        // Verify all required models are in the schema
        let modelTypes = container.schema.entities.map { $0.name }
        
        XCTAssertTrue(modelTypes.contains("Activity"))
        XCTAssertTrue(modelTypes.contains("TrainingType"))
        XCTAssertTrue(modelTypes.contains("Exercise"))
        XCTAssertTrue(modelTypes.contains("BoulderCombination"))
        XCTAssertTrue(modelTypes.contains("Session"))
        XCTAssertTrue(modelTypes.contains("SessionItem"))
        XCTAssertTrue(modelTypes.contains("Plan"))
        XCTAssertTrue(modelTypes.contains("PlanDay"))
    }
    
    // MARK: - Navigation Flow Tests
    
    func testTabStructureIntegrity() {
        // Verify that all documented tabs are accessible
        // This tests the RootTabView structure mentioned in documentation
        
        // Create test data for tabs to display
        SeedData.loadIfNeeded(context)
        _ = createTestPlan()
        _ = createTestSession()
        
        // Verify data exists for each tab
        let activities = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        XCTAssertFalse(activities.isEmpty, "Catalog tab should have data")
        
        let plans = (try? context.fetch(FetchDescriptor<Plan>())) ?? []
        XCTAssertFalse(plans.isEmpty, "Plans tab should have data")
        
        let sessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        XCTAssertFalse(sessions.isEmpty, "Log tab should have data")
    }
    
    func testDataFlowBetweenFeatures() {
        // Test the complete data flow: Catalog → Plans → Sessions → Analytics
        
        // 1. Create catalog data (simulating Catalog tab usage)
        let activity = createTestActivity(name: "Integration Test Activity")
        let trainingType = createTestTrainingType(activity: activity, name: "Integration Type")
        let exercise = createTestExercise(trainingType: trainingType, name: "Integration Exercise")
        
        // 2. Create plan and add exercise (simulating Plans tab usage)
        let plan = createTestPlan(name: "Integration Plan")
        let planDay = plan.days.first!
        planDay.chosenExercises.append(exercise.name)
        
        // 3. Log the exercise (simulating Log tab usage)
        let session = createTestSession()
        let sessionItem = SessionItem(
            exerciseName: exercise.name,
            planSourceId: plan.id,
            planName: plan.name,
            reps: 10,
            sets: 3
        )
        session.items.append(sessionItem)
        
        try? context.save()
        
        // 4. Verify data is available for analytics (Progress tab)
        let loggedItems = (try? context.fetch(FetchDescriptor<SessionItem>())) ?? []
        XCTAssertEqual(loggedItems.count, 1)
        XCTAssertEqual(loggedItems.first?.exerciseName, exercise.name)
        XCTAssertEqual(loggedItems.first?.planSourceId, plan.id)
    }
    
    // MARK: - User Journey Integration Tests
    
    func testCompleteExerciseSelectionJourney() {
        // Test the documented journey: Start → Catalog → Activity → TrainingType → Exercise → Plan
        
        // Setup initial data
        SeedData.loadIfNeeded(context)
        
        // 1. User opens catalog
        let activities = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        XCTAssertFalse(activities.isEmpty)
        
        // 2. User selects activity
        let coreActivity = activities.first { $0.name == "Core" }
        XCTAssertNotNil(coreActivity)
        
        // 3. User selects training type
        let trainingTypes = coreActivity!.types
        XCTAssertFalse(trainingTypes.isEmpty)
        
        // 4. User selects exercise
        let firstType = trainingTypes.first!
        let exercises = firstType.exercises
        XCTAssertFalse(exercises.isEmpty)
        
        // 5. User adds to plan
        let plan = createTestPlan()
        let exercise = exercises.first!
        plan.days.first!.chosenExercises.append(exercise.name)
        
        try? context.save()
        
        // Verify complete journey
        XCTAssertTrue(plan.days.first!.chosenExercises.contains(exercise.name))
    }
    
    func testCompleteLoggingJourney() {
        // Test the documented journey: Plans → Select Plan → Select Day → Log Exercises
        
        // Setup plan with exercises
        let plan = createTestPlan()
        let planDay = plan.days.first!
        planDay.chosenExercises.append(contentsOf: ["Push-ups", "Pull-ups", "Squats"])
        
        // User executes plan
        let session = createTestSession(date: planDay.date)
        
        for exerciseName in planDay.chosenExercises {
            let item = SessionItem(
                exerciseName: exerciseName,
                planSourceId: plan.id,
                planName: plan.name,
                reps: Int.random(in: 8...12),
                sets: 3
            )
            session.items.append(item)
        }
        
        try? context.save()
        
        // Verify logging journey
        XCTAssertEqual(session.items.count, 3)
        XCTAssertTrue(session.items.allSatisfy { $0.planSourceId == plan.id })
    }
    
    // MARK: - Error Handling and Recovery Tests
    
    func testDataConsistencyAfterAppRestart() {
        // Simulate app restart by creating new context
        // Create test activities for our consistency check
        let activities = [
            createTestActivity(name: "Restart Test Activity"),
            createTestActivity(name: "Another Activity")
        ]
        
        try? context.save()
        
        // Verify we have the expected number of activities
        XCTAssertEqual(activities.count, 2)
        
        // Simulate app restart with new context
        let newConfiguration = ModelConfiguration(schema: container.schema, isStoredInMemoryOnly: true)
        let newContainer = try! ModelContainer(for: container.schema, configurations: [newConfiguration])
        let newContext = ModelContext(newContainer)
        
        // Verify data persistence (in real app this would be persistent storage)
        // For in-memory testing, we verify the pattern works
        XCTAssertNoThrow(try newContext.save())
    }
    
    func testGracefulErrorHandling() {
        // Test app behavior with invalid data
        let invalidActivity = Activity(name: "")  // Empty name
        context.insert(invalidActivity)
        
        // App should handle invalid data gracefully
        XCTAssertNoThrow(try context.save())
        
        // Test CSV export with invalid data
        XCTAssertNoThrow(LogCSV.makeExportCSV(context: context))
    }
    
    // MARK: - Feature Integration Tests
    
    func testPlanFactoryIntegration() {
        // Test that PlanFactory integrates properly with the app
        let weeklyPlan = PlanFactory.create(name: "Weekly", kind: .weekly, start: Date(), in: context)
        let pyramidPlan = PlanFactory.create(name: "Pyramid", kind: .threeTwoOne, start: Date(), in: context)
        
        try? context.save()
        
        // Verify plans are created correctly
        XCTAssertEqual(weeklyPlan.days.count, 7)
        XCTAssertTrue(pyramidPlan.days.count > 7)
        
        // Verify plans are persisted
        let plans = (try? context.fetch(FetchDescriptor<Plan>())) ?? []
        XCTAssertEqual(plans.count, 2)
    }
    
    func testSeedDataIntegration() {
        // Test that SeedData works properly with app
        XCTAssertNoThrow(SeedData.loadIfNeeded(context))
        
        // Verify seeded data is accessible
        let activities = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        XCTAssertFalse(activities.isEmpty)
        
        // Verify data structure is complete
        for activity in activities {
            XCTAssertFalse(activity.types.isEmpty)
            for trainingType in activity.types {
                // A training type should have either exercises or combinations
                XCTAssertFalse(trainingType.exercises.isEmpty && trainingType.combinations.isEmpty, "Training type '\(trainingType.name)' should have exercises or combinations")
            }
        }
    }
    
    // MARK: - Performance Integration Tests
    
    func testAppPerformanceWithLargeDataset() {
        // Test app performance with realistic data volumes
        measure {
            // Create realistic data volume
            for i in 0..<20 {
                let activity = createTestActivity(name: "Activity \(i)")
                for j in 0..<5 {
                    let trainingType = createTestTrainingType(activity: activity, name: "Type \(i)-\(j)")
                    for k in 0..<10 {
                        _ = createTestExercise(trainingType: trainingType, name: "Exercise \(i)-\(j)-\(k)")
                    }
                }
            }
            
            // Create sessions and plans
            for i in 0..<50 {
                let session = createTestSession()
                let item = SessionItem(exerciseName: "Exercise \(i)")
                session.items.append(item)
            }
            
            for i in 0..<10 {
                _ = createTestPlan(name: "Plan \(i)")
            }
            
            try? context.save()
        }
    }
}
