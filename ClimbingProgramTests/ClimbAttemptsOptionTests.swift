import XCTest
@testable import klettrack

final class ClimbAttemptsOptionTests: XCTestCase {
    func testStandardPickerOptionsHaveRequestedOrder() {
        XCTAssertEqual(
            ClimbAttemptsOption.standardOptions.map(\.displayName),
            ["Flash"] + (2...15).map(String.init) + ["None"]
        )
    }

    func testStatisticsMapping() {
        XCTAssertEqual(ClimbAttemptsOption.statisticsCount(forStoredValue: "Flash"), 1)
        XCTAssertEqual(ClimbAttemptsOption.statisticsCount(forStoredValue: "2"), 2)
        XCTAssertEqual(ClimbAttemptsOption.statisticsCount(forStoredValue: "15"), 15)
        XCTAssertEqual(ClimbAttemptsOption.statisticsCount(forStoredValue: "None"), 0)
    }

    func testLegacyNumericValuesRemainReadable() {
        let legacy = ClimbAttemptsOption.fromStoredValue("20")

        XCTAssertEqual(legacy.displayName, "20")
        XCTAssertEqual(legacy.storedValue, "20")
        XCTAssertEqual(legacy.statisticsCount, 20)
    }

    func testLegacyOneAndZeroMapToNewSemanticOptions() {
        XCTAssertEqual(ClimbAttemptsOption.fromStoredValue("1"), .flash)
        XCTAssertEqual(ClimbAttemptsOption.fromStoredValue("0"), .none)
    }
}
