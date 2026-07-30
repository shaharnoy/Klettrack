//
//  UserDecimalTests.swift
//  klettrack Tests
//

import XCTest
@testable import klettrack

final class UserDecimalTests: XCTestCase {

    // MARK: - Parsing what the user typed

    func testParsesAPlainDecimalPoint() {
        XCTAssertEqual(userDecimal("32.5"), 32.5)
        XCTAssertEqual(userDecimal("30"), 30)
        XCTAssertEqual(userDecimal("0"), 0)
    }

    /// A decimal pad emits the locale's separator, and most of Europe types a comma.
    /// `Double("32,5")` is nil, so without the substitution the weight silently
    /// wouldn't update for those users.
    func testParsesACommaAsTheDecimalSeparator() {
        XCTAssertEqual(userDecimal("32,5"), 32.5)
        XCTAssertEqual(userDecimal("0,5"), 0.5)
    }

    func testToleratesSurroundingWhitespace() {
        XCTAssertEqual(userDecimal("  47,5 "), 47.5)
    }

    /// A half-typed field must read as "no value yet", not as zero, so the caller can
    /// leave the recorded weight alone.
    func testReturnsNilForAnEmptyOrUnparseableField() {
        XCTAssertNil(userDecimal(""))
        XCTAssertNil(userDecimal("   "))
        XCTAssertNil(userDecimal("abc"))
        XCTAssertNil(userDecimal("-"))
    }

    /// Swift reads a trailing separator fine, which matters mid-typing: "32," must not
    /// wipe the value the user is halfway through changing.
    func testParsesATrailingSeparatorMidTyping() {
        XCTAssertEqual(userDecimal("32."), 32)
        XCTAssertEqual(userDecimal("32,"), 32)
    }

    // MARK: - Rendering back into the field

    func testWholeNumbersRenderWithoutATrailingZero() {
        XCTAssertEqual(decimalText(30), "30")
        XCTAssertEqual(decimalText(0), "0")
    }

    func testNilRendersBlankSoThePlaceholderShows() {
        XCTAssertEqual(decimalText(nil), "")
    }

    /// The round trip is the real contract: whatever is shown must parse back to the
    /// number it came from, in this device's locale.
    func testRenderedTextParsesBackToTheSameNumber() {
        for value in [0, 2.5, 30, 32.5, 47.5, 100.25] as [Double] {
            XCTAssertEqual(
                userDecimal(decimalText(value)), value,
                "\(value) rendered as \(decimalText(value)) must parse back"
            )
        }
    }

    /// A grouping separator would be ambiguous with the decimal one in a comma locale.
    func testLargeValuesCarryNoGroupingSeparator() {
        let text = decimalText(1234.5)
        XCTAssertFalse(text.contains(" "), "No space grouping: \(text)")
        XCTAssertEqual(userDecimal(text), 1234.5)
    }
}
