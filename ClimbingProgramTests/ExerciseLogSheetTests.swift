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

    // MARK: - Prefill from a per-set record

    /// The timer knows what was actually lifted, so the form opens on actuals rather
    /// than on the plan's counts.
    func testPerSetPrefillUsesTheRollupNotThePlan() {
        let prefill = ExerciseLogSheet.Prefill(
            loggedSets: [
                LoggedSet(reps: 3, weightKg: 30),
                LoggedSet(reps: 3, weightKg: 35),
                LoggedSet(reps: 3, weightKg: 25)
            ],
            durationSeconds: 420
        )

        XCTAssertEqual(prefill.reps, "3")
        XCTAssertEqual(prefill.sets, "3")
        XCTAssertEqual(prefill.weight, "30", "The mean of 30/35/25")
        XCTAssertEqual(prefill.duration, "7")
        XCTAssertEqual(prefill.loggedSets.count, 3)
    }

    /// A whole number must not arrive in the text field as "3.0".
    func testPerSetPrefillDropsTrailingZeroes() {
        let prefill = ExerciseLogSheet.Prefill(
            loggedSets: [LoggedSet(reps: 8, weightKg: 20)],
            durationSeconds: nil
        )
        XCTAssertEqual(prefill.reps, "8")
        XCTAssertEqual(prefill.sets, "1")
        XCTAssertEqual(prefill.weight, "20")
        XCTAssertEqual(prefill.duration, "")
    }

    /// The field is localised, so assert the contract rather than a separator: what
    /// the form shows must parse back to what was lifted, via the same comma
    /// normalisation `save()` applies.
    func testPerSetPrefillKeepsAFractionalWeight() {
        let prefill = ExerciseLogSheet.Prefill(
            loggedSets: [LoggedSet(reps: 3, weightKg: 32.5)],
            durationSeconds: nil
        )
        XCTAssertEqual(
            Double(prefill.weight.replacing(",", with: ".")), 32.5,
            "32.5 must not be truncated to 32"
        )
    }

    /// A bodyweight sequence has no weight at all — the field must open blank, not "0".
    func testPerSetPrefillLeavesWeightBlankWhenNoneWasLogged() {
        let prefill = ExerciseLogSheet.Prefill(
            loggedSets: [LoggedSet(reps: 10), LoggedSet(reps: 8)],
            durationSeconds: nil
        )
        XCTAssertEqual(prefill.weight, "")
        XCTAssertEqual(prefill.sets, "2")
    }

    /// The whole point of the round trip: what the timer captured reaches the log.
    func testSavingPersistsThePerSetRecord() throws {
        let date = Date()
        let sets = [
            LoggedSet(reps: 3, weightKg: 30, rpe: 1),
            LoggedSet(reps: 3, weightKg: 32.5, rpe: 4, note: "grip slipped")
        ]
        let session = findOrCreateSession(for: date, in: context)
        let prefill = ExerciseLogSheet.Prefill(loggedSets: sets, durationSeconds: 300)
        session.items.append(
            SessionItem(
                exerciseName: "Weighted Pull-up",
                reps: 3,
                sets: 2,
                weightKg: 31.25,
                loggedSets: prefill.loggedSets
            )
        )
        try context.save()

        let item = try XCTUnwrap(items(on: date).first)
        XCTAssertEqual(item.loggedSets.count, 2)
        XCTAssertEqual(item.loggedSets[1].note, "grip slipped")
        XCTAssertEqual(item.loggedSets[1].effortLabel, "Very Hard")
    }
}
