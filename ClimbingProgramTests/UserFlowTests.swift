//
//  UserFlowTests.swift
//  ClimbingProgram Tests
//
//  Created by AI Assistant on 23.08.25.
//

import XCTest
import SwiftData
@testable import ClimbingProgram

/**
 * User Flow Tests
 *
 * Tests all documented user journeys and workflows from README.md:
 * - Exercise Selection Journey
 * - Workout Logging Journey
 * - Plan Management Journey
 */

class UserFlowTests: ClimbingProgramTestSuite {
    
    // MARK: - Exercise Selection Journey Tests
    // Start → Catalog Tab → Activity → TrainingType → Exercise → Add to Plan → PlanDay → Save & Complete
    
    func testExerciseSelectionFlow() {
        // 1. Create catalog structure
        let activity = Activity(name: "Core")
        context.insert(activity)
        
        let trainingType = TrainingType(name: "Anterior Core")
        activity.types.append(trainingType)
        
        let exercise = Exercise(name: "Plank", repsText: "60s", setsText: "3")
        trainingType.exercises.append(exercise)
        
        // 2. Create plan to add exercise to
        let plan = createTestPlan()
        let planDay = plan.days.first!
        
        // 3. Simulate user selecting exercise and adding to plan
        planDay.chosenExercises.append(exercise.name)
        
        try? context.save()
        
        // Verify the complete flow
        XCTAssertEqual(activity.types.count, 1)
        XCTAssertEqual(trainingType.exercises.count, 1)
        XCTAssertEqual(planDay.chosenExercises.count, 1)
        XCTAssertEqual(planDay.chosenExercises.first, "Plank")
    }
    
    func testBoulderCombinationSelectionFlow() {
        // Test selection of boulder combinations
        let activity = Activity(name: "Climbing")
        context.insert(activity)
        
        let trainingType = TrainingType(name: "Bouldering")
        activity.types.append(trainingType)
        
        let combo = BoulderCombination(name: "Power Circuit")
        trainingType.combinations.append(combo)
        
        let exercise1 = Exercise(name: "Campus Board", repsText: "5", setsText: "3")
        let exercise2 = Exercise(name: "Dyno Practice", repsText: "10", setsText: "2")
        combo.exercises.append(contentsOf: [exercise1, exercise2])
        
        let plan = createTestPlan()
        let planDay = plan.days.first!
        
        // User selects the combination
        combo.exercises.forEach { exercise in
            planDay.chosenExercises.append(exercise.name)
        }
        
        try? context.save()
        
        XCTAssertEqual(combo.exercises.count, 2)
        XCTAssertEqual(planDay.chosenExercises.count, 2)
        XCTAssertTrue(planDay.chosenExercises.contains("Campus Board"))
        XCTAssertTrue(planDay.chosenExercises.contains("Dyno Practice"))
    }
    
    // MARK: - Workout Logging Journey Tests
    // Start → Plans Tab → Select Plan → Select Day → View Exercises → [Quick Log/Detailed Log/Progress View]
    
    func testQuickLogFlow() {
        // Setup plan with exercises
        let plan = createTestPlan()
        let planDay = plan.days.first!
        planDay.chosenExercises.append("Push-ups")
        
        // Create session for today
        let session = Session(date: planDay.date)
        context.insert(session)
        
        // Simulate quick log (✓ button) - minimal data
        let quickLogItem = SessionItem(
            exerciseName: "Push-ups",
            planSourceId: plan.id,
            planName: plan.name,
            notes: "Quick logged"
        )
        
        session.items.append(quickLogItem)
        try? context.save()
        
        XCTAssertEqual(session.items.count, 1)
        XCTAssertEqual(quickLogItem.exerciseName, "Push-ups")
        XCTAssertEqual(quickLogItem.planSourceId, plan.id)
        XCTAssertEqual(quickLogItem.notes, "Quick logged")
        XCTAssertNil(quickLogItem.reps)
        XCTAssertNil(quickLogItem.sets)
    }
    
    func testDetailedLogFlow() {
        // Setup plan with exercises
        let plan = createTestPlan()
        let planDay = plan.days.first!
        planDay.chosenExercises.append("Pull-ups")
        
        // Create session
        let session = Session(date: planDay.date)
        context.insert(session)
        
        // Simulate detailed log (pencil button) - full metrics
        let detailedLogItem = SessionItem(
            exerciseName: "Pull-ups",
            planSourceId: plan.id,
            planName: plan.name,
            reps: 8,
            sets: 3,
            weightKg: 10.0,
            grade: "V4",
            notes: "Good form, felt strong"
        )
        
        session.items.append(detailedLogItem)
        try? context.save()
        
        XCTAssertEqual(detailedLogItem.reps, 8)
        XCTAssertEqual(detailedLogItem.sets, 3)
        XCTAssertEqual(detailedLogItem.weightKg, 10.0)
        XCTAssertEqual(detailedLogItem.grade, "V4")
        XCTAssertEqual(detailedLogItem.notes, "Good form, felt strong")
    }
    
    func testDirectLoggingFlow() {
        // Test logging without plans (Log tab direct entry)
        let session = createTestSession()
        
        let directLogItem = SessionItem(
            exerciseName: "Squats",
            reps: 15,
            sets: 4,
            weightKg: 50.0,
            notes: "Direct logged workout"
        )
        
        session.items.append(directLogItem)
        try? context.save()
        
        XCTAssertNil(directLogItem.planSourceId)
        XCTAssertNil(directLogItem.planName)
        XCTAssertEqual(directLogItem.exerciseName, "Squats")
    }
    
