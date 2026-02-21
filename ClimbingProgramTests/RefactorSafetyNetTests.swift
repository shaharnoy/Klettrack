//
//  RefactorSafetyNetTests.swift
//  Klettrack tests
//  Created by Shahar Noy on 17.02.26.
//

import XCTest
import SwiftData
@testable import klettrack

@MainActor
final class RefactorSafetyNetTests: BaseSwiftDataTestCase {

    func testTimerManagerFormatTimeUnderHour() {
        let manager = TimerManager()

        XCTAssertEqual(manager.formatTime(0), "0:00")
        XCTAssertEqual(manager.formatTime(59), "0:59")
        XCTAssertEqual(manager.formatTime(125), "2:05")
    }

    func testTimerManagerFormatTimeOverHour() {
        let manager = TimerManager()

        XCTAssertEqual(manager.formatTime(3_661), "1:01:01")
        XCTAssertEqual(manager.formatTime(7_200), "2:00:00")
    }

    func testTimerManagerFormatTimeDetailed() {
        let manager = TimerManager()
        let parts = manager.formatTimeDetailed(3_661)

        XCTAssertEqual(parts.hours, 1)
        XCTAssertEqual(parts.minutes, 1)
        XCTAssertEqual(parts.seconds, 1)
    }

    func testAppendWeeksCopiesRecurringTemplateForMatchingWeekday() throws {
        let restType = ensureDayType(withKey: "rest", name: "Rest", colorKey: "gray")
        let climbingType = ensureDayType(withKey: "climbingSmall", name: "Climb", colorKey: "blue")
        _ = restType

        let start = Calendar.current.startOfDay(for: Date())
        let plan = createTestPlan(name: "Recurring Plan", kindKey: "weekly", start: start)
        let sortedBefore = plan.days.sorted { $0.date < $1.date }
        let templateWeekday = Calendar.current.component(.weekday, from: sortedBefore[0].date)

        plan.recurringChosenExercisesByWeekday[templateWeekday] = ["Pull-up", "Core Hold"]
        plan.recurringExerciseOrderByWeekday[templateWeekday] = ["Pull-up": 0, "Core Hold": 1]
        plan.recurringDayTypeIdByWeekday[templateWeekday] = climbingType.id

        PlanFactory.appendWeeks(to: plan, count: 1, in: context)
        try context.save()

        let sortedAfter = plan.days.sorted { $0.date < $1.date }
        XCTAssertEqual(sortedAfter.count, 14)

        let firstAppendedDay = sortedAfter[7]
        XCTAssertEqual(Calendar.current.component(.weekday, from: firstAppendedDay.date), templateWeekday)
        XCTAssertEqual(firstAppendedDay.chosenExercises, ["Pull-up", "Core Hold"])
        XCTAssertEqual(firstAppendedDay.exerciseOrder["Pull-up"], 0)
        XCTAssertEqual(firstAppendedDay.exerciseOrder["Core Hold"], 1)
        XCTAssertEqual(firstAppendedDay.type?.id, climbingType.id)
    }

    func testClimbSessionManagerInitializeFromTodaysClimbsUsesMostRecentTypeAndNonUnknownGym() throws {
        let manager = ClimbSessionManager.shared
        manager.clearSession()

        let now = Date()
        let oneHourAgo = Calendar.current.date(byAdding: .hour, value: -1, to: now) ?? now

        let older = ClimbEntry(
            climbType: .sport,
            grade: "6a",
            style: "Technical",
            gym: "Stronghold",
            dateLogged: oneHourAgo
        )
        let newer = ClimbEntry(
            climbType: .boulder,
            grade: "6b",
            style: "Power",
            gym: "Unknown",
            dateLogged: now
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        manager.initializeFromTodaysClimbs(modelContext: context)

        XCTAssertEqual(manager.getSessionClimbType(from: context), .boulder)
        XCTAssertEqual(manager.getSessionGym(from: context), "Stronghold")

        manager.clearSession()
    }

    func testClimbSessionManagerUpdateSessionClearsUnknownGym() {
        let manager = ClimbSessionManager.shared
        manager.clearSession()

        manager.updateSession(climbType: .sport, gym: "Unknown")

        XCTAssertEqual(manager.getSessionClimbType(), .sport)
        XCTAssertNil(manager.getSessionGym())

        manager.clearSession()
    }
}
