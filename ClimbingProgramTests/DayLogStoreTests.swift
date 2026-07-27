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

    func testSameTagCanBeAssignedToMultipleDayLogs() throws {
        let calendar = Calendar.current
        let firstDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 24)))
        let secondDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 25)))
        let firstDayLog = try XCTUnwrap(DayLogStore.dayLog(for: firstDate, in: context))
        let secondDayLog = try XCTUnwrap(DayLogStore.dayLog(for: secondDate, in: context))
        let tag = try XCTUnwrap(DayLogStore.createTag(name: "Volume", colorKey: "green", in: context))

        DayLogStore.setTag(tag, assigned: true, to: firstDayLog)
        DayLogStore.setTag(tag, assigned: true, to: secondDayLog)
        try context.save()

        XCTAssertEqual(DayLogStore.activeTags(from: firstDayLog).map(\.id), [tag.id])
        XCTAssertEqual(DayLogStore.activeTags(from: secondDayLog).map(\.id), [tag.id])
        XCTAssertEqual(Set(tag.dayLogs?.map(\.id) ?? []), [firstDayLog.id, secondDayLog.id])
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

    func testLogFilterDateRangeIncludesStartAndEndDays() throws {
        let calendar = Calendar.current
        let first = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 24)))
        let second = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 25)))
        let third = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 26)))
        let grouped = logSummaries(for: [first, second, third], calendar: calendar)

        let filtered = LogDaySummaryFilter.filteredSummaries(
            grouped,
            dateRange: DateRange(customStart: first, customEnd: second),
            selectedTagIDs: [],
            calendar: calendar
        )

        XCTAssertEqual(Set(filtered.keys), Set([first, second].map { calendar.startOfDay(for: $0) }))
    }

    func testLogFilterMatchesAnySelectedTag() throws {
        let calendar = Calendar.current
        let volume = try XCTUnwrap(DayLogStore.createTag(name: "Volume", colorKey: "green", in: context))
        let project = try XCTUnwrap(DayLogStore.createTag(name: "Project", colorKey: "red", in: context))
        let travel = try XCTUnwrap(DayLogStore.createTag(name: "Travel", colorKey: "blue", in: context))
        let volumeDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 24)))
        let projectDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 25)))
        let travelDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 26)))
        let grouped = [
            calendar.startOfDay(for: volumeDay): LogDaySummary(dayLog: dayLog(on: volumeDay, tags: [volume])),
            calendar.startOfDay(for: projectDay): LogDaySummary(dayLog: dayLog(on: projectDay, tags: [project])),
            calendar.startOfDay(for: travelDay): LogDaySummary(dayLog: dayLog(on: travelDay, tags: [travel]))
        ]

        let filtered = LogDaySummaryFilter.filteredSummaries(
            grouped,
            dateRange: DateRange(),
            selectedTagIDs: [volume.id, project.id],
            calendar: calendar
        )

        XCTAssertEqual(Set(filtered.keys), Set([volumeDay, projectDay].map { calendar.startOfDay(for: $0) }))
    }

    func testLogFilterCombinesDateAndTagsWithAndBehavior() throws {
        let calendar = Calendar.current
        let volume = try XCTUnwrap(DayLogStore.createTag(name: "Volume", colorKey: "green", in: context))
        let project = try XCTUnwrap(DayLogStore.createTag(name: "Project", colorKey: "red", in: context))
        let first = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 24)))
        let second = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 25)))
        let third = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 26)))
        let grouped = [
            calendar.startOfDay(for: first): LogDaySummary(dayLog: dayLog(on: first, tags: [volume])),
            calendar.startOfDay(for: second): LogDaySummary(dayLog: dayLog(on: second, tags: [project])),
            calendar.startOfDay(for: third): LogDaySummary(dayLog: dayLog(on: third, tags: [volume]))
        ]

        let filtered = LogDaySummaryFilter.filteredSummaries(
            grouped,
            dateRange: DateRange(customStart: first, customEnd: second),
            selectedTagIDs: [volume.id],
            calendar: calendar
        )

        XCTAssertEqual(Set(filtered.keys), [calendar.startOfDay(for: first)])
    }

    func testLogFilterNoSelectedTagsLeavesTagFilteringInactive() throws {
        let calendar = Calendar.current
        let volume = try XCTUnwrap(DayLogStore.createTag(name: "Volume", colorKey: "green", in: context))
        let first = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 24)))
        let second = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 25)))
        let grouped = [
            calendar.startOfDay(for: first): LogDaySummary(dayLog: dayLog(on: first, tags: [volume])),
            calendar.startOfDay(for: second): LogDaySummary()
        ]

        let filtered = LogDaySummaryFilter.filteredSummaries(
            grouped,
            dateRange: DateRange(),
            selectedTagIDs: [],
            calendar: calendar
        )

        XCTAssertEqual(Set(filtered.keys), Set(grouped.keys))
    }

    func testLogFilterResetEquivalentReturnsAllGroupedDays() throws {
        let calendar = Calendar.current
        let first = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 24)))
        let second = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 25)))
        let grouped = logSummaries(for: [first, second], calendar: calendar)

        let filtered = LogDaySummaryFilter.filteredSummaries(
            grouped,
            dateRange: DateRange(),
            selectedTagIDs: [],
            calendar: calendar
        )

        XCTAssertEqual(Set(filtered.keys), Set(grouped.keys))
    }

    private func logSummaries(for dates: [Date], calendar: Calendar) -> [Date: LogDaySummary] {
        Dictionary(uniqueKeysWithValues: dates.map { date in
            (calendar.startOfDay(for: date), LogDaySummary())
        })
    }

    private func dayLog(on date: Date, tags: [DayTag]) -> DayLog {
        let log = DayLog(date: date, tags: tags)
        context.insert(log)
        return log
    }
}
