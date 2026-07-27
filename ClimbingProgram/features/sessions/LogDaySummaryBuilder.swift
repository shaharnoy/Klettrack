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
            let dateKey = calendar.startOfDay(for: session.date)
            if grouped[dateKey] == nil {
                grouped[dateKey] = LogDaySummary()
            }
            grouped[dateKey]?.exercises = Array(session.items).count
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
            if grouped[dateKey] == nil {
                grouped[dateKey] = LogDaySummary()
            }
            grouped[dateKey]?.dayLog = dayLog
        }

        return grouped
    }
}
