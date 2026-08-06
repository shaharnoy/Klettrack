//
//  DayLogStore.swift
//  klettrack
//

import Foundation
import SwiftData

@MainActor
enum DayLogStore {
    static func normalizedDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    static func activeTags(from dayLog: DayLog?) -> [DayTag] {
        (dayLog?.tags ?? [])
            .filter { !$0.isHidden }
            .sorted { lhs, rhs in
                if lhs.sort != rhs.sort { return lhs.sort < rhs.sort }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    static func hasContext(_ dayLog: DayLog?) -> Bool {
        guard let dayLog else { return false }
        let hasNote = dayLog.note?.isEmpty == false
        return hasNote || !activeTags(from: dayLog).isEmpty
    }

    static func fetchDayLog(for date: Date, in context: ModelContext) -> DayLog? {
        let day = normalizedDay(date)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        let descriptor = FetchDescriptor<DayLog>(
            predicate: #Predicate<DayLog> { log in
                log.date >= day && log.date < nextDay
            },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? context.fetch(descriptor))?.first
    }

    @discardableResult
    static func dayLog(for date: Date, in context: ModelContext, createIfMissing: Bool = true) -> DayLog? {
        if let existing = fetchDayLog(for: date, in: context) {
            return existing
        }
        guard createIfMissing else { return nil }
        let created = DayLog(date: normalizedDay(date))
        context.insert(created)
        return created
    }

    static func setNote(_ rawNote: String, for dayLog: DayLog) {
        dayLog.note = rawNote.isEmpty ? nil : rawNote
    }

    static func activeTag(named rawName: String, in context: ModelContext, excluding id: UUID? = nil) -> DayTag? {
        let normalizedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedName.isEmpty else { return nil }
        let tags = (try? context.fetch(FetchDescriptor<DayTag>())) ?? []
        return tags.first {
            !$0.isHidden &&
            $0.id != id &&
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedName
        }
    }

    @discardableResult
    static func createTag(name rawName: String, colorKey: String, in context: ModelContext) -> DayTag? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let existing = activeTag(named: name, in: context) {
            return existing
        }
        let allTags = (try? context.fetch(FetchDescriptor<DayTag>())) ?? []
        if let hidden = allTags.first(where: {
            $0.isHidden &&
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name.lowercased()
        }) {
            hidden.name = name
            hidden.colorKey = DayTypeModel.allowedColorKeys.contains(colorKey) ? colorKey : "gray"
            hidden.isHidden = false
            return hidden
        }
        let tag = DayTag(
            name: name,
            colorKey: colorKey,
            sort: ((allTags.map(\.sort).max() ?? -10) + 10)
        )
        context.insert(tag)
        return tag
    }

    static func renameTag(_ tag: DayTag, to rawName: String, colorKey: String, in context: ModelContext) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        guard activeTag(named: name, in: context, excluding: tag.id) == nil else { return false }
        tag.name = name
        if DayTypeModel.allowedColorKeys.contains(colorKey) {
            tag.colorKey = colorKey
        }
        return true
    }

    static func setTag(_ tag: DayTag, assigned isAssigned: Bool, to dayLog: DayLog) {
        var tags = dayLog.tags ?? []
        if isAssigned {
            if !tags.contains(where: { $0.id == tag.id }) {
                tags.append(tag)
            }
        } else {
            tags.removeAll { $0.id == tag.id }
        }
        dayLog.tags = tags
    }

    static func hideTag(_ tag: DayTag, in context: ModelContext) {
        tag.isHidden = true
        let dayLogs = (try? context.fetch(FetchDescriptor<DayLog>())) ?? []
        for dayLog in dayLogs {
            var tags = dayLog.tags ?? []
            tags.removeAll { $0.id == tag.id }
            dayLog.tags = tags
        }
    }
}
