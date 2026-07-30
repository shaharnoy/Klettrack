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

    /// The Save button's own path, driven end to end — not a hand-built `SessionItem`.
    func testSavingWritesOneItemWithPlanIdentity() throws {
        let date = Date()
        let planId = UUID()

        ExerciseLogSheet.Prefill(
            reps: "5", sets: "3", duration: "9", weight: "12.5", notes: "felt strong"
        )
        .commit(
            exerciseName: "Weighted Pull-Ups",
            date: date,
            planId: planId,
            planName: "Strength Block",
            in: context
        )

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

    /// A `.decimalPad` emits the locale's separator, which is a comma across most of
    /// Europe — and `Double("12,5")` is nil. Only the real save path parses these.
    func testSavingParsesACommaDecimalSeparator() throws {
        let date = Date()

        ExerciseLogSheet.Prefill(reps: "5", weight: "12,5").commit(
            exerciseName: "Weighted Pull-Ups", date: date, planId: nil, planName: nil,
            in: context
        )

        let item = try XCTUnwrap(items(on: date).first)
        XCTAssertEqual(item.weightKg, 12.5)
    }

    /// A field left blank means "not recorded". Storing "" instead of nil would render
    /// as a blank line in the log rather than as an absent value.
    func testSavingTurnsBlankFieldsIntoNilRatherThanEmptyStrings() throws {
        let date = Date()

        ExerciseLogSheet.Prefill(reps: "5", grade: "   ", notes: "").commit(
            exerciseName: "Pull-Up", date: date, planId: nil, planName: nil, in: context
        )

        let item = try XCTUnwrap(items(on: date).first)
        XCTAssertEqual(item.reps, 5)
        XCTAssertNil(item.grade, "Whitespace is still blank")
        XCTAssertNil(item.notes)
        XCTAssertNil(item.sets)
        XCTAssertNil(item.weightKg)
        XCTAssertNil(item.duration)
    }

    /// Hand-editing the rollup fields must not discard what the timer recorded.
    func testSavingKeepsThePerSetRecordAlongsideAnEditedRollup() throws {
        let date = Date()
        let sets = [
            LoggedSet(reps: 5, weightKg: 40, rpe: 3),
            LoggedSet(reps: 5, weightKg: 42.5, rpe: 4, note: "last one was slow")
        ]

        var prefill = ExerciseLogSheet.Prefill(loggedSets: sets, durationSeconds: 300)
        prefill.weight = "45"   // the athlete corrects the rollup by hand

        prefill.commit(
            exerciseName: "Weighted Pull-Ups", date: date, planId: nil, planName: nil,
            in: context
        )

        let item = try XCTUnwrap(items(on: date).first)
        XCTAssertEqual(item.weightKg, 45, "The edit wins for the rollup")
        XCTAssertEqual(item.loggedSets.count, 2, "The per-set record is untouched")
        XCTAssertEqual(item.loggedSets.map(\.weightKg), [40, 42.5])
        XCTAssertEqual(item.loggedSets[1].note, "last one was slow")
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
