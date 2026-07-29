//
//  LoggedSetTests.swift
//  klettrack Tests
//

import XCTest
import SwiftData
@testable import klettrack

final class LoggedSetTests: ClimbingProgramTestSuite {

    // MARK: - Rollup

    /// The whole point of the rollup: uniform sets must produce exactly what a
    /// hand-logged item would have held, so analytics and charts see no change.
    func testUniformSetsRollUpToTheSameValuesAsBefore() {
        let sets = (0..<4).map { _ in LoggedSet(reps: 3, weightKg: 30) }
        let rollup = sets.rollup
        XCTAssertEqual(rollup.reps, 3)
        XCTAssertEqual(rollup.sets, 4)
        XCTAssertEqual(rollup.weightKg, 30)
    }

    func testVariedWeightsRollUpToTheMean() {
        let sets = [
            LoggedSet(reps: 3, weightKg: 30),
            LoggedSet(reps: 3, weightKg: 35),
            LoggedSet(reps: 3, weightKg: 25)
        ]
        let rollup = sets.rollup
        XCTAssertEqual(rollup.weightKg, 30, "30/35/25 averages to 30")
        XCTAssertEqual(rollup.sets, 3)
    }

    /// A bodyweight exercise leaves every weight nil — the rollup must stay nil
    /// rather than collapsing to 0, which would show as "0 kg" in the log.
    func testUnweightedSetsRollUpToNilWeightNotZero() {
        let sets = [LoggedSet(reps: 8), LoggedSet(reps: 8)]
        let rollup = sets.rollup
        XCTAssertNil(rollup.weightKg)
        XCTAssertEqual(rollup.reps, 8)
        XCTAssertEqual(rollup.sets, 2)
    }

    /// Only some sets carry weight: the mean covers the ones that do, and the set
    /// count still covers all of them.
    func testPartiallyWeightedSetsAverageOnlyTheWeightedOnes() {
        let sets = [
            LoggedSet(reps: 5, weightKg: 20),
            LoggedSet(reps: 5, weightKg: nil),
            LoggedSet(reps: 5, weightKg: 10)
        ]
        let rollup = sets.rollup
        XCTAssertEqual(rollup.weightKg, 15)
        XCTAssertEqual(rollup.sets, 3)
    }

    func testEmptySetsRollUpToAllNil() {
        let rollup = [LoggedSet]().rollup
        XCTAssertNil(rollup.reps)
        XCTAssertNil(rollup.sets, "No sets logged is not the same as zero sets")
        XCTAssertNil(rollup.weightKg)
    }

    // MARK: - Effort

    func testEffortLabelMapsTheFiveLevels() {
        XCTAssertEqual(LoggedSet(rpe: 1).effortLabel, "Easy")
        XCTAssertEqual(LoggedSet(rpe: 5).effortLabel, "Max")
    }

    func testEffortLabelIsNilWhenUnratedOrOutOfRange() {
        XCTAssertNil(LoggedSet().effortLabel)
        XCTAssertNil(LoggedSet(rpe: 0).effortLabel)
        XCTAssertNil(LoggedSet(rpe: 6).effortLabel)
    }

    // MARK: - Persistence

