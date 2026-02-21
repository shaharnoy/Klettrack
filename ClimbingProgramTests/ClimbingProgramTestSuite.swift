// ClimbingProgramTestSuite.swift
//  klettrack tests
//  Created by Shahar Noy on 30.09.25.

import XCTest
import SwiftData
@testable import klettrack

class ClimbingProgramTestSuite: XCTestCase {

    // Shared in-memory SwiftData container for each test case
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() {
        super.setUp()

        // Build schema with all @Model types touched by tests/utilities
        let schema = Schema([
            // Catalog
            Activity.self,
            TrainingType.self,
            BoulderCombination.self,
            Exercise.self,
            SyncState.self,
            SyncMutation.self,

            // Plans
            Plan.self,
            PlanDay.self,

            // Sessions (log)
            Session.self,
            SessionItem.self,

            // Timer
            TimerTemplate.self,
            TimerInterval.self,
            TimerSession.self,
            TimerLap.self,

            // Climbing log (used by CSV export/tests)
            ClimbEntry.self,
            ClimbStyle.self,
            ClimbGym.self,
            ClimbMedia.self
        ])

        // In-memory configuration for isolation and speed
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        // Create the container and a working context
        container = try! ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Test helpers

    @discardableResult
    func createTestPlan(
        name: String = "Test Plan",
        kindKey: String = "weekly",
        start: Date = Date()
    ) -> Plan {
        let fetch = FetchDescriptor<PlanKindModel>(predicate: #Predicate { $0.key == kindKey })
        let kindModel = (try? context.fetch(fetch))?.first ?? PlanKindModel(key: kindKey, name: kindKey.capitalized, totalWeeks: kindKey == "weekly" ? nil : 1, isRepeating: kindKey == "weekly", order: 0)
        if (try? context.fetch(fetch))?.first == nil { context.insert(kindModel) }
        return PlanFactory.create(name: name, kind: kindModel, start: start, in: context)
    }

    @discardableResult
    func createTestSession(date: Date = Date()) -> Session {
        let s = Session(date: date)
        context.insert(s)
        return s
    }

    @discardableResult
    func createTestActivity(name: String = "Test Activity") -> Activity {
        let a = Activity(name: name)
        context.insert(a)
        return a
    }

    @discardableResult
    func createTestTrainingType(activity: Activity, name: String = "Test Training Type") -> TrainingType {
        let t = TrainingType(name: name)
        activity.types.append(t)
        return t
    }

    @discardableResult
    func createTestExercise(
        trainingType: TrainingType,
        name: String = "Test Exercise",
        repsText: String? = nil,
        setsText: String? = nil
    ) -> Exercise {
        let e = Exercise(name: name, repsText: repsText, setsText: setsText)
        trainingType.exercises.append(e)
        return e
    }

    @discardableResult
    func createTestBoulderCombination(
        trainingType: TrainingType,
        name: String = "Test Combination",
        comboDescription: String? = nil
    ) -> BoulderCombination {
        let combo = BoulderCombination(name: name, comboDescription: comboDescription)
        trainingType.combinations.append(combo)
        return combo
    }

    // MARK: - Custom assertions

    func assertDatesSameDay(_ d1: Date, _ d2: Date, file: StaticString = #filePath, line: UInt = #line) {
        let cal = Calendar.current
        let s1 = cal.startOfDay(for: d1)
        let s2 = cal.startOfDay(for: d2)
        XCTAssertEqual(s1, s2, "Expected dates to be on the same calendar day. Got \(d1) vs \(d2).", file: file, line: line)
    }

    // MARK: - Additional helpers similar to BaseSwiftDataTestCase

    func planKind(withKey key: String = "weekly") -> PlanKindModel? {
        let fetch = FetchDescriptor<PlanKindModel>(predicate: #Predicate { $0.key == key })
        return (try? context.fetch(fetch))?.first
    }

    func dayType(withKey key: String) -> DayTypeModel? {
        let fetch = FetchDescriptor<DayTypeModel>(predicate: #Predicate { $0.key == key })
        return (try? context.fetch(fetch))?.first
    }
}
