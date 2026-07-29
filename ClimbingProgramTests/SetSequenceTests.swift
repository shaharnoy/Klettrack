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

    // MARK: - Delivering less than the prescription

    /// The plan asks for five sets, you had three in you. Only the three reach the log.
    func testFinishingEarlyLogsOnlyTheSetsActuallyConfirmed() {
        let manager = makeManager()
        let session = makeSession()
        manager.startSetSequence(reps: 5, sets: 5, restSeconds: 180, session: session)

        for _ in 1...3 {
            manager.confirmSet()
            manager.totalElapsedTime = 180
            manager.advanceSetSequence()
        }

        XCTAssertEqual(manager.setLogs.count, 5, "All five are laid out, so you can skip ahead")
        XCTAssertEqual(manager.performedSetCount, 3)
        XCTAssertEqual(manager.performedSetLogs.count, 3, "Only what was confirmed is logged")

        manager.finishSetSequence()

        XCTAssertEqual(manager.state, .completed)
        XCTAssertEqual(session.completedIntervals, 3, "What was done, not what was asked")
        XCTAssertTrue(session.wasCompleted, "Stopping short is a training decision, not an abort")
        XCTAssertEqual(manager.performedSetLogs.count, 3, "The log survives completion")
    }

    /// Skipping with the chevron is not doing the set.
    func testSkippingASetDoesNotCountItAsPerformed() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 4, restSeconds: 180, session: makeSession())

        manager.confirmSet()          // set 1 done
        manager.totalElapsedTime = 180
        manager.advanceSetSequence()  // now on set 2
        manager.nextSet()             // skip set 2 without doing it

        XCTAssertEqual(manager.setSequence?.currentSet, 3)
        XCTAssertEqual(manager.performedSetCount, 1)
        XCTAssertEqual(manager.performedSetLogs.count, 1)
    }

    /// Going back to correct set 2 of 4 must not retract sets 3 and 4.
    func testSteppingBackKeepsTheHighWaterMark() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 4, restSeconds: 60, session: makeSession())

        for _ in 1...3 {
            manager.confirmSet()
            manager.advanceSetSequence()
        }
        XCTAssertEqual(manager.performedSetCount, 3)

        manager.previousSet()
        manager.previousSet()

        XCTAssertEqual(manager.setSequence?.currentSet, 2)
        XCTAssertEqual(manager.performedSetCount, 3, "Reviewing a set doesn't undo later ones")
    }

    func testNothingIsLoggedBeforeTheFirstDone() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 3, restSeconds: 180, session: makeSession())

        XCTAssertEqual(manager.setLogs.count, 3)
        XCTAssertEqual(manager.performedSetCount, 0)
        XCTAssertTrue(manager.performedSetLogs.isEmpty)
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

    // MARK: - Per-set log seeding

    /// Seeding up front is what makes skipping a set free: an untouched set already
    /// holds its planned reps and the weight carried over from last time.
    func testStartingASequenceSeedsOneLogPerSet() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 4, restSeconds: 180, seedWeightKg: 30, session: makeSession())

        XCTAssertEqual(manager.setLogs.count, 4)
        XCTAssertEqual(manager.setLogs.map(\.reps), [3, 3, 3, 3])
        XCTAssertEqual(manager.setLogs.map(\.weightKg), [30, 30, 30, 30])
        XCTAssertEqual(manager.seedWeightKg, 30)
        XCTAssertEqual(manager.editingSetIndex, 0)
        XCTAssertTrue(manager.setLogs.allSatisfy { $0.rpe == nil && $0.note == nil })
    }

    func testSeedingWithNoHistoryLeavesWeightUnset() {
        let manager = makeManager()
        manager.startSetSequence(reps: 8, sets: 2, restSeconds: 90, session: makeSession())

        XCTAssertEqual(manager.setLogs.count, 2)
        XCTAssertTrue(manager.setLogs.allSatisfy { $0.weightKg == nil })
        XCTAssertNil(manager.seedWeightKg)
    }

    // MARK: - Exercise shape

    /// Omitting `shape` has to keep the old behaviour, or every existing caller and
    /// every test above it changes meaning.
    func testShapeDefaultsToWeighted() {
        let manager = makeManager()
        manager.startSetSequence(reps: 5, sets: 3, restSeconds: 180, session: makeSession())

        XCTAssertEqual(manager.setSequence?.shape, .weighted)
        XCTAssertTrue(manager.setSequence?.shape.takesLoad ?? false)
    }

    func testShapeReachesTheSequence() {
        let manager = makeManager()
        manager.startSetSequence(
            reps: nil, sets: 10, restSeconds: 210, shape: .attempts, session: makeSession()
        )

        let sequence = manager.setSequence
        XCTAssertEqual(sequence?.shape, .attempts)
        XCTAssertFalse(sequence?.shape.takesLoad ?? true, "A limit boulder takes no added load")
        XCTAssertEqual(sequence?.totalSets, 10)
        XCTAssertEqual(sequence?.repsPerSet, nil, "Attempts aren't reps")
    }

    /// The panel hides the stepper for these, so a seeded weight would be a number the
    /// athlete can neither see nor clear.
    func testAnAttemptsSequenceRecordsNoWeight() {
        let manager = makeManager()
        manager.startSetSequence(
            reps: nil, sets: 3, restSeconds: 180, shape: .attempts, session: makeSession()
        )

        XCTAssertEqual(manager.setLogs.count, 3)
        XCTAssertTrue(manager.setLogs.allSatisfy { $0.weightKg == nil })
        XCTAssertTrue(manager.setLogs.allSatisfy { $0.reps == nil })
    }

    /// Effort and notes are the books' "quality of the attempt" — the one per-set thing
    /// that still applies when there is no load to record.
    func testAnAttemptsSequenceStillRecordsEffortAndNotes() {
        let manager = makeManager()
        manager.startSetSequence(
            reps: nil, sets: 3, restSeconds: 180, shape: .attempts, session: makeSession()
        )

        manager.updateSet(at: 0) { $0.rpe = 5; $0.note = "fell at the crux" }

        XCTAssertEqual(manager.setLogs[0].effortLabel, "Max")
        XCTAssertEqual(manager.setLogs[0].note, "fell at the crux")
        XCTAssertNil(manager.setLogs[0].weightKg)
    }

    // MARK: - Overall progress
    //
    // The bar reports the whole exercise, not the current rest. Each set plus the rest
    // that follows it is one equal slice, so with 4 sets the waypoints are 0 / 25 / 50 /
    // 75 / 100 and a rest ramps across one 25-point band.

    func testProgressStartsAtZeroOnTheFirstSetPrompt() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 4, restSeconds: 180, session: makeSession())

        XCTAssertEqual(manager.progressPercentage, 0, accuracy: 0.001)
    }

    /// The reported bug: the bar filled up over one 3-minute rest instead of tracking
    /// the exercise.
    func testARestOnlyRampsAcrossItsOwnSlice() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 4, restSeconds: 180, session: makeSession())

        manager.confirmSet()             // set 1 done, rest 1 running
        manager.totalElapsedTime = 90    // halfway through the rest

        XCTAssertEqual(manager.progressPercentage, 0.125, accuracy: 0.001,
                       "Half of the first quarter, not half of everything")

        manager.totalElapsedTime = 180   // rest complete, but not yet advanced
        XCTAssertEqual(manager.progressPercentage, 0.25, accuracy: 0.001)
    }

    func testProgressHitsTheSetWaypoints() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 4, restSeconds: 180, session: makeSession())

        // Set 1 + rest 1 → 25%.
        manager.confirmSet()
        manager.totalElapsedTime = 180
        manager.advanceSetSequence()
        XCTAssertEqual(manager.setSequence?.currentSet, 2)
        XCTAssertEqual(manager.progressPercentage, 0.25, accuracy: 0.001)

        // Set 2 + rest 2 → 50% at the start of set 3.
        manager.confirmSet()
        manager.totalElapsedTime = 180
        manager.advanceSetSequence()
        XCTAssertEqual(manager.setSequence?.currentSet, 3)
        XCTAssertEqual(manager.progressPercentage, 0.5, accuracy: 0.001)

        // Set 3 + rest 3 → 75%.
        manager.confirmSet()
        manager.totalElapsedTime = 180
        manager.advanceSetSequence()
        XCTAssertEqual(manager.progressPercentage, 0.75, accuracy: 0.001)

        // Final set has no trailing rest, so confirming it completes the exercise.
        manager.confirmSet()
        XCTAssertEqual(manager.state, .completed)
        XCTAssertEqual(manager.progressPercentage, 1.0, accuracy: 0.001)
    }

    /// Skipping a rest early still lands on the slice boundary — the slice is a set, not
    /// an amount of elapsed time.
    func testSkippingARestStillLandsOnTheWaypoint() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 4, restSeconds: 180, session: makeSession())

        manager.confirmSet()
        manager.totalElapsedTime = 20   // cut a 3 min rest short
        manager.skipRest()

        XCTAssertEqual(manager.setSequence?.currentSet, 2)
        XCTAssertEqual(manager.progressPercentage, 0.25, accuracy: 0.001)
    }

    func testGoingBackASetMovesProgressBack() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 4, restSeconds: 180, session: makeSession())
        manager.goToSet(3)
        XCTAssertEqual(manager.progressPercentage, 0.5, accuracy: 0.001)

        manager.previousSet()

        XCTAssertEqual(manager.progressPercentage, 0.25, accuracy: 0.001)
    }

    /// Adding a try re-slices the exercise: 2 of 3 done is less far along than 2 of 2.
    func testAddingASetRescalesProgress() {
        let manager = makeManager()
        manager.startSetSequence(
            reps: nil, sets: 2, restSeconds: 180, shape: .attempts, session: makeSession()
        )
        manager.goToSet(2)
        XCTAssertEqual(manager.progressPercentage, 0.5, accuracy: 0.001)

        manager.addSet()

        XCTAssertEqual(manager.progressPercentage, 1.0 / 3.0, accuracy: 0.001)
    }

    /// A zero-second rest must not divide by zero.
    func testAZeroLengthRestDoesNotBreakProgress() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 2, restSeconds: 0, session: makeSession())

        manager.confirmSet()
        let progress = manager.progressPercentage

        XCTAssertFalse(progress.isNaN)
        XCTAssertTrue(progress >= 0 && progress <= 1, "Got \(progress)")
    }

    // MARK: - addSet

    func testAddSetExtendsThePlanAndAppendsOneLog() {
        let manager = makeManager()
        manager.startSetSequence(
            reps: nil, sets: 3, restSeconds: 180, shape: .attempts, session: makeSession()
        )

        manager.addSet()

        XCTAssertEqual(manager.setSequence?.totalSets, 4)
        XCTAssertEqual(manager.setLogs.count, 4)
        XCTAssertNil(manager.setLogs[3].weightKg)
        XCTAssertNil(manager.setLogs[3].reps)
    }

    /// The whole point: on the final try, one more tap has to be possible instead of
    /// `nextSet` ending the session.
    func testAddSetOnTheFinalTryKeepsTheSessionGoing() {
        let manager = makeManager()
        manager.startSetSequence(
            reps: nil, sets: 2, restSeconds: 180, shape: .attempts, session: makeSession()
        )
        manager.goToSet(2)
        XCTAssertTrue(manager.setSequence?.isFinalSet ?? false)

        manager.addSet()

        XCTAssertFalse(manager.setSequence?.isFinalSet ?? true, "Try 2 of 3 is not the last")
        manager.nextSet()
        XCTAssertEqual(manager.setSequence?.currentSet, 3)
        XCTAssertNotEqual(manager.state, .completed)
    }

    func testAddSetDoesNotMoveTheCurrentSetOrTheClock() {
        let manager = makeManager()
        manager.startSetSequence(
            reps: nil, sets: 3, restSeconds: 180, shape: .attempts, session: makeSession()
        )
        manager.goToSet(2)

        manager.addSet()

        XCTAssertEqual(manager.setSequence?.currentSet, 2, "Adding room is not advancing")
        XCTAssertEqual(manager.state, .awaitingUser)
        XCTAssertEqual(manager.editingSetIndex, 1)
    }

    func testAddSetIsANoOpWithoutASequence() {
        let manager = makeManager()

        manager.addSet()

        XCTAssertNil(manager.setSequence)
        XCTAssertTrue(manager.setLogs.isEmpty)
    }

    /// Finishing clears the sequence but deliberately keeps `setLogs` — the completion
    /// sheet reads them. A late `addSet` must not append a phantom try to that record.
    func testAddSetIsANoOpOnceCompleted() {
        let manager = makeManager()
        manager.startSetSequence(
            reps: nil, sets: 1, restSeconds: 180, shape: .attempts, session: makeSession()
        )
        manager.confirmSet()   // final try → finishes
        XCTAssertEqual(manager.state, .completed)
        XCTAssertNil(manager.setSequence, "finishSetSequence clears the sequence")
        let logsAtFinish = manager.setLogs.count

        manager.addSet()

        XCTAssertEqual(manager.setLogs.count, logsAtFinish)
        XCTAssertNil(manager.setSequence)
    }

    /// A weighted sequence carries its seed forward, so an added set starts where the
    /// others did rather than empty.
    func testAddSetCarriesTheSeedWeightOnAWeightedSequence() {
        let manager = makeManager()
        manager.startSetSequence(
            reps: 3, sets: 2, restSeconds: 180, seedWeightKg: 30, session: makeSession()
        )

        manager.addSet()

        XCTAssertEqual(manager.setLogs.count, 3)
        XCTAssertEqual(manager.setLogs[2].weightKg, 30)
        XCTAssertEqual(manager.setLogs[2].reps, 3)
    }

    func testUpdatingASetWritesThrough() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 3, restSeconds: 180, seedWeightKg: 30, session: makeSession())

        manager.updateSet(at: 1) { $0.weightKg = 32.5; $0.rpe = 4; $0.note = "grip slipped" }

        XCTAssertEqual(manager.setLogs[1].weightKg, 32.5)
        XCTAssertEqual(manager.setLogs[1].effortLabel, "Very Hard")
        XCTAssertEqual(manager.setLogs[1].note, "grip slipped")
        XCTAssertEqual(manager.setLogs[0].weightKg, 30, "Only the addressed set changes")
    }

    func testUpdatingOutOfRangeIsIgnored() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 2, restSeconds: 180, session: makeSession())

        manager.updateSet(at: 9) { $0.weightKg = 999 }

        XCTAssertEqual(manager.setLogs.count, 2)
        XCTAssertTrue(manager.setLogs.allSatisfy { $0.weightKg == nil })
    }

    /// The editing cursor is for reviewing a set mid-rest; it must not move the timer.
    func testSelectingASetDoesNotMoveTheTimer() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 4, restSeconds: 180, session: makeSession())

        manager.selectSet(at: 2)

        XCTAssertEqual(manager.editingSetIndex, 2)
        XCTAssertEqual(manager.setSequence?.currentSet, 1, "Still on set 1")
        XCTAssertEqual(manager.state, .awaitingUser)
    }

    func testSelectingAnOutOfRangeSetIsIgnored() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 2, restSeconds: 180, session: makeSession())

        manager.selectSet(at: 7)

        XCTAssertEqual(manager.editingSetIndex, 0)
    }

    // MARK: - Set navigation

    /// The chosen skip semantics: jump ahead, and the set you passed keeps its
    /// seeded values so it is still logged.
    func testNextSetFromThePromptSkipsAheadAndKeepsTheSeededValues() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 4, restSeconds: 180, seedWeightKg: 30, session: makeSession())

        manager.nextSet()

        XCTAssertEqual(manager.setSequence?.currentSet, 2)
        XCTAssertEqual(manager.state, .awaitingUser, "No rest — the set was skipped, not performed")
        XCTAssertEqual(manager.setSequence?.accumulatedSeconds, 0)
        XCTAssertEqual(manager.setLogs[0].reps, 3, "The skipped set is still recorded")
        XCTAssertEqual(manager.setLogs[0].weightKg, 30)
        XCTAssertEqual(manager.editingSetIndex, 1, "The panel follows the timer")
    }

    func testNextSetOnTheFinalSetFinishes() {
        let manager = makeManager()
        let session = makeSession()
        manager.startSetSequence(reps: 3, sets: 2, restSeconds: 180, seedWeightKg: 30, session: session)

        manager.nextSet()   // skip set 1 → set 2
        manager.nextSet()   // final set → finish

        XCTAssertEqual(manager.state, .completed)
        XCTAssertNil(manager.setSequence)
        XCTAssertTrue(session.wasCompleted)
        XCTAssertEqual(session.completedIntervals, 0,
                       "Both sets were skipped, not done — the sequence ended having logged nothing")
    }

    /// Mid-rest, forward means "stop resting", which is the pre-existing skip.
    func testNextSetDuringARestCutsTheRestShort() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 3, restSeconds: 180, session: makeSession())

        manager.confirmSet()
        manager.totalElapsedTime = 120
        manager.nextSet()

        XCTAssertEqual(manager.state, .awaitingUser)
        XCTAssertEqual(manager.setSequence?.currentSet, 2)
        XCTAssertEqual(manager.setSequence?.accumulatedSeconds, 120,
                       "Only the time actually rested is banked")
    }

    func testPreviousSetGoesBackToCorrectAnEarlierSet() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 4, restSeconds: 180, seedWeightKg: 30, session: makeSession())

        manager.nextSet()
        manager.nextSet()
        XCTAssertEqual(manager.setSequence?.currentSet, 3)

        manager.previousSet()

        XCTAssertEqual(manager.setSequence?.currentSet, 2)
        XCTAssertEqual(manager.editingSetIndex, 1)
        XCTAssertEqual(manager.state, .awaitingUser)
    }

    func testPreviousSetOnTheFirstSetDoesNothing() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 3, restSeconds: 180, session: makeSession())

        manager.previousSet()

        XCTAssertEqual(manager.setSequence?.currentSet, 1)
        XCTAssertEqual(manager.state, .awaitingUser)
    }

    /// Going backwards must not rewind time already spent resting.
    func testGoingBackwardsMidRestStillBanksTheRestTime() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 3, restSeconds: 180, session: makeSession())

        manager.confirmSet()          // resting after set 1
        manager.totalElapsedTime = 45
        manager.previousSet()         // "I wasn't actually done"

        XCTAssertEqual(manager.setSequence?.accumulatedSeconds, 45)
        XCTAssertEqual(manager.setSequence?.currentSet, 1)
        XCTAssertEqual(manager.state, .awaitingUser)
    }

    func testGoToSetClampsToTheSequence() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 3, restSeconds: 180, session: makeSession())

        manager.goToSet(99)
        XCTAssertEqual(manager.setSequence?.currentSet, 3)

        manager.goToSet(-4)
        XCTAssertEqual(manager.setSequence?.currentSet, 1)
    }

    func testNavigationDoesNothingWithoutASequence() {
        let manager = makeManager()
        manager.nextSet()
        manager.previousSet()
        manager.goToSet(2)
        XCTAssertNil(manager.setSequence)
    }

    // MARK: - Carrying the working weight forward

    /// An exercise with no history seeds every set to no weight, so the weight dialled
    /// in for set 1 is the only one there is. Landing on set 2 with an empty field means
    /// re-entering it every single set.
    func testSkippingARestCarriesTheWeightYouJustLoggedIntoTheNextSet() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 4, restSeconds: 180, session: makeSession())

        manager.updateSet(at: 0) { $0.weightKg = 10 }
        manager.confirmSet()
        manager.totalElapsedTime = 30
        manager.skipRest()

        XCTAssertEqual(manager.setLogs[1].weightKg, 10)
        XCTAssertEqual(manager.editingSetIndex, 1)
        XCTAssertEqual(manager.setLogs[2].weightKg, nil, "Only the set you land on")
    }

    /// Skip and the rest simply running out are the same code path, so a fix that only
    /// covers the button leaves the timeout broken.
    func testARestFinishingNaturallyCarriesTheWeightToo() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 4, restSeconds: 180, session: makeSession())

        manager.updateSet(at: 0) { $0.weightKg = 10 }
        manager.confirmSet()
        manager.advanceSetSequence()

        XCTAssertEqual(manager.setLogs[1].weightKg, 10)
    }

    /// Dialling set 3 in ahead of time, or going back to correct a set, has to survive
    /// the carry-forward.
    func testCarryForwardLeavesAWeightAlreadyRecordedAlone() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 4, restSeconds: 180, session: makeSession())

        manager.updateSet(at: 0) { $0.weightKg = 10 }
        manager.updateSet(at: 1) { $0.weightKg = 20 }
        manager.nextSet()

        XCTAssertEqual(manager.setLogs[1].weightKg, 20)

        manager.previousSet()

        XCTAssertEqual(manager.setLogs[0].weightKg, 10, "Going back must not rewrite it")
    }

    func testCarryForwardInventsNothingWhenNoWeightHasBeenRecorded() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 3, restSeconds: 180, session: makeSession())

        manager.nextSet()

        XCTAssertNil(manager.setLogs[1].weightKg, "Nothing to carry, so nothing invented")
    }

    /// Reaching a set by tapping its chip has to match reaching it by chevron, or the
    /// same set shows a weight one way and an empty box the other.
    func testTappingAheadToASetCarriesTheWeightForward() {
        let manager = makeManager()
        manager.startSetSequence(reps: 6, sets: 4, restSeconds: 180, session: makeSession())

        manager.updateSet(at: 0) { $0.weightKg = 10 }
        manager.selectSet(at: 3)

        XCTAssertEqual(manager.setLogs[3].weightKg, 10)
        XCTAssertEqual(manager.setSequence?.currentSet, 1, "The cursor moved, the timer did not")
    }

    // MARK: - Set status

    func testStatusMarksThePassedSetsDoneAndTheRestUpcoming() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 3, restSeconds: 180, session: makeSession())

        XCTAssertEqual(manager.setStatus(at: 0), .current)
        XCTAssertEqual(manager.setStatus(at: 1), .upcoming)

        manager.nextSet()   // now on set 2

        XCTAssertEqual(manager.setStatus(at: 0), .done)
        XCTAssertEqual(manager.setStatus(at: 1), .current)
        XCTAssertEqual(manager.setStatus(at: 2), .upcoming)
    }

    /// Once you tap Done and the rest starts, the set you just finished reads done —
    /// even though `currentSet` has not moved yet.
    func testTheCurrentSetReadsDoneWhileRestingAfterIt() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 3, restSeconds: 180, session: makeSession())

        manager.confirmSet()

        XCTAssertEqual(manager.setSequence?.currentSet, 1, "Still set 1 during its rest")
        XCTAssertEqual(manager.setStatus(at: 0), .done)
        XCTAssertEqual(manager.setStatus(at: 1), .upcoming)

        manager.stop()
    }

    // MARK: - Log lifetime

    /// The log sheet reads `setLogs` after completion, so finishing must not clear it.
    func testFinishingASequenceLeavesTheLogReadable() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 1, restSeconds: 180, seedWeightKg: 30, session: makeSession())

        manager.updateSet(at: 0) { $0.rpe = 5 }
        manager.confirmSet()

        XCTAssertEqual(manager.state, .completed)
        XCTAssertNil(manager.setSequence, "The sequence is over")
        XCTAssertEqual(manager.setLogs.count, 1, "but its log is what gets offered to the log form")
        XCTAssertEqual(manager.setLogs[0].rpe, 5)
    }

    func testStoppingClearsTheLog() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 3, restSeconds: 180, seedWeightKg: 30, session: makeSession())

        manager.stop()

        XCTAssertTrue(manager.setLogs.isEmpty, "An abandoned workout has nothing to log")
        XCTAssertNil(manager.seedWeightKg)
    }
}
