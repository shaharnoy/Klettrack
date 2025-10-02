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
}
