import XCTest
import SwiftData
@testable import klettrack

@MainActor
final class DayDetailExerciseLogFlowTests: BaseSwiftDataTestCase {
    func testEmptyDayCreatesSessionForSelectedDate() throws {
        let selectedDate = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 20))
        )

        let preparation = try DayDetailExerciseLogFlow.prepare(
            existingSession: nil,
            date: selectedDate,
            in: context
        )

        let sessions = try context.fetch(FetchDescriptor<Session>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(preparation.persistedSession.id, sessions[0].id)
        XCTAssertEqual(
            Calendar.current.startOfDay(for: preparation.persistedSession.date),
            Calendar.current.startOfDay(for: selectedDate)
        )
    }

    func testExistingEmptySessionIsUsedByExerciseSheet() throws {
        let existingSession = createTestSession()

        let preparation = try DayDetailExerciseLogFlow.prepare(
            existingSession: existingSession,
            date: existingSession.date,
            in: context
        )

        XCTAssertEqual(preparation.sessionForSheet.id, existingSession.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Session>()).count, 1)
    }

    func testEmptyDayProvidesCreatedSessionToExerciseSheet() throws {
        let selectedDate = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 20))
        )

        let preparation = try DayDetailExerciseLogFlow.prepare(
            existingSession: nil,
            date: selectedDate,
            in: context
        )

        XCTAssertEqual(
            preparation.sessionForSheet.id,
            preparation.persistedSession.id,
            "Logging an exercise on an empty day must present AddSessionItemSheet with the newly created session."
        )
    }
}
