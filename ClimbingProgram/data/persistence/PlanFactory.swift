//
//  PlanFactory.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import Foundation
import SwiftData

struct PlanFactory {
    static func create(name: String, kind: PlanKindModel, start: Date, in context: ModelContext) -> Plan {
        let plan = Plan(name: name, kind: kind, startDate: start)

        let cal = Calendar.current
        func addDays(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: start)! }

        let weeksCount: Int = kind.isRepeating ? 1 : (kind.totalWeeks ?? 1)
        var dayCount = weeksCount * 7
        if kind.key == "daily" {
            dayCount = 1
        }

        if kind.key == "3-2-1" || kind.key == "4-3-2-1" {
            plan.days = createPyramidStructure(dayCount: dayCount, start: start, calendar: cal, context: context)
        }
        else if kind.key == "daily" {
            let restType = dayType(withKey: "rest", in: context)
            plan.days = [PlanDay(date: start, type: restType)]
        }
        else {
            let restType = dayType(withKey: "rest", in: context)
            plan.days = (0..<dayCount).map { i in PlanDay(date: addDays(i), type: restType) }
        }

        context.insert(plan)
        try? context.save()
        return plan
    }

    private static func dayType(withKey key: String, in context: ModelContext) -> DayTypeModel? {
        let descriptor = FetchDescriptor<DayTypeModel>(predicate: #Predicate { $0.key == key })
        return (try? context.fetch(descriptor))?.first
    }

    private static func createPyramidStructure(dayCount: Int, start: Date, calendar: Calendar, context: ModelContext) -> [PlanDay] {
        var days: [PlanDay] = []
        let weeksCount = dayCount / 7

        for week in 0..<weeksCount {
            let weekStart = calendar.date(byAdding: .day, value: week * 7, to: start)!

            // For now, use "rest" day type for all days as placeholder
            let restType = dayType(withKey: "rest", in: context)

            let weekPattern: [DayTypeModel?] = Array(repeating: restType, count: 7)

            for (dayIndex, dayType) in weekPattern.enumerated() {
                let dayDate = calendar.date(byAdding: .day, value: dayIndex, to: weekStart)!
                days.append(PlanDay(date: dayDate, type: dayType))
            }
        }

        return days
    }

    static func appendWeeks(to plan: Plan, count: Int, in context: ModelContext) {
        guard count > 0 else { return }
        let cal = Calendar.current
        let existing = plan.days.sorted { $0.date < $1.date }
        guard let lastDate = existing.last?.date else { return }
        let startNext = cal.date(byAdding: .day, value: 1, to: lastDate)!
        let restType = dayType(withKey: "rest", in: context)

        // Helper: resolve DayTypeModel by id (only when needed)
        func resolveDayType(_ id: UUID?) -> DayTypeModel? {
            guard let id else { return nil }
            let d = FetchDescriptor<DayTypeModel>(predicate: #Predicate { $0.id == id })
            return (try? context.fetch(d))?.first
        }

        for w in 0..<count {
            for i in 0..<7 {
                let date = cal.date(byAdding: .day, value: w*7 + i, to: startNext)!
                let weekday = cal.component(.weekday, from: date)

                let day = PlanDay(date: date, type: restType)

                // NEW: If plan has a recurrence for this weekday, apply it.
                if let chosen = plan.recurringChosenExercisesByWeekday[weekday] {
                    day.chosenExercises = chosen
                    day.exerciseOrder = plan.recurringExerciseOrderByWeekday[weekday] ?? [:]
                    day.type = resolveDayType(plan.recurringDayTypeIdByWeekday[weekday]) ?? day.type
                }

                plan.days.append(day)
            }
        }
    }

}
