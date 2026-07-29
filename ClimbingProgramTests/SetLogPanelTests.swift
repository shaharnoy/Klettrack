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
}
