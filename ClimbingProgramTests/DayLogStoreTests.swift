import XCTest
import SwiftData
@testable import klettrack

@MainActor
final class DayLogStoreTests: BaseSwiftDataTestCase {
    func testFetchOrCreateNormalizesToOneDayLogPerDate() throws {
        let calendar = Calendar.current
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 27, hour: 9)))
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 27, hour: 20)))

        let first = try XCTUnwrap(DayLogStore.dayLog(for: morning, in: context))
        let second = try XCTUnwrap(DayLogStore.dayLog(for: evening, in: context))

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.date, calendar.startOfDay(for: morning))
    }

    func testSetNoteTrimsEmptyValuesToNil() throws {
        let dayLog = try XCTUnwrap(DayLogStore.dayLog(for: Date(), in: context))

        DayLogStore.setNote("  Good session  ", for: dayLog)
        XCTAssertEqual(dayLog.note, "Good session")

        DayLogStore.setNote("   \n ", for: dayLog)
        XCTAssertNil(dayLog.note)
    }

    func testCreateTagPreventsDuplicateActiveNames() throws {
        let first = try XCTUnwrap(DayLogStore.createTag(name: " Projecting ", colorKey: "red", in: context))
        let second = try XCTUnwrap(DayLogStore.createTag(name: "projecting", colorKey: "blue", in: context))

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.name, "Projecting")
        XCTAssertEqual(first.colorKey, "red")
    }

    func testAssignAndHideTagRemovesItFromDayLog() throws {
        let dayLog = try XCTUnwrap(DayLogStore.dayLog(for: Date(), in: context))
        let tag = try XCTUnwrap(DayLogStore.createTag(name: "Volume", colorKey: "green", in: context))

        DayLogStore.setTag(tag, assigned: true, to: dayLog)
        XCTAssertEqual(DayLogStore.activeTags(from: dayLog).map(\.id), [tag.id])

        DayLogStore.hideTag(tag, in: context)
        XCTAssertTrue(tag.isHidden)
        XCTAssertTrue(DayLogStore.activeTags(from: dayLog).isEmpty)
    }

    func testFetchWithoutCreateDoesNotInsertEmptyDayLog() throws {
        let day = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 29)))

        XCTAssertNil(DayLogStore.dayLog(for: day, in: context, createIfMissing: false))

        let descriptor = FetchDescriptor<DayLog>()
        XCTAssertEqual((try? context.fetch(descriptor))?.count, 0)
    }

    func testTagPresentationOrdersSelectedTagsBeforeUnselectedTags() throws {
        let selectedLaterSort = DayTag(name: "Project", colorKey: "red", sort: 20)
        let unselectedEarlierSort = DayTag(name: "Easy", colorKey: "green", sort: 0)
        let selectedEarlierSort = DayTag(name: "Volume", colorKey: "blue", sort: 10)
        let unselectedSameSortA = DayTag(name: "Alpha", colorKey: "gray", sort: 30)
        let unselectedSameSortB = DayTag(name: "Beta", colorKey: "gray", sort: 30)
        let hidden = DayTag(name: "Hidden", colorKey: "gray", sort: -10, isHidden: true)

        let presentations = DayTagPresentationBuilder.orderedTags(
            allTags: [
                unselectedSameSortB,
                selectedLaterSort,
                hidden,
                unselectedEarlierSort,
                unselectedSameSortA,
                selectedEarlierSort
            ],
            selectedTags: [selectedLaterSort, selectedEarlierSort, hidden]
        )

        XCTAssertEqual(presentations.map { $0.tag.name }, ["Volume", "Project", "Easy", "Alpha", "Beta"])
        XCTAssertEqual(presentations.map(\.isSelected), [true, true, false, false, false])
    }

    func testBackfillCopiesLegacyPlanDayNotesToSharedDayLog() throws {
        let day = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 27)))
        let planDay = PlanDay(date: day)
        planDay.dailyNotes = "Legacy note"
        context.insert(planDay)

        backfillDayLogsFromPlanDayNotes(context)

        let dayLog = try XCTUnwrap(DayLogStore.fetchDayLog(for: day, in: context))
        XCTAssertEqual(dayLog.note, "Legacy note")
    }

    func testBackfillKeepsExistingSharedNoteWhenLegacyDuplicatesExist() throws {
        let day = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 28)))
        let existing = try XCTUnwrap(DayLogStore.dayLog(for: day, in: context))
        existing.note = "Existing shared note"

        let first = PlanDay(date: day)
        first.dailyNotes = "Legacy note"
        let second = PlanDay(date: day)
        second.dailyNotes = "Duplicate note"
        context.insert(first)
        context.insert(second)

        backfillDayLogsFromPlanDayNotes(context)

        let dayLog = try XCTUnwrap(DayLogStore.fetchDayLog(for: day, in: context))
        XCTAssertEqual(dayLog.note, "Existing shared note")
    }

    func testLogSummaryIncludesActivityOnlyMetadataOnlyAndMixedDays() throws {
        let calendar = Calendar.current
        let activityOnlyDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 24, hour: 10)))
        let metadataOnlyDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 25, hour: 10)))
        let mixedDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 26, hour: 10)))

        let activitySession = createTestSession(date: activityOnlyDay)
        activitySession.items.append(SessionItem(exerciseName: "Rows"))

        let metadataOnlyLog = try XCTUnwrap(DayLogStore.dayLog(for: metadataOnlyDay, in: context))
        metadataOnlyLog.note = "Travel day"

        let mixedSession = createTestSession(date: mixedDay)
        mixedSession.items.append(SessionItem(exerciseName: "Pullups"))
        let mixedLog = try XCTUnwrap(DayLogStore.dayLog(for: mixedDay, in: context))
        let tag = try XCTUnwrap(DayLogStore.createTag(name: "Volume", colorKey: "green", in: context))
        DayLogStore.setTag(tag, assigned: true, to: mixedLog)

        let grouped = LogDaySummaryBuilder.build(
            sessions: [activitySession, mixedSession],
            climbEntries: [],
            dayLogs: [metadataOnlyLog, mixedLog],
            calendar: calendar
        )

        let activityKey = calendar.startOfDay(for: activityOnlyDay)
        let metadataKey = calendar.startOfDay(for: metadataOnlyDay)
        let mixedKey = calendar.startOfDay(for: mixedDay)

        XCTAssertEqual(grouped[activityKey]?.exercises, 1)
        XCTAssertNil(grouped[activityKey]?.dayLog)
        XCTAssertEqual(grouped[metadataKey]?.dayLog?.note, "Travel day")
        XCTAssertEqual(grouped[metadataKey]?.exercises, 0)
        XCTAssertEqual(grouped[mixedKey]?.exercises, 1)
        XCTAssertEqual(DayLogStore.activeTags(from: grouped[mixedKey]?.dayLog).map(\.name), ["Volume"])
    }
}
