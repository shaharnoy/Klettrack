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
