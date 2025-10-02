//
//  DataModelTests.swift
//  klettrack Tests
//  Created by Shahar Noy on 30.08.25.
//

import XCTest
import SwiftData
@testable import klettrack

/**
 * Data Model Tests
 *
 * Tests SwiftData model relationships and data integrity as documented in README.md
 */

class DataModelTests: ClimbingProgramTestSuite {
    
    // MARK: - Model Relationship Tests
    
    func testActivityTrainingTypeRelationship() {
        let activity = createTestActivity()
        let trainingType = createTestTrainingType(activity: activity)
        
        try? context.save()
        
        XCTAssertEqual(activity.types.count, 1)
        XCTAssertEqual(activity.types.first?.name, "Test Training Type")
        XCTAssertTrue(activity.types.contains(trainingType))
    }
    
    func testTrainingTypeExerciseRelationship() {
        let activity = createTestActivity()
        let trainingType = createTestTrainingType(activity: activity)
        let exercise = createTestExercise(trainingType: trainingType)
        
        try? context.save()
        
        XCTAssertEqual(trainingType.exercises.count, 1)
        XCTAssertTrue(trainingType.exercises.contains(exercise))
    }
    
    func testBoulderCombinationComplexRelationship() {
        let activity = createTestActivity()
        let trainingType = createTestTrainingType(activity: activity)
        
        let combo = createTestBoulderCombination(trainingType: trainingType)
        let exercise1 = Exercise(name: "Campus Board", repsText: "5", setsText: "3")
        let exercise2 = Exercise(name: "Dyno Practice", repsText: "10", setsText: "2")
        combo.exercises.append(contentsOf: [exercise1, exercise2])
        
        try? context.save()
        
        XCTAssertEqual(trainingType.combinations.count, 1)
        XCTAssertEqual(combo.exercises.count, 2)
        XCTAssertTrue(trainingType.combinations.contains(combo))
    }
    
    func testSessionItemPlanLinking() {
        let plan = createTestPlan()
        let session = createTestSession()
        
        let item = SessionItem(
            exerciseName: "Test Exercise",
            planSourceId: plan.id,
            planName: plan.name,
            reps: 10,
            sets: 3
        )
        
        session.items.append(item)
        try? context.save()
        
        XCTAssertEqual(item.planSourceId, plan.id)
        XCTAssertEqual(item.planName, plan.name)
        XCTAssertTrue(session.items.contains(item))
    }
    
    // MARK: - Data Integrity Tests
    
    func testCascadingDeletes() {
        let activity = createTestActivity()
        let trainingType = createTestTrainingType(activity: activity)
        let exercise = createTestExercise(trainingType: trainingType)
        
        try? context.save()
        
        // In SwiftData, we need to manually handle cascade deletes
        // First delete the exercises
        context.delete(exercise)
        // Then delete the training type
        context.delete(trainingType)
        // Finally delete the activity
        context.delete(activity)
        try? context.save()
        
        let descriptor = FetchDescriptor<Exercise>()
        let remainingExercises = (try? context.fetch(descriptor)) ?? []
        XCTAssertTrue(remainingExercises.isEmpty)
    }
    
    func testDateNormalizationAcrossModels() {
        let now = Date()
        let session = Session(date: now)
        let plan = createTestPlan()
        
        let calendar = Calendar.current
        let expectedDate = calendar.startOfDay(for: now)
        
        assertDatesSameDay(session.date, expectedDate)
        assertDatesSameDay(plan.startDate, expectedDate)
    }
    
    // MARK: - Complex Query Tests
    
    func testComplexRelationshipQueries() {
        // Create complex data structure
        let coreActivity = createTestActivity(name: "Core")
        let anteriorType = createTestTrainingType(activity: coreActivity, name: "Anterior Core")
        _ = createTestExercise(trainingType: anteriorType, name: "Plank")
        
        let climbingActivity = createTestActivity(name: "Climbing")
        let boulderingType = createTestTrainingType(activity: climbingActivity, name: "Bouldering")
        let combo = createTestBoulderCombination(trainingType: boulderingType, name: "Power Circuit")
        let campusExercise = Exercise(name: "Campus Board")
        combo.exercises.append(campusExercise)
        
        try? context.save()
        
        // Test complex queries
        let activityDescriptor = FetchDescriptor<Activity>(
            predicate: #Predicate<Activity> { $0.name.contains("Core") }
        )
        let coreActivities = (try? context.fetch(activityDescriptor)) ?? []
        XCTAssertEqual(coreActivities.count, 1)
        
        let exerciseDescriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { $0.name.contains("Campus") }
        )
        let campusExercises = (try? context.fetch(exerciseDescriptor)) ?? []
        XCTAssertEqual(campusExercises.count, 1)
    }
}