    // MARK: - Plan Management Journey Tests
    // Start → Plans Tab → Create/Select Plan → Configure Days → Add Exercises → Daily Execution → Log Completion → Track Progress
    
    func testPlanCreationFlow() {
        // Test different plan types
        let weeklyPlan = PlanFactory.create(name: "Weekly Training", kind: .weekly, start: Date(), in: context)
        let pyramidPlan = PlanFactory.create(name: "3-2-1 Plan", kind: .threeTwoOne, start: Date(), in: context)
        
        try? context.save()
        
        XCTAssertEqual(weeklyPlan.kind, .weekly)
        XCTAssertEqual(pyramidPlan.kind, .threeTwoOne)
        XCTAssertFalse(weeklyPlan.days.isEmpty)
        XCTAssertFalse(pyramidPlan.days.isEmpty)
        
        // Verify different plan structures
        XCTAssertEqual(weeklyPlan.days.count, 7) // 1 week
        XCTAssertTrue(pyramidPlan.days.count > 7) // Multi-week structure
    }
    
    func testPlanExecutionFlow() {
        let plan = createTestPlan()
        let planDay = plan.days.first!
        
        // 1. Configure day with exercises
        planDay.chosenExercises.append(contentsOf: ["Exercise 1", "Exercise 2", "Exercise 3"])
        planDay.type = .climbingFull
        
        // 2. Execute the plan (log exercises)
        let session = Session(date: planDay.date)
        context.insert(session)
        
        planDay.chosenExercises.forEach { exerciseName in
            let item = SessionItem(
                exerciseName: exerciseName,
                planSourceId: plan.id,
                planName: plan.name,
                reps: Double.random(in: 8...12),
                sets: 3
            )
            session.items.append(item)
        }
        
        try? context.save()
        
        XCTAssertEqual(planDay.chosenExercises.count, 3)
        XCTAssertEqual(session.items.count, 3)
        XCTAssertEqual(planDay.type, .climbingFull)
        
        // Verify all logged items are linked to the plan
        session.items.forEach { item in
            XCTAssertEqual(item.planSourceId, plan.id)
        }
    }
    
    func testProgressTrackingFlow() {
        // Create historical data for progress tracking
        let plan = createTestPlan()
        let exerciseName = "Bench Press"
        
        // Create multiple sessions over time
        let dates = [
            Calendar.current.date(byAdding: .day, value: -14, to: Date())!,
            Calendar.current.date(byAdding: .day, value: -7, to: Date())!,
            Date()
        ]
        
        let progressData: [(reps: Double, sets: Double, weight: Double)] = [
            (8, 3, 60.0),
            (10, 3, 65.0),
            (12, 3, 70.0)
        ]
        
        var sessions: [Session] = []
        for (index, date) in dates.enumerated() {
            let session = Session(date: date)
            context.insert(session)
            sessions.append(session)
            
            let data = progressData[index]
            let item = SessionItem(
                exerciseName: exerciseName,
                planSourceId: plan.id,
                planName: plan.name,
                reps: data.reps,
                sets: data.sets,
                weightKg: data.weight
            )
            
            session.items.append(item)
        }
        
        try? context.save()
        
        // Verify progress tracking data
        let descriptor = FetchDescriptor<SessionItem>(
            predicate: #Predicate<SessionItem> { $0.exerciseName == exerciseName }
        )
        
        let items = (try? context.fetch(descriptor)) ?? []
        XCTAssertEqual(items.count, 3)
        
        // Verify progression
        let sortedItems = items.sorted { item1, item2 in
            // Find the session for each item
            let session1 = sessions.first { $0.items.contains(where: { $0.id == item1.id }) }
            let session2 = sessions.first { $0.items.contains(where: { $0.id == item2.id }) }
            return (session1?.date ?? Date()) < (session2?.date ?? Date())
        }
        
        XCTAssertEqual(sortedItems[0].reps, 8)
        XCTAssertEqual(sortedItems[1].reps, 10)
        XCTAssertEqual(sortedItems[2].reps, 12)
        
        XCTAssertEqual(sortedItems[0].weightKg, 60.0)
        XCTAssertEqual(sortedItems[2].weightKg, 70.0)
    }
    
    // MARK: - Cross-Feature Integration Tests
    
    func testCatalogToPlanToLogIntegration() {
        // Full end-to-end test: Catalog → Plan → Log → Progress
        
        // 1. Create exercise in catalog
        let activity = Activity(name: "Strength")
        context.insert(activity)
        
        let trainingType = TrainingType(name: "Upper Body")
        activity.types.append(trainingType)
        
        let exercise = Exercise(name: "Pull-ups", repsText: "8-12", setsText: "3")
        trainingType.exercises.append(exercise)
        
        // 2. Add to plan
        let plan = createTestPlan()
        let planDay = plan.days.first!
        planDay.chosenExercises.append(exercise.name)
        
        // 3. Log execution
        let session = Session(date: planDay.date)
        context.insert(session)
        
        let logItem = SessionItem(
            exerciseName: exercise.name,
            planSourceId: plan.id,
            planName: plan.name,
            reps: 10,
            sets: 3
        )
        session.items.append(logItem)
        
        try? context.save()
        
        // Verify complete integration
        XCTAssertEqual(exercise.name, "Pull-ups")
        XCTAssertTrue(planDay.chosenExercises.contains(exercise.name))
        XCTAssertEqual(logItem.exerciseName, exercise.name)
        XCTAssertEqual(logItem.planSourceId, plan.id)
        
        // Verify data relationships are intact
        XCTAssertTrue(activity.types.contains(trainingType))
        XCTAssertTrue(trainingType.exercises.contains(exercise))
        XCTAssertTrue(session.items.contains(logItem))
    }
}
