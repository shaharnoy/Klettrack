//  TimerappStateTests.swift
//  klettrack Tests
//
//  Created by Shahar Noy on 30.09.25.

import XCTest

#if canImport(ClimbingProgram)
@testable import ClimbingProgram
#elseif canImport(klettrack)
@testable import klettrack
#endif

@MainActor
final class TimerAppStateTests: XCTestCase {
    func testSwitchToTimerSetsSelectedTab() {
        let state = TimerAppState()
        XCTAssertNotEqual(state.selectedTab, 5)
        state.switchToTimer()
        XCTAssertEqual(state.selectedTab, 5)
    }

    func testSwitchToTimerCarriesAndClearsExerciseContext() {
        let state = TimerAppState()
        let context = ExerciseTimerContext(
            exerciseName: "Hangboard Repeaters",
            planDayDate: Date(),
            planId: UUID(),
            planName: "Strength Block",
            plan: .repBased(reps: 7, sets: 4, restSeconds: 180, templateId: nil)
        )

        state.switchToTimer(exercise: context)
        XCTAssertEqual(state.currentExerciseName, "Hangboard Repeaters")
        XCTAssertEqual(state.exerciseContext?.planName, "Strength Block")

        // A day-level launch must not leave the previous exercise context behind.
        state.switchToTimer()
        XCTAssertNil(state.currentExerciseName)
        XCTAssertNil(state.exerciseContext)
    }
}
