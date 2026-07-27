//
//  SetSequenceTests.swift
//  klettrack Tests
//
//  The rep-based set sequence: do N reps, confirm, rest, repeat.
//

import XCTest
import SwiftData
@testable import klettrack

@MainActor
final class SetSequenceTests: ClimbingProgramTestSuite {

    private func makeManager() -> TimerManager {
        TimerManager()
    }

    private func makeSession() -> TimerSession {
        let session = TimerSession(exerciseName: "Weighted Pull-Ups")
        context.insert(session)
        return session
    }

    func testStartingASequenceWaitsForTheUser() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 3, restSeconds: 180, session: makeSession())

        XCTAssertEqual(manager.state, .awaitingUser)
        XCTAssertTrue(manager.isAwaitingUser)
        XCTAssertFalse(manager.isRunning, "Nothing counts until the user confirms")

        let sequence = manager.setSequence
        XCTAssertEqual(sequence?.currentSet, 1)
        XCTAssertEqual(sequence?.totalSets, 3)
        XCTAssertEqual(sequence?.repsPerSet, 5)
        XCTAssertEqual(sequence?.accumulatedSeconds, 0)
        XCTAssertFalse(sequence?.isFinalSet ?? true)
    }

    func testConfirmingANonFinalSetStartsTheRest() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 3, restSeconds: 180, session: makeSession())

        manager.confirmSet()

        XCTAssertNotEqual(manager.state, .awaitingUser, "The rest should now be running")
        XCTAssertNotNil(manager.setSequence, "The sequence stays alive across the rest")
        XCTAssertEqual(manager.setSequence?.currentSet, 1, "Still set 1 until the rest completes")
        XCTAssertEqual(manager.configuration?.totalTimeSeconds, 180)

        manager.stop() // don't leave a ticker running
    }

    /// You tapped Done because the set is over — the rest starts immediately,
    /// with no 5-second get-ready in front of it.
    func testRestStartsImmediatelyWithoutGetReady() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 3, restSeconds: 180, session: makeSession())

        manager.confirmSet()

        XCTAssertEqual(manager.configuration?.getReady, false)
        XCTAssertEqual(manager.state, .running, "Not .getReady")
        XCTAssertFalse(manager.isGetReady)
        XCTAssertEqual(manager.currentPhase, .rest, "Straight into the rest")

        manager.stop()
    }

    /// The get-ready flag was previously ignored for total timers; a normal
    /// configuration must still get its 5 seconds.
    func testOrdinaryTotalTimerKeepsItsGetReady() {
        let manager = makeManager()
        manager.start(with: TimerConfiguration(totalTimeSeconds: 60))

        XCTAssertEqual(manager.state, .getReady)
        manager.stop()
    }

    /// The rest finishing advances to the next set rather than ending the exercise.
    func testRestCompletionAdvancesToTheNextSet() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 3, restSeconds: 180, session: makeSession())

        manager.confirmSet()
        manager.advanceSetSequence()

        XCTAssertEqual(manager.state, .awaitingUser)
        XCTAssertEqual(manager.setSequence?.currentSet, 2)
        XCTAssertFalse(manager.isCompleted, "Two sets still to go")
    }

    /// `start()` zeroes totalElapsedTime on every rest, so the sequence must sum it itself.
    func testElapsedTimeAccumulatesAcrossRests() {
        let manager = makeManager()
        let session = makeSession()
        manager.startSetSequence(reps: 5, sets: 3, restSeconds: 180, session: session)

        manager.confirmSet()
        manager.totalElapsedTime = 180
        manager.advanceSetSequence()
        XCTAssertEqual(manager.setSequence?.accumulatedSeconds, 180)

        manager.confirmSet()
        manager.totalElapsedTime = 175
        manager.advanceSetSequence()
        XCTAssertEqual(manager.setSequence?.accumulatedSeconds, 355, "Both rests must be counted")
        XCTAssertEqual(manager.setSequence?.currentSet, 3)

        // Final set: confirming finishes rather than starting a fourth rest.
        manager.confirmSet()
        XCTAssertEqual(manager.state, .completed)
        XCTAssertNil(manager.setSequence)
        XCTAssertEqual(session.totalElapsedSeconds, 355)
        XCTAssertEqual(session.completedIntervals, 3)
        XCTAssertTrue(session.wasCompleted)
        XCTAssertNotNil(session.endDate)
    }

    func testSingleSetSequenceFinishesOnFirstConfirmation() {
        let manager = makeManager()
        let session = makeSession()
        manager.startSetSequence(reps: 8, sets: 1, restSeconds: 180, session: session)

        XCTAssertTrue(manager.setSequence?.isFinalSet ?? false)
        manager.confirmSet()

        XCTAssertEqual(manager.state, .completed)
        XCTAssertNil(manager.setSequence)
        XCTAssertEqual(session.totalElapsedSeconds, 0, "No rest ever ran")
        XCTAssertTrue(session.wasCompleted)
    }

    func testStopAbortsTheSequence() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 3, restSeconds: 180, session: makeSession())
        manager.confirmSet()

        manager.stop()

        XCTAssertNil(manager.setSequence, "A stopped sequence must not resurrect itself")

        // A stray completion after stopping must not advance anything.
        manager.advanceSetSequence()
        XCTAssertNil(manager.setSequence)
    }

    func testStopRecordsAccumulatedTimeAsIncomplete() {
        let manager = makeManager()
        let session = makeSession()
        manager.startSetSequence(reps: 5, sets: 3, restSeconds: 180, session: session)

        manager.confirmSet()
        manager.totalElapsedTime = 180
        manager.advanceSetSequence()

        manager.totalElapsedTime = 0
        manager.stop()

        XCTAssertEqual(session.totalElapsedSeconds, 180, "Time already rested still counts")
        XCTAssertFalse(session.wasCompleted)
    }

    // MARK: - Skipping a rest

    func testSkipRestAdvancesAndCountsOnlyTheTimeActuallyRested() {
        let manager = makeManager()
        let session = makeSession()
        manager.startSetSequence(reps: 5, sets: 3, restSeconds: 180, session: session)

        manager.confirmSet()
        manager.totalElapsedTime = 120   // cut a 3 min rest short at 2 min
        manager.skipRest()

        XCTAssertEqual(manager.state, .awaitingUser)
        XCTAssertEqual(manager.setSequence?.currentSet, 2)
        XCTAssertEqual(manager.setSequence?.accumulatedSeconds, 120,
                       "Logs what was actually rested, not the planned 180")
    }

    func testSkipRestDoesNothingWhileAwaitingTheUser() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 3, restSeconds: 180, session: makeSession())

        manager.skipRest()

        XCTAssertEqual(manager.setSequence?.currentSet, 1, "There is no rest to skip yet")
        XCTAssertEqual(manager.state, .awaitingUser)
    }

    func testSkipRestDoesNothingWithoutASequence() {
        let manager = makeManager()
        manager.skipRest()
        XCTAssertNil(manager.setSequence)
    }

    // MARK: - Display

    /// A lap taken during one rest must not carry into the next one — displayTime for a
    /// total timer is (elapsed - lastLapTime), so a stale lap made it start negative.
    func testDisplayTimeNeverGoesNegativeAfterALapInAPreviousRest() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 3, restSeconds: 180, session: makeSession())

        manager.confirmSet()
        manager.totalElapsedTime = 13
        manager.addLap()
        XCTAssertGreaterThanOrEqual(manager.displayTime, 0)

        manager.advanceSetSequence()   // rest finishes, set 2 prompt
        manager.confirmSet()           // rest 2 starts, totalElapsedTime back to 0

        XCTAssertGreaterThanOrEqual(manager.displayTime, 0, "Rest 2 must not start negative")
        XCTAssertTrue(manager.laps.isEmpty, "Laps are cleared with each rest")

        manager.stop()
    }

    /// The rest runs on a plain total timer whose segment is a work block, so the
    /// phase has to be corrected or the UI reads "Work" during a rest.
    func testRestReportsTheRestPhase() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 3, restSeconds: 180, session: makeSession())
        manager.confirmSet()

        XCTAssertEqual(manager.currentPhase, .rest, "A rest must not read as Work")

        manager.stop()
    }

    func testRestDisplayCountsDown() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 3, restSeconds: 180, session: makeSession())
        manager.confirmSet()

        manager.totalElapsedTime = 0
        XCTAssertEqual(manager.displayTime, 180, "A rest starts at its full length")

        manager.totalElapsedTime = 20
        XCTAssertEqual(manager.displayTime, 160, "and counts down, not up")

        manager.stop()
    }

    func testConfirmIsIgnoredWhenNotAwaitingUser() {
        let manager = makeManager()
        XCTAssertNil(manager.setSequence)

        manager.confirmSet() // no sequence at all

        XCTAssertNil(manager.setSequence)
        XCTAssertNotEqual(manager.state, .completed)
    }
}
