//
//  ExerciseLogSheetTests.swift
//  klettrack Tests
//

import XCTest
import SwiftData
@testable import klettrack

final class ExerciseLogSheetTests: ClimbingProgramTestSuite {

    private func items(on date: Date) -> [SessionItem] {
        let sessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        let calendar = Calendar.current
        return sessions
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .flatMap { $0.items }
    }

    /// The sheet's Save path writes through findOrCreateSession, shared with the plan day editor.
    func testSavingWritesOneItemWithPlanIdentity() throws {
        let date = Date()
        let planId = UUID()
        let session = findOrCreateSession(for: date, in: context)
        session.items.append(
            SessionItem(
                exerciseName: "Weighted Pull-Ups",
                planSourceId: planId,
                planName: "Strength Block",
                reps: 5,
                sets: 3,
                weightKg: 12.5,
                notes: "felt strong",
                duration: 9
            )
        )
        try context.save()

        let logged = items(on: date)
        XCTAssertEqual(logged.count, 1)
        let item = try XCTUnwrap(logged.first)
        XCTAssertEqual(item.exerciseName, "Weighted Pull-Ups")
        XCTAssertEqual(item.planSourceId, planId)
        XCTAssertEqual(item.planName, "Strength Block")
        XCTAssertEqual(item.reps, 5)
        XCTAssertEqual(item.sets, 3)
        XCTAssertEqual(item.weightKg, 12.5)
        XCTAssertEqual(item.duration, 9)
        XCTAssertEqual(item.notes, "felt strong")
    }

    func testSavingTwiceOnADateReusesTheSession() throws {
        let date = Date()

        let first = findOrCreateSession(for: date, in: context)
        first.items.append(SessionItem(exerciseName: "A"))
        try context.save()

        let second = findOrCreateSession(for: date, in: context)
        second.items.append(SessionItem(exerciseName: "B"))
        try context.save()

        XCTAssertEqual(first.id, second.id, "Both saves belong to the same day's session")
        let sessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(items(on: date).count, 2)
    }

    // MARK: - Prefill

    func testTimerPrefillConvertsSecondsToWholeMinutes() {
        let prefill = ExerciseLogSheet.Prefill(reps: 5, sets: 3, durationSeconds: 355)
        XCTAssertEqual(prefill.reps, "5")
        XCTAssertEqual(prefill.sets, "3")
        XCTAssertEqual(prefill.duration, "6", "355s rounds to 6 minutes")
        XCTAssertEqual(prefill.weight, "", "Weight is what the user came to fill in")
        XCTAssertEqual(prefill.notes, "")
    }

    func testTimerPrefillLeavesUnknownFieldsBlank() {
        let prefill = ExerciseLogSheet.Prefill(reps: nil, sets: nil, durationSeconds: nil)
        XCTAssertEqual(prefill.reps, "")
        XCTAssertEqual(prefill.sets, "")
        XCTAssertEqual(prefill.duration, "")
    }

    /// A rest shorter than 30s must not round down to a meaningless "0 min".
    func testTimerPrefillNeverRoundsDownToZeroMinutes() {
        let prefill = ExerciseLogSheet.Prefill(reps: nil, sets: nil, durationSeconds: 20)
        XCTAssertEqual(prefill.duration, "1")
    }
}
