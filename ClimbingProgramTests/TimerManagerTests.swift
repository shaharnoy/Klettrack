import XCTest
@testable import klettrack

@MainActor
final class TimerManagerTests: XCTestCase {
    func testRestartClearsDurationTimerLapBaseline() {
        let manager = TimerManager()
        manager.loadConfiguration(TimerConfiguration(totalTimeSeconds: 120))

        // Simulate a completed duration timer after a lap was recorded.
        manager.totalElapsedTime = 120
        manager.addLap()
        XCTAssertEqual(manager.displayTime, 0)

        manager.restart()

        XCTAssertEqual(manager.totalElapsedTime, 0)
        XCTAssertEqual(manager.displayTime, 0)
        XCTAssertGreaterThanOrEqual(manager.displayTime, 0)
    }
}
