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

    /// A clock the test winds forward by hand, so "the athlete spent 30 seconds on this
    /// set" is a fact rather than a sleep.
    private final class StubClock: Clock, @unchecked Sendable {
        private var current = Date(timeIntervalSince1970: 1_800_000_000)
        func now() -> Date { current }
        func advance(_ seconds: TimeInterval) { current += seconds }
    }

    private func makeSession() -> TimerSession {
        let session = TimerSession(exerciseName: "Weighted Pull-Ups")
        context.insert(session)
        return session
    }

    // MARK: - Nested reps inside sets

    /// The reported case: 5 sets of 3 goes at the same boulder. Fifteen efforts, a short
    /// rest between goes and a long one between bouts.
    func testANestedSequenceRunsEveryRepOfEverySet() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 5, restBetweenReps: 30, restBetweenSets: 180,
                                 shape: .attempts, session: makeSession())

        let sequence = try? XCTUnwrap(manager.setSequence)
        XCTAssertEqual(sequence?.totalEfforts, 15)
        XCTAssertEqual(sequence?.effortsPerSet, 3)
        XCTAssertEqual(sequence?.currentSet, 1)
        XCTAssertEqual(sequence?.currentRep, 1)
        XCTAssertEqual(manager.effortLogs.count, 15)
        XCTAssertEqual(manager.effortLogs.map(\.setNumber).prefix(4), [1, 1, 1, 2])
    }

    /// Which rest runs is the whole point: short within a bout, long between them.
    func testTheRestBetweenRepsDiffersFromTheRestBetweenSets() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 2, restBetweenReps: 30, restBetweenSets: 180,
                                 shape: .attempts, session: makeSession())

        // Rep 1 → rep 2, still inside set 1.
        manager.confirmEffort()
        XCTAssertEqual(manager.configuration?.totalTimeSeconds, 30, "Between reps")
        manager.advanceSetSequence()

        // Rep 2 → rep 3, still inside set 1.
        manager.confirmEffort()
        XCTAssertEqual(manager.configuration?.totalTimeSeconds, 30)
        manager.advanceSetSequence()

        // Rep 3 is the last of set 1, so the next rest crosses into set 2.
        XCTAssertTrue(manager.setSequence?.isLastRepOfSet ?? false)
        manager.confirmEffort()
        XCTAssertEqual(manager.configuration?.totalTimeSeconds, 180, "Between sets")
        manager.advanceSetSequence()

        XCTAssertEqual(manager.setSequence?.currentSet, 2)
        XCTAssertEqual(manager.setSequence?.currentRep, 1)
    }

    /// No rep-rest means reps run continuously: five pull-ups in a row are one effort,
    /// not five. This is the guard that today's behaviour is untouched.
    func testWithoutARepRestTheSequenceIsOneEffortPerSet() {
        let manager = makeManager()
        let session = makeSession()
        manager.startSetSequence(reps: 5, sets: 3, restBetweenReps: 0, restBetweenSets: 180,
                                 shape: .weighted, session: session)

        let sequence = try? XCTUnwrap(manager.setSequence)
        XCTAssertEqual(sequence?.effortsPerSet, 1, "Not 5 — the reps aren't separate efforts")
        XCTAssertEqual(sequence?.totalEfforts, 3)
        XCTAssertEqual(manager.effortLogs.count, 3)
        XCTAssertEqual(manager.effortLogs.map(\.reps), [5, 5, 5], "Each log is a set of five")
        XCTAssertEqual(manager.effortLogs.map(\.setNumber), [1, 2, 3])

        manager.confirmEffort()
        XCTAssertEqual(manager.configuration?.totalTimeSeconds, 180)
    }

    /// A nested effort is a single rep, so it carries no rep count of its own.
    func testANestedEffortLogsNoRepCount() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 2, restBetweenReps: 30, restBetweenSets: 180,
                                 shape: .attempts, session: makeSession())

        XCTAssertTrue(manager.effortLogs.allSatisfy { $0.reps == nil })
    }

    /// Both rest lengths and the efforts themselves belong in the logged duration.
    func testNestedDurationCountsBothRestsAndTheEfforts() {
        let clock = StubClock()
        let manager = TimerManager(clock: clock)
        let session = makeSession()
        manager.startSetSequence(reps: 2, sets: 2, restBetweenReps: 30, restBetweenSets: 180,
                                 shape: .attempts, session: session)

        // set 1 rep 1 (10s) → 30s rest → rep 2 (10s) → 180s rest
        clock.advance(10); manager.confirmEffort()
        manager.totalElapsedTime = 30; manager.advanceSetSequence()
        clock.advance(10); manager.confirmEffort()
        manager.totalElapsedTime = 180; manager.advanceSetSequence()
        // set 2 rep 1 (10s) → 30s rest → rep 2 (10s) → finish
        clock.advance(10); manager.confirmEffort()
        manager.totalElapsedTime = 30; manager.advanceSetSequence()
        clock.advance(10); manager.confirmEffort()

        XCTAssertEqual(session.totalElapsedSeconds, 40 + 30 + 180 + 30)
        XCTAssertEqual(session.completedIntervals, 4, "Four efforts confirmed")
    }

    /// Nothing may push past the prescription — the plan is set in the catalog.
    func testNavigationCannotRunPastThePlan() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 1, restBetweenReps: 30, restBetweenSets: 0,
                                 shape: .attempts, session: makeSession())

        manager.goToEffort(99)
        XCTAssertEqual(manager.setSequence?.currentEffort, 3, "Clamped to the last effort")
        XCTAssertEqual(manager.effortLogs.count, 3, "No effort was invented")
    }

    func testStartingASequenceWaitsForTheUser() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        XCTAssertEqual(manager.state, .awaitingUser)
        XCTAssertTrue(manager.isAwaitingUser)
        XCTAssertFalse(manager.isRunning, "Nothing counts until the user confirms")

        let sequence = manager.setSequence
        XCTAssertEqual(sequence?.currentSet, 1)
        XCTAssertEqual(sequence?.totalSets, 3)
        XCTAssertEqual(sequence?.effortsPerSet, 1, "No rep rest configured, so one effort per set")
        XCTAssertEqual(manager.effortLogs.first?.reps, 5)
        XCTAssertEqual(sequence?.accumulatedSeconds, 0)
        XCTAssertFalse(sequence?.isFinalEffort ?? true)
    }

    func testConfirmingANonFinalSetStartsTheRest() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.confirmEffort()

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
        manager.startSetSequence(reps: 5, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.confirmEffort()

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
        manager.startSetSequence(reps: 5, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.confirmEffort()
        manager.advanceSetSequence()

        XCTAssertEqual(manager.state, .awaitingUser)
        XCTAssertEqual(manager.setSequence?.currentSet, 2)
        XCTAssertFalse(manager.isCompleted, "Two sets still to go")
    }

    /// `start()` zeroes totalElapsedTime on every rest, so the sequence must sum it itself.
    func testElapsedTimeAccumulatesAcrossRests() {
        let manager = makeManager()
        let session = makeSession()
        manager.startSetSequence(reps: 5, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: session)

        manager.confirmEffort()
        manager.totalElapsedTime = 180
        manager.advanceSetSequence()
        XCTAssertEqual(manager.setSequence?.accumulatedSeconds, 180)

        manager.confirmEffort()
        manager.totalElapsedTime = 175
        manager.advanceSetSequence()
        XCTAssertEqual(manager.setSequence?.accumulatedSeconds, 355, "Both rests must be counted")
        XCTAssertEqual(manager.setSequence?.currentSet, 3)

        // Final set: confirming finishes rather than starting a fourth rest.
        manager.confirmEffort()
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
        manager.startSetSequence(reps: 8, sets: 1, restBetweenReps: 0, restBetweenSets: 180, session: session)

        XCTAssertTrue(manager.setSequence?.isFinalEffort ?? false)
        manager.confirmEffort()

        XCTAssertEqual(manager.state, .completed)
        XCTAssertNil(manager.setSequence)
        XCTAssertEqual(session.totalElapsedSeconds, 0, "No rest ever ran")
        XCTAssertTrue(session.wasCompleted)
    }

    // MARK: - How long the exercise actually took

    /// The logged duration is the whole exercise, sets included — not just the rests.
    ///
    /// Pairs with `testElapsedTimeAccumulatesAcrossRests` above, which runs the same
    /// three sets without advancing the clock and gets 355. The 90 seconds between them
    /// is the time spent on the sets, which used to be recorded nowhere.
    func testDurationCountsTimeSpentOnTheSetsAndNotOnlyTheRests() {
        let clock = StubClock()
        let manager = TimerManager(clock: clock)
        let session = makeSession()
        manager.startSetSequence(reps: 5, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: session)

        clock.advance(30)             // set 1
        manager.confirmEffort()
        manager.totalElapsedTime = 180
        manager.advanceSetSequence()

        clock.advance(30)             // set 2
        manager.confirmEffort()
        manager.totalElapsedTime = 175
        manager.advanceSetSequence()

        clock.advance(30)             // set 3, the final one — no rest follows it
        manager.confirmEffort()

        XCTAssertEqual(session.totalElapsedSeconds, 90 + 355,
                       "Three sets of 30s plus rests of 180s and 175s")
        XCTAssertTrue(session.wasCompleted)
    }

    /// The final set is the one nothing else would bank: no rest runs after it.
    func testTheFinalSetsOwnTimeIsCounted() {
        let clock = StubClock()
        let manager = TimerManager(clock: clock)
        let session = makeSession()
        manager.startSetSequence(reps: 8, sets: 1, restBetweenReps: 0, restBetweenSets: 180, session: session)

        clock.advance(45)
        manager.confirmEffort()

        XCTAssertEqual(session.totalElapsedSeconds, 45, "No rest ever ran, but the set did")
    }

    /// Finishing early still counts the set you were on when you stopped.
    func testFinishingEarlyBanksTheSetInProgress() {
        let clock = StubClock()
        let manager = TimerManager(clock: clock)
        let session = makeSession()
        manager.startSetSequence(reps: 5, sets: 5, restBetweenReps: 0, restBetweenSets: 60, session: session)

        clock.advance(40)
        manager.confirmEffort()
        manager.totalElapsedTime = 60
        manager.advanceSetSequence()

        clock.advance(20)             // partway into set 2, then stop
        manager.finishSetSequence()

        XCTAssertEqual(session.totalElapsedSeconds, 40 + 60 + 20)
        XCTAssertEqual(session.completedIntervals, 1, "Only set 1 was confirmed")
    }

    func testAbandoningMidSetStillRecordsTheTimeSpent() {
        let clock = StubClock()
        let manager = TimerManager(clock: clock)
        let session = makeSession()
        manager.startSetSequence(reps: 5, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: session)

        clock.advance(25)
        manager.stop()

        XCTAssertEqual(session.totalElapsedSeconds, 25)
        XCTAssertFalse(session.wasCompleted)
    }

    // MARK: - Delivering less than the prescription

    /// The plan asks for five sets, you had three in you. Only the three reach the log.
    func testFinishingEarlyLogsOnlyTheSetsActuallyConfirmed() {
        let manager = makeManager()
        let session = makeSession()
        manager.startSetSequence(reps: 5, sets: 5, restBetweenReps: 0, restBetweenSets: 180, session: session)

        for _ in 1...3 {
            manager.confirmEffort()
            manager.totalElapsedTime = 180
            manager.advanceSetSequence()
        }

        XCTAssertEqual(manager.effortLogs.count, 5, "All five are laid out, so you can skip ahead")
        XCTAssertEqual(manager.performedEffortCount, 3)
        XCTAssertEqual(manager.performedEffortLogs.count, 3, "Only what was confirmed is logged")

        manager.finishSetSequence()

        XCTAssertEqual(manager.state, .completed)
        XCTAssertEqual(session.completedIntervals, 3, "What was done, not what was asked")
        XCTAssertTrue(session.wasCompleted, "Stopping short is a training decision, not an abort")
        XCTAssertEqual(manager.performedEffortLogs.count, 3, "The log survives completion")
    }

    /// Skipping with the chevron is not doing the set.
    func testSkippingASetDoesNotCountItAsPerformed() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 4, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.confirmEffort()          // set 1 done
        manager.totalElapsedTime = 180
        manager.advanceSetSequence()  // now on set 2
        manager.nextEffort()             // skip set 2 without doing it

        XCTAssertEqual(manager.setSequence?.currentSet, 3)
        XCTAssertEqual(manager.performedEffortCount, 1)
        XCTAssertEqual(manager.performedEffortLogs.count, 1)
    }

    /// Going back to correct set 2 of 4 must not retract sets 3 and 4.
    func testSteppingBackKeepsTheHighWaterMark() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 4, restBetweenReps: 0, restBetweenSets: 60, session: makeSession())

        for _ in 1...3 {
            manager.confirmEffort()
            manager.advanceSetSequence()
        }
        XCTAssertEqual(manager.performedEffortCount, 3)

        manager.previousEffort()
        manager.previousEffort()

        XCTAssertEqual(manager.setSequence?.currentSet, 2)
        XCTAssertEqual(manager.performedEffortCount, 3, "Reviewing a set doesn't undo later ones")
    }

    func testNothingIsLoggedBeforeTheFirstDone() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        XCTAssertEqual(manager.effortLogs.count, 3)
        XCTAssertEqual(manager.performedEffortCount, 0)
        XCTAssertTrue(manager.performedEffortLogs.isEmpty)
    }

    func testStopAbortsTheSequence() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())
        manager.confirmEffort()

        manager.stop()

        XCTAssertNil(manager.setSequence, "A stopped sequence must not resurrect itself")

        // A stray completion after stopping must not advance anything.
        manager.advanceSetSequence()
        XCTAssertNil(manager.setSequence)
    }

    func testStopRecordsAccumulatedTimeAsIncomplete() {
        let manager = makeManager()
        let session = makeSession()
        manager.startSetSequence(reps: 5, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: session)

        manager.confirmEffort()
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
        manager.startSetSequence(reps: 5, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: session)

        manager.confirmEffort()
        manager.totalElapsedTime = 120   // cut a 3 min rest short at 2 min
        manager.skipRest()

        XCTAssertEqual(manager.state, .awaitingUser)
        XCTAssertEqual(manager.setSequence?.currentSet, 2)
        XCTAssertEqual(manager.setSequence?.accumulatedSeconds, 120,
                       "Logs what was actually rested, not the planned 180")
    }

    func testSkipRestDoesNothingWhileAwaitingTheUser() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

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
        manager.startSetSequence(reps: 5, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.confirmEffort()
        manager.totalElapsedTime = 13
        manager.addLap()
        XCTAssertGreaterThanOrEqual(manager.displayTime, 0)

        manager.advanceSetSequence()   // rest finishes, set 2 prompt
        manager.confirmEffort()           // rest 2 starts, totalElapsedTime back to 0

        XCTAssertGreaterThanOrEqual(manager.displayTime, 0, "Rest 2 must not start negative")
        XCTAssertTrue(manager.laps.isEmpty, "Laps are cleared with each rest")

        manager.stop()
    }

    /// The rest runs on a plain total timer whose segment is a work block, so the
    /// phase has to be corrected or the UI reads "Work" during a rest.
    func testRestReportsTheRestPhase() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())
        manager.confirmEffort()

        XCTAssertEqual(manager.currentPhase, .rest, "A rest must not read as Work")

        manager.stop()
    }

    func testRestDisplayCountsDown() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())
        manager.confirmEffort()

        manager.totalElapsedTime = 0
        XCTAssertEqual(manager.displayTime, 180, "A rest starts at its full length")

        manager.totalElapsedTime = 20
        XCTAssertEqual(manager.displayTime, 160, "and counts down, not up")

        manager.stop()
    }

    func testConfirmIsIgnoredWhenNotAwaitingUser() {
        let manager = makeManager()
        XCTAssertNil(manager.setSequence)

        manager.confirmEffort() // no sequence at all

        XCTAssertNil(manager.setSequence)
        XCTAssertNotEqual(manager.state, .completed)
    }

    // MARK: - Per-set log seeding

    /// Seeding up front is what makes skipping a set free: an untouched set already
    /// holds its planned reps and the weight carried over from last time.
    func testStartingASequenceSeedsOneLogPerSet() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 4, restBetweenReps: 0, restBetweenSets: 180, seedWeightKg: 30, session: makeSession())

        XCTAssertEqual(manager.effortLogs.count, 4)
        XCTAssertEqual(manager.effortLogs.map(\.reps), [3, 3, 3, 3])
        XCTAssertEqual(manager.effortLogs.map(\.weightKg), [30, 30, 30, 30])
        XCTAssertEqual(manager.seedWeightKg, 30)
        XCTAssertEqual(manager.editingEffortIndex, 0)
        XCTAssertTrue(manager.effortLogs.allSatisfy { $0.rpe == nil && $0.note == nil })
    }

    func testSeedingWithNoHistoryLeavesWeightUnset() {
        let manager = makeManager()
        manager.startSetSequence(reps: 8, sets: 2, restBetweenReps: 0, restBetweenSets: 90, session: makeSession())

        XCTAssertEqual(manager.effortLogs.count, 2)
        XCTAssertTrue(manager.effortLogs.allSatisfy { $0.weightKg == nil })
        XCTAssertNil(manager.seedWeightKg)
    }

    // MARK: - Exercise shape

    /// Omitting `shape` has to keep the old behaviour, or every existing caller and
    /// every test above it changes meaning.
    func testShapeDefaultsToWeighted() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        XCTAssertEqual(manager.setSequence?.shape, .weighted)
        XCTAssertTrue(manager.setSequence?.shape.takesLoad ?? false)
    }

    func testShapeReachesTheSequence() {
        let manager = makeManager()
        manager.startSetSequence(
            reps: 1, sets: 10, restBetweenReps: 0, restBetweenSets: 210, shape: .attempts, session: makeSession()
        )

        let sequence = manager.setSequence
        XCTAssertEqual(sequence?.shape, .attempts)
        XCTAssertFalse(sequence?.shape.takesLoad ?? true, "A limit boulder takes no added load")
        XCTAssertEqual(sequence?.totalSets, 10)
        XCTAssertEqual(sequence?.effortsPerSet, 1, "No rep rest configured, so one effort per set")
    }

    /// The panel hides the stepper for these, so a seeded weight would be a number the
    /// athlete can neither see nor clear.
    func testAnAttemptsSequenceRecordsNoWeight() {
        let manager = makeManager()
        manager.startSetSequence(
            reps: nil, sets: 3, restBetweenReps: 0, restBetweenSets: 180, shape: .attempts, session: makeSession()
        )

        XCTAssertEqual(manager.effortLogs.count, 3)
        XCTAssertTrue(manager.effortLogs.allSatisfy { $0.weightKg == nil })
        XCTAssertTrue(manager.effortLogs.allSatisfy { $0.reps == nil })
    }

    /// A try isn't a rep. An exercise with no rep count must not be given one, or every
    /// chip captions itself "1 reps".
    func testAnEffortWithNoRepCountRecordsNone() {
        let manager = makeManager()
        manager.startSetSequence(reps: nil, sets: 3, restBetweenReps: 0, restBetweenSets: 180,
                                 shape: .attempts, session: makeSession())
        XCTAssertTrue(manager.effortLogs.allSatisfy { $0.reps == nil })

        let counted = makeManager()
        counted.startSetSequence(reps: 5, sets: 3, restBetweenReps: 0, restBetweenSets: 180,
                                 shape: .weighted, session: makeSession())
        XCTAssertEqual(counted.effortLogs.map(\.reps), [5, 5, 5], "A known count is still recorded")
    }

    /// Effort and notes are the books' "quality of the attempt" — the one per-set thing
    /// that still applies when there is no load to record.
    func testAnAttemptsSequenceStillRecordsEffortAndNotes() {
        let manager = makeManager()
        manager.startSetSequence(
            reps: 1, sets: 3, restBetweenReps: 0, restBetweenSets: 180, shape: .attempts, session: makeSession()
        )

        manager.updateSet(at: 0) { $0.rpe = 5; $0.note = "fell at the crux" }

        XCTAssertEqual(manager.effortLogs[0].effortLabel, "Max")
        XCTAssertEqual(manager.effortLogs[0].note, "fell at the crux")
        XCTAssertNil(manager.effortLogs[0].weightKg)
    }

    // MARK: - Overall progress
    //
    // The bar reports the whole exercise, not the current rest. Each set plus the rest
    // that follows it is one equal slice, so with 4 sets the waypoints are 0 / 25 / 50 /
    // 75 / 100 and a rest ramps across one 25-point band.

    func testProgressStartsAtZeroOnTheFirstSetPrompt() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 4, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        XCTAssertEqual(manager.progressPercentage, 0, accuracy: 0.001)
    }

    /// The reported bug: the bar filled up over one 3-minute rest instead of tracking
    /// the exercise.
    func testARestOnlyRampsAcrossItsOwnSlice() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 4, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.confirmEffort()             // set 1 done, rest 1 running
        manager.totalElapsedTime = 90    // halfway through the rest

        XCTAssertEqual(manager.progressPercentage, 0.125, accuracy: 0.001,
                       "Half of the first quarter, not half of everything")

        manager.totalElapsedTime = 180   // rest complete, but not yet advanced
        XCTAssertEqual(manager.progressPercentage, 0.25, accuracy: 0.001)
    }

    func testProgressHitsTheSetWaypoints() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 4, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        // Set 1 + rest 1 → 25%.
        manager.confirmEffort()
        manager.totalElapsedTime = 180
        manager.advanceSetSequence()
        XCTAssertEqual(manager.setSequence?.currentSet, 2)
        XCTAssertEqual(manager.progressPercentage, 0.25, accuracy: 0.001)

        // Set 2 + rest 2 → 50% at the start of set 3.
        manager.confirmEffort()
        manager.totalElapsedTime = 180
        manager.advanceSetSequence()
        XCTAssertEqual(manager.setSequence?.currentSet, 3)
        XCTAssertEqual(manager.progressPercentage, 0.5, accuracy: 0.001)

        // Set 3 + rest 3 → 75%.
        manager.confirmEffort()
        manager.totalElapsedTime = 180
        manager.advanceSetSequence()
        XCTAssertEqual(manager.progressPercentage, 0.75, accuracy: 0.001)

        // Final set has no trailing rest, so confirming it completes the exercise.
        manager.confirmEffort()
        XCTAssertEqual(manager.state, .completed)
        XCTAssertEqual(manager.progressPercentage, 1.0, accuracy: 0.001)
    }

    /// Skipping a rest early still lands on the slice boundary — the slice is a set, not
    /// an amount of elapsed time.
    func testSkippingARestStillLandsOnTheWaypoint() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 4, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.confirmEffort()
        manager.totalElapsedTime = 20   // cut a 3 min rest short
        manager.skipRest()

        XCTAssertEqual(manager.setSequence?.currentSet, 2)
        XCTAssertEqual(manager.progressPercentage, 0.25, accuracy: 0.001)
    }

    func testGoingBackASetMovesProgressBack() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 4, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())
        manager.goToEffort(3)
        XCTAssertEqual(manager.progressPercentage, 0.5, accuracy: 0.001)

        manager.previousEffort()

        XCTAssertEqual(manager.progressPercentage, 0.25, accuracy: 0.001)
    }

    /// A zero-second rest must not divide by zero.
    func testAZeroLengthRestDoesNotBreakProgress() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 2, restBetweenReps: 0, restBetweenSets: 0, session: makeSession())

        manager.confirmEffort()
        let progress = manager.progressPercentage

        XCTAssertFalse(progress.isNaN)
        XCTAssertTrue(progress >= 0 && progress <= 1, "Got \(progress)")
    }

    func testUpdatingASetWritesThrough() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 3, restBetweenReps: 0, restBetweenSets: 180, seedWeightKg: 30, session: makeSession())

        manager.updateSet(at: 1) { $0.weightKg = 32.5; $0.rpe = 4; $0.note = "grip slipped" }

        XCTAssertEqual(manager.effortLogs[1].weightKg, 32.5)
        XCTAssertEqual(manager.effortLogs[1].effortLabel, "Very Hard")
        XCTAssertEqual(manager.effortLogs[1].note, "grip slipped")
        XCTAssertEqual(manager.effortLogs[0].weightKg, 30, "Only the addressed set changes")
    }

    func testUpdatingOutOfRangeIsIgnored() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 2, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.updateSet(at: 9) { $0.weightKg = 999 }

        XCTAssertEqual(manager.effortLogs.count, 2)
        XCTAssertTrue(manager.effortLogs.allSatisfy { $0.weightKg == nil })
    }

    /// The editing cursor is for reviewing a set mid-rest; it must not move the timer.
    func testSelectingASetDoesNotMoveTheTimer() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 4, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.selectEffort(at: 2)

        XCTAssertEqual(manager.editingEffortIndex, 2)
        XCTAssertEqual(manager.setSequence?.currentSet, 1, "Still on set 1")
        XCTAssertEqual(manager.state, .awaitingUser)
    }

    func testSelectingAnOutOfRangeSetIsIgnored() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 2, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.selectEffort(at: 7)

        XCTAssertEqual(manager.editingEffortIndex, 0)
    }

    // MARK: - Set navigation

    /// The chosen skip semantics: jump ahead, and the set you passed keeps its
    /// seeded values so it is still logged.
    func testNextSetFromThePromptSkipsAheadAndKeepsTheSeededValues() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 4, restBetweenReps: 0, restBetweenSets: 180, seedWeightKg: 30, session: makeSession())

        manager.nextEffort()

        XCTAssertEqual(manager.setSequence?.currentSet, 2)
        XCTAssertEqual(manager.state, .awaitingUser, "No rest — the set was skipped, not performed")
        XCTAssertEqual(manager.setSequence?.accumulatedSeconds, 0)
        XCTAssertEqual(manager.effortLogs[0].reps, 3, "The skipped set is still recorded")
        XCTAssertEqual(manager.effortLogs[0].weightKg, 30)
        XCTAssertEqual(manager.editingEffortIndex, 1, "The panel follows the timer")
    }

    func testNextSetOnTheFinalSetFinishes() {
        let manager = makeManager()
        let session = makeSession()
        manager.startSetSequence(reps: 3, sets: 2, restBetweenReps: 0, restBetweenSets: 180, seedWeightKg: 30, session: session)

        manager.nextEffort()   // skip set 1 → set 2
        manager.nextEffort()   // final set → finish

        XCTAssertEqual(manager.state, .completed)
        XCTAssertNil(manager.setSequence)
        XCTAssertTrue(session.wasCompleted)
        XCTAssertEqual(session.completedIntervals, 0,
                       "Both sets were skipped, not done — the sequence ended having logged nothing")
    }

    /// Mid-rest, forward means "stop resting", which is the pre-existing skip.
    func testNextSetDuringARestCutsTheRestShort() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.confirmEffort()
        manager.totalElapsedTime = 120
        manager.nextEffort()

        XCTAssertEqual(manager.state, .awaitingUser)
        XCTAssertEqual(manager.setSequence?.currentSet, 2)
        XCTAssertEqual(manager.setSequence?.accumulatedSeconds, 120,
                       "Only the time actually rested is banked")
    }

    func testPreviousSetGoesBackToCorrectAnEarlierSet() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 4, restBetweenReps: 0, restBetweenSets: 180, seedWeightKg: 30, session: makeSession())

        manager.nextEffort()
        manager.nextEffort()
        XCTAssertEqual(manager.setSequence?.currentSet, 3)

        manager.previousEffort()

        XCTAssertEqual(manager.setSequence?.currentSet, 2)
        XCTAssertEqual(manager.editingEffortIndex, 1)
        XCTAssertEqual(manager.state, .awaitingUser)
    }

    func testPreviousSetOnTheFirstSetDoesNothing() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.previousEffort()

        XCTAssertEqual(manager.setSequence?.currentSet, 1)
        XCTAssertEqual(manager.state, .awaitingUser)
    }

    /// Going backwards must not rewind time already spent resting.
    func testGoingBackwardsMidRestStillBanksTheRestTime() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.confirmEffort()          // resting after set 1
        manager.totalElapsedTime = 45
        manager.previousEffort()         // "I wasn't actually done"

        XCTAssertEqual(manager.setSequence?.accumulatedSeconds, 45)
        XCTAssertEqual(manager.setSequence?.currentSet, 1)
        XCTAssertEqual(manager.state, .awaitingUser)
    }

    func testGoToSetClampsToTheSequence() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.goToEffort(99)
        XCTAssertEqual(manager.setSequence?.currentSet, 3)

        manager.goToEffort(-4)
        XCTAssertEqual(manager.setSequence?.currentSet, 1)
    }

    func testNavigationDoesNothingWithoutASequence() {
        let manager = makeManager()
        manager.nextEffort()
        manager.previousEffort()
        manager.goToEffort(2)
        XCTAssertNil(manager.setSequence)
    }

    // MARK: - Carrying the working weight forward

    /// An exercise with no history seeds every set to no weight, so the weight dialled
    /// in for set 1 is the only one there is. Landing on set 2 with an empty field means
    /// re-entering it every single set.
    func testSkippingARestCarriesTheWeightYouJustLoggedIntoTheNextSet() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 4, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.updateSet(at: 0) { $0.weightKg = 10 }
        manager.confirmEffort()
        manager.totalElapsedTime = 30
        manager.skipRest()

        XCTAssertEqual(manager.effortLogs[1].weightKg, 10)
        XCTAssertEqual(manager.editingEffortIndex, 1)
        XCTAssertEqual(manager.effortLogs[2].weightKg, nil, "Only the set you land on")
    }

    /// Skip and the rest simply running out are the same code path, so a fix that only
    /// covers the button leaves the timeout broken.
    func testARestFinishingNaturallyCarriesTheWeightToo() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 4, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.updateSet(at: 0) { $0.weightKg = 10 }
        manager.confirmEffort()
        manager.advanceSetSequence()

        XCTAssertEqual(manager.effortLogs[1].weightKg, 10)
    }

    /// Dialling set 3 in ahead of time, or going back to correct a set, has to survive
    /// the carry-forward.
    func testCarryForwardLeavesAWeightAlreadyRecordedAlone() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 4, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.updateSet(at: 0) { $0.weightKg = 10 }
        manager.updateSet(at: 1) { $0.weightKg = 20 }
        manager.nextEffort()

        XCTAssertEqual(manager.effortLogs[1].weightKg, 20)

        manager.previousEffort()

        XCTAssertEqual(manager.effortLogs[0].weightKg, 10, "Going back must not rewrite it")
    }

    func testCarryForwardInventsNothingWhenNoWeightHasBeenRecorded() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.nextEffort()

        XCTAssertNil(manager.effortLogs[1].weightKg, "Nothing to carry, so nothing invented")
    }

    /// Reaching a set by tapping its chip has to match reaching it by chevron, or the
    /// same set shows a weight one way and an empty box the other.
    func testTappingAheadToASetCarriesTheWeightForward() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 4, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.updateSet(at: 0) { $0.weightKg = 10 }
        manager.selectEffort(at: 3)

        XCTAssertEqual(manager.effortLogs[3].weightKg, 10)
        XCTAssertEqual(manager.setSequence?.currentSet, 1, "The cursor moved, the timer did not")
    }

    // MARK: - Set status

    func testStatusMarksThePassedSetsDoneAndTheRestUpcoming() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        XCTAssertEqual(manager.effortStatus(at: 0), .current)
        XCTAssertEqual(manager.effortStatus(at: 1), .upcoming)

        manager.nextEffort()   // now on set 2

        XCTAssertEqual(manager.effortStatus(at: 0), .done)
        XCTAssertEqual(manager.effortStatus(at: 1), .current)
        XCTAssertEqual(manager.effortStatus(at: 2), .upcoming)
    }

    /// Once you tap Done and the rest starts, the set you just finished reads done —
    /// even though `currentSet` has not moved yet.
    func testTheCurrentSetReadsDoneWhileRestingAfterIt() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 3, restBetweenReps: 0, restBetweenSets: 180, session: makeSession())

        manager.confirmEffort()

        XCTAssertEqual(manager.setSequence?.currentSet, 1, "Still set 1 during its rest")
        XCTAssertEqual(manager.effortStatus(at: 0), .done)
        XCTAssertEqual(manager.effortStatus(at: 1), .upcoming)

        manager.stop()
    }

    // MARK: - Log lifetime

    /// The log sheet reads `effortLogs` after completion, so finishing must not clear it.
    func testFinishingASequenceLeavesTheLogReadable() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 1, restBetweenReps: 0, restBetweenSets: 180, seedWeightKg: 30, session: makeSession())

        manager.updateSet(at: 0) { $0.rpe = 5 }
        manager.confirmEffort()

        XCTAssertEqual(manager.state, .completed)
        XCTAssertNil(manager.setSequence, "The sequence is over")
        XCTAssertEqual(manager.effortLogs.count, 1, "but its log is what gets offered to the log form")
        XCTAssertEqual(manager.effortLogs[0].rpe, 5)
    }

    func testStoppingClearsTheLog() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 3, restBetweenReps: 0, restBetweenSets: 180, seedWeightKg: 30, session: makeSession())

        manager.stop()

        XCTAssertTrue(manager.effortLogs.isEmpty, "An abandoned workout has nothing to log")
        XCTAssertNil(manager.seedWeightKg)
    }
}
