import Foundation
import XCTest

@testable import klettrack

final class BoardDateParserTests: XCTestCase {
    func testTensionZoneLessTimestampUsesTheClimberTimezone() throws {
        let berlin = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))

        let date = try XCTUnwrap(
            BoardDateParser.parseTensionClimbedAt(
                "2026-06-02 22:02:00.000000",
                timeZone: berlin
            )
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 2)
        XCTAssertEqual(components.hour, 22)
        XCTAssertEqual(components.minute, 2)
    }

    func testTensionTimestampWithUTCOffsetPreservesItsAbsoluteInstant() throws {
        let berlin = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let expected = try XCTUnwrap(BoardDateParser.parse("2026-06-02T20:02:00Z"))
        let actual = try XCTUnwrap(
            BoardDateParser.parseTensionClimbedAt(
                "2026-06-02T20:02:00Z",
                timeZone: berlin
            )
        )

        XCTAssertEqual(actual, expected)
    }
}
