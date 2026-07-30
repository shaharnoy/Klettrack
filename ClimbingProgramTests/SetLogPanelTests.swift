//
//  SetLogPanelTests.swift
//  klettrack Tests
//

import XCTest
@testable import klettrack

final class SetLogPanelTests: XCTestCase {

    /// The spec's canonical rep rest is 30 seconds. Dividing by 60 used to announce
    /// "0 minute rest" to VoiceOver — sub-minute rests must read in seconds.
    func testRestPhraseUsesSecondsBelowAMinute() {
        XCTAssertEqual(SetLogPanel.restPhrase(seconds: 30), "30 second")
        XCTAssertEqual(SetLogPanel.restPhrase(seconds: 45), "45 second")
    }

    /// A minute or longer still reads in minutes, as it always did.
    func testRestPhraseUsesMinutesAtOrAboveAMinute() {
        XCTAssertEqual(SetLogPanel.restPhrase(seconds: 60), "1 minute")
        XCTAssertEqual(SetLogPanel.restPhrase(seconds: 180), "3 minute")
    }

    // MARK: - The Reps card

    @MainActor
    private func panel(
        reps: Int?, sets: Int, restBetweenReps: Int, shape: ExerciseShape
    ) -> SetLogPanel {
        let manager = TimerManager()
        manager.startSetSequence(
            reps: reps, sets: sets, restBetweenReps: restBetweenReps, restBetweenSets: 180,
            shape: shape
        )
        return SetLogPanel(timerManager: manager, sequence: manager.setSequence!)
    }

    /// Nested, a rep is an effort the timer counts through, so the card tracks a real
    /// position and reads as the fraction the interval timer shows.
    @MainActor
    func testNestedRepsCardTracksThePositionWithinTheSet() {
        let target = panel(reps: 7, sets: 4, restBetweenReps: 30, shape: .attempts).repsTarget
        XCTAssertEqual(target?.current, 1)
        XCTAssertEqual(target?.total, 7)
        XCTAssertNil(target?.detail, "A counted rep reads as a fraction, not a bare target")
    }

    /// Flat, the whole set is one effort — the rep count is the prescription. A fraction
    /// there would claim progress through reps nobody is timing, so it reads as "6".
    @MainActor
    func testFlatRepsCardReadsAsABareTarget() {
        let target = panel(reps: 6, sets: 4, restBetweenReps: 0, shape: .weighted).repsTarget
        XCTAssertEqual(target?.detail, "6")
        XCTAssertEqual(target?.current, target?.total, "A target fills its bar")
    }

    /// A try isn't a rep. With no count to show, the card is left out rather than invented.
    @MainActor
    func testAttemptsWithNoRepCountGetNoRepsCard() {
        XCTAssertNil(panel(reps: nil, sets: 4, restBetweenReps: 0, shape: .attempts).repsTarget)
    }
}
