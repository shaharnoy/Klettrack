//
//  TestSuite.swift
//  ClimbingProgram Tests
//
//  Created by AI Assistant on 23.08.25.
//

import XCTest
import SwiftData
@testable import ClimbingProgram

/**
 * Base Test Suite for ClimbingProgram
 *
 * Provides shared test infrastructure and utilities for all test classes
    */

class ClimbingProgramTestSuite: XCTestCase {
    
    var container: ModelContainer!
    var context: ModelContext!
    
    override func setUp() {
        super.setUp()
        
        // Create in-memory container for testing
        let schema = Schema([
            Activity.self,
            TrainingType.self,
            Exercise.self,
            BoulderCombination.self,
            Session.self,
            SessionItem.self,
            Plan.self,
            PlanDay.self,
            TimerTemplate.self,
            TimerInterval.self,
            TimerSession.self,
            TimerLap.self
        ])
        
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
            context = ModelContext(container)
        } catch {
            XCTFail("Failed to create test container: \(error)")
        }
    }
    
    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }
    
    // MARK: - Shared Test Helpers
    
    func createTestActivity(name: String = "Test Activity") -> Activity {
        let activity = Activity(name: name)
        context.insert(activity)
        return activity
    }
    
    func createTestTrainingType(activity: Activity, name: String = "Test Training Type") -> TrainingType {
        let trainingType = TrainingType(name: name)
        activity.types.append(trainingType)
        return trainingType
    }
    
    func createTestExercise(trainingType: TrainingType, name: String = "Test Exercise") -> Exercise {
        let exercise = Exercise(name: name, repsText: "10", setsText: "3")
        trainingType.exercises.append(exercise)
        return exercise
    }
    
    func createTestSession(date: Date = Date()) -> Session {
        let session = Session(date: date)
        context.insert(session)
        return session
    }
    
    func createTestPlan(name: String = "Test Plan", kind: PlanKind = .weekly) -> Plan {
        let plan = PlanFactory.create(name: name, kind: kind, start: Date(), in: context)
        return plan
    }
    
    func createTestBoulderCombination(trainingType: TrainingType, name: String = "Test Combo") -> BoulderCombination {
        let combo = BoulderCombination(name: name)
        trainingType.combinations.append(combo)
        return combo
    }
    
    // MARK: - Timer Test Helpers
    
    func createTestTimerTemplate(name: String = "Test Timer Template") -> TimerTemplate {
        let template = TimerTemplate(
            name: name,
            templateDescription: "Test template description",
            isRepeating: false,
            repeatCount: nil,
            restTimeBetweenIntervals: nil
        )
        
        let interval = TimerInterval(
            name: "Test Interval",
            workTimeSeconds: 30,
            restTimeSeconds: 15,
            repetitions: 1,
            order: 0
        )
        template.intervals.append(interval)
        context.insert(template)
        
        do {
            try context.save()
        } catch {
            XCTFail("Failed to save test timer template: \(error)")
        }
        
        return template
    }
    
    // MARK: - Assertion Helpers
    
    func assertDatesSameDay(_ date1: Date, _ date2: Date, file: StaticString = #file, line: UInt = #line) {
        let calendar = Calendar.current
        XCTAssertEqual(calendar.startOfDay(for: date1), calendar.startOfDay(for: date2),
                      "Dates should be on the same day", file: file, line: line)
    }
    
    func assertContainsExercise(_ exercises: [Exercise], named exerciseName: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(exercises.contains { $0.name == exerciseName },
                     "Should contain exercise named '\(exerciseName)'", file: file, line: line)
    }
}