    /// `loggedSets` is a Codable array attribute, not a relationship. It has to
    /// survive a save/fetch cycle for that shortcut to be sound.
    func testLoggedSetsSurviveASaveAndFetch() throws {
        let date = Date()
        let session = findOrCreateSession(for: date, in: context)
        session.items.append(
            SessionItem(
                exerciseName: "Weighted Pull-up",
                reps: 3,
                sets: 3,
                weightKg: 30,
                loggedSets: [
                    LoggedSet(reps: 3, weightKg: 30, rpe: 1),
                    LoggedSet(reps: 3, weightKg: 32.5, rpe: 3, note: "grip slipped"),
                    LoggedSet(reps: 3, weightKg: 27.5, rpe: 5)
                ]
            )
        )
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SessionItem>())
        let item = try XCTUnwrap(fetched.first)
        XCTAssertEqual(item.loggedSets.count, 3)
        XCTAssertEqual(item.loggedSets[1].weightKg, 32.5)
        XCTAssertEqual(item.loggedSets[1].note, "grip slipped")
        XCTAssertEqual(item.loggedSets[2].effortLabel, "Max")
    }

    /// Every pre-existing item predates the field, so the default has to be an
    /// empty array — this is what lets the change ship without a backfill.
    func testItemsLoggedWithoutSetDetailDefaultToEmpty() throws {
        let session = findOrCreateSession(for: Date(), in: context)
        session.items.append(SessionItem(exerciseName: "Pull-up", reps: 8, sets: 3))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SessionItem>())
        XCTAssertEqual(try XCTUnwrap(fetched.first).loggedSets, [])
    }

    // MARK: - Coding

    /// The CSV column round-trips this JSON. `id` must not be encoded.
    func testCodingOmitsIdentityAndRoundTrips() throws {
        let original = [
            LoggedSet(reps: 3, weightKg: 30, rpe: 2, note: "solid"),
            LoggedSet(reps: 2, weightKg: 30)
        ]
        let data = try JSONEncoder().encode(original)
        let objects = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(
            Set(objects[0].keys),
            ["reps", "weightKg", "rpe", "note"],
            "A stale UUID must not survive an export"
        )

        let decoded = try JSONDecoder().decode([LoggedSet].self, from: data)
        XCTAssertEqual(decoded.map(\.weightKg), [30, 30])
        XCTAssertEqual(decoded.map(\.reps), [3, 2])
        XCTAssertEqual(decoded[0].note, "solid")
        XCTAssertNil(decoded[1].rpe)
    }

    /// A `sets_detail` cell exported before any later field was added must still decode.
    ///
    /// `csvDecoded` swallows a decode failure into `[]`, so a *non-Optional* new field
    /// on `LoggedSet` would silently blank the per-set detail of every historical
    /// export instead of failing loudly. If this test breaks, the new field needs to be
    /// Optional — not the fixture updated.
    func testAHistoricalSetsDetailCellStillDecodes() {
        let exported = #"[{"reps":3,"weightKg":30,"rpe":2,"note":"solid"},{"reps":2}]"#

        let decoded = [LoggedSet].csvDecoded(exported)

        XCTAssertEqual(decoded.count, 2, "A historical export must not decode to nothing")
        XCTAssertEqual(decoded[0].weightKg, 30)
        XCTAssertEqual(decoded[0].rpe, 2)
        XCTAssertEqual(decoded[1].reps, 2)
        XCTAssertNil(decoded[1].weightKg)
    }

    /// An attempts-based set carries effort and a note and nothing else. Round-tripping
    /// it must not invent a zero weight, which would render as "0 kg" in the log.
    func testAnAttemptSetRoundTripsWithoutAWeight() throws {
        let attempts = [
            LoggedSet(reps: nil, weightKg: nil, rpe: 5, note: "fell at the crux"),
            LoggedSet(reps: nil, weightKg: nil, rpe: 3)
        ]

        let decoded = [LoggedSet].csvDecoded(attempts.csvEncoded)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertTrue(decoded.allSatisfy { $0.weightKg == nil })
        XCTAssertTrue(decoded.allSatisfy { $0.reps == nil })
        XCTAssertEqual(decoded[0].note, "fell at the crux")
        XCTAssertEqual(decoded.rollup.weightKg, nil, "No weight means no weight, not zero")
        XCTAssertEqual(decoded.rollup.sets, 2)
    }

    // MARK: - Grouping

    /// A nested session reads back as bouts, not as a flat run of fifteen.
    func testGroupingAPerEffortLogBySet() {
        let sets = [
            LoggedSet(rpe: 3, setNumber: 1),
            LoggedSet(rpe: 4, setNumber: 1),
            LoggedSet(rpe: 5, setNumber: 2)
        ]
        XCTAssertEqual(sets.groupedBySet.map(\.setNumber), [1, 2])
        XCTAssertEqual(sets.groupedBySet.map { $0.efforts.count }, [2, 1])
    }

    /// Hand-logged and pre-nesting rows have no set number; they stay one flat group.
    func testUngroupedLogsStayFlat() {
        let sets = [LoggedSet(reps: 5, weightKg: 40), LoggedSet(reps: 5, weightKg: 40)]
        XCTAssertEqual(sets.groupedBySet.count, 1)
        XCTAssertNil(sets.groupedBySet.first?.setNumber)
    }
}
