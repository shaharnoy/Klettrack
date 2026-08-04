//
//  LogDaySummaryBuilder.swift
//  klettrack
//

import Foundation

struct LogDaySummary {
    var exercises: Int = 0
    var climbs: Int = 0
    var session: Session?
    var climbEntries: [ClimbEntry] = []
    var dayLog: DayLog?
}

@MainActor
enum LogDaySummaryBuilder {
    static func build(
        sessions: [Session],
        climbEntries: [ClimbEntry],
        dayLogs: [DayLog],
        calendar: Calendar = .current
    ) -> [Date: LogDaySummary] {
        var grouped: [Date: LogDaySummary] = [:]

        for session in sessions {
            let exerciseCount = session.items.count
            guard exerciseCount > 0 else { continue }

            let dateKey = calendar.startOfDay(for: session.date)
            if grouped[dateKey] == nil {
                grouped[dateKey] = LogDaySummary()
            }
            grouped[dateKey]?.exercises = exerciseCount
            grouped[dateKey]?.session = session
        }

        for climb in climbEntries {
            let dateKey = calendar.startOfDay(for: climb.dateLogged)
            if grouped[dateKey] == nil {
                grouped[dateKey] = LogDaySummary()
            }
            grouped[dateKey]?.climbs += 1
            grouped[dateKey]?.climbEntries.append(climb)
        }

        for dayLog in dayLogs where DayLogStore.hasContext(dayLog) {
            let dateKey = calendar.startOfDay(for: dayLog.date)
            guard grouped[dateKey] != nil else { continue }
            grouped[dateKey]?.dayLog = dayLog
        }

        return grouped
    }
}

@MainActor
enum LogDaySummaryFilter {
    static func filteredSummaries(
        _ summaries: [Date: LogDaySummary],
        dateRange: DateRange,
        selectedTagIDs: Set<UUID>,
        calendar: Calendar = .current
    ) -> [Date: LogDaySummary] {
        summaries.filter { date, summary in
            matchesDate(date, dateRange: dateRange, calendar: calendar) &&
            matchesTags(summary, selectedTagIDs: selectedTagIDs)
        }
    }

    static func isDateFilterActive(
        dateRange: DateRange,
        availableDates: [Date],
        calendar: Calendar = .current
    ) -> Bool {
        guard !availableDates.isEmpty,
              let customStart = dateRange.customStart,
              let customEnd = dateRange.customEnd,
              let minDate = availableDates.min(),
              let maxDate = availableDates.max()
        else {
            return false
        }

        return !(
            calendar.isDate(customStart, inSameDayAs: minDate) &&
            calendar.isDate(customEnd, inSameDayAs: maxDate)
        )
    }

    private static func matchesDate(_ date: Date, dateRange: DateRange, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)

        if let customStart = dateRange.customStart {
            let start = calendar.startOfDay(for: customStart)
            if day < start { return false }
        }

        if let customEnd = dateRange.customEnd {
            let end = calendar.startOfDay(for: customEnd)
            if day > end { return false }
        }

        return true
    }

    private static func matchesTags(_ summary: LogDaySummary, selectedTagIDs: Set<UUID>) -> Bool {
        guard !selectedTagIDs.isEmpty else { return true }
        let dayTagIDs = Set(DayLogStore.activeTags(from: summary.dayLog).map(\.id))
        return !dayTagIDs.isDisjoint(with: selectedTagIDs)
    }
}
