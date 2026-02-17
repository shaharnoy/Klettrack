//
//  TestSupport.swift
//  Klettrack tests
//  Created by Shahar Noy on 17.02.26.
//

import XCTest
import SwiftData
@testable import klettrack

@MainActor
class BaseSwiftDataTestCase: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        try super.setUpWithError()
        let types: [any PersistentModel.Type] = [
            Activity.self, TrainingType.self, Exercise.self, BoulderCombination.self,
            SyncState.self, SyncMutation.self,
            Session.self, SessionItem.self,
            Plan.self, PlanDay.self,
            TimerTemplate.self, TimerInterval.self, TimerSession.self, TimerLap.self,
            ClimbEntry.self, ClimbStyle.self, ClimbGym.self, ClimbMedia.self
        ]
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema(types)
        container = try ModelContainer(for: schema, configurations: config)
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }
}

extension BaseSwiftDataTestCase {
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
    func createTestPlan(
        name: String = "Plan",
        kindKey: String = "weekly",
        start: Date = Date()
    ) -> Plan {
        let fetch = FetchDescriptor<PlanKindModel>(predicate: #Predicate { $0.key == kindKey })
        let resolvedKind = (try? context.fetch(fetch))?.first
            ?? PlanKindModel(
                key: kindKey,
                name: kindKey.capitalized,
                totalWeeks: kindKey == "weekly" ? nil : 1,
                isRepeating: kindKey == "weekly",
                order: 0
            )
        if (try? context.fetch(fetch))?.first == nil {
            context.insert(resolvedKind)
        }
        return PlanFactory.create(name: name, kind: resolvedKind, start: start, in: context)
    }

    // MARK: - DayType helpers
    /// Fetch a DayTypeModel by key, creating and inserting a minimal one if missing.
    @discardableResult
    func ensureDayType(withKey key: String,
                       name: String? = nil,
                       order: Int = 0,
                       colorKey: String = "gray") -> DayTypeModel {
        let fetch = FetchDescriptor<DayTypeModel>(predicate: #Predicate { $0.key == key })
        if let existing = (try? context.fetch(fetch))?.first {
            return existing
        }
        let created = DayTypeModel(
            key: key,
            name: name ?? key.capitalized,
            order: order,
            colorKey: colorKey
        )
        context.insert(created)
        return created
    }

    /// Convenience to try fetch without creating.
    func dayTypeIfExists(withKey key: String) -> DayTypeModel? {
        let fetch = FetchDescriptor<DayTypeModel>(predicate: #Predicate { $0.key == key })
        return (try? context.fetch(fetch))?.first
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
