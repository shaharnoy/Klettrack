//  TestSupport.swift
//  klettrack Tests
//
//  Created by Shahar Noy on 30.09.25.

import XCTest
import SwiftData
@testable import klettrack

@MainActor
class BaseSwiftDataTestCase: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext! { container.mainContext }
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        let types: [any PersistentModel.Type] = [
            Activity.self, TrainingType.self, Exercise.self, BoulderCombination.self,
            Session.self, SessionItem.self,
            Plan.self, PlanDay.self,
            TimerTemplate.self, TimerInterval.self, TimerSession.self, TimerLap.self,
            ClimbEntry.self, ClimbStyle.self, ClimbGym.self
        ]
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema(types)
        container = try ModelContainer(for: schema, configurations: config)
    }
    
    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Catalog helpers
    
    @discardableResult
    func createTestActivity(name: String = "Activity") -> Activity {
        let a = Activity(name: name)
        context.insert(a)
        return a
    }
    
    @discardableResult
    func createTestTrainingType(activity: Activity, name: String = "Type") -> TrainingType {
        let tt = TrainingType(name: name)
        activity.types.append(tt)
        return tt
    }
    
    @discardableResult
    func createTestExercise(trainingType: TrainingType, name: String = "Exercise") -> Exercise {
        let e = Exercise(name: name)
        trainingType.exercises.append(e)
        return e
    }
    
    // MARK: - Plans
    
    @discardableResult
    func createTestPlan(name: String = "Plan", kind: PlanKind = .weekly, start: Date = Date()) -> Plan {
        // Delegate to the same factory the app uses to avoid divergence
        PlanFactory.create(name: name, kind: kind, start: start, in: context)
    }
    
    // MARK: - Sessions
    
    @discardableResult
    func createTestSession(date: Date = Date()) -> Session {
        let s = Session(date: date)
        context.insert(s)
        return s
    }
    
    // MARK: - Timer helpers
    
    @discardableResult
    func createTestTimerTemplate(name: String = "Template") -> TimerTemplate {
        let tmpl = TimerTemplate(
            name: name,
            templateDescription: "Test template",
            totalTimeSeconds: nil,
            isRepeating: true,
            repeatCount: 2,
            restTimeBetweenIntervals: 60
        )
        let interval = TimerInterval(
            name: "Work/Rest",
            workTimeSeconds: 10,
            restTimeSeconds: 20,
            repetitions: 3,
            order: 0
        )
        tmpl.intervals.append(interval)
        context.insert(tmpl)
        context.insert(interval)
        return tmpl
    }
}
