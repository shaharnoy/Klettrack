//
//  PlanFactory.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//

import Foundation
import SwiftData

struct PlanFactory {
    static func create(name: String, kind: PlanKind, start: Date, in context: ModelContext) -> Plan {
        let plan = Plan(name: name, kind: kind, startDate: start)

        let cal = Calendar.current
        func addDays(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: start)! }

        // Days count
        let dayCount: Int = {
            switch kind {
            case .weekly:
                return 7          // one week seed, user can duplicate weeks later if we add that
            case .threeTwoOne:     // 6 weeks total
                return 6 * 7
            case .fourThreeTwoOne: // 10 weeks total
                return 10 * 7
            }
        }()

        // Create proper pyramid structure for pyramid plans
        if kind == .threeTwoOne || kind == .fourThreeTwoOne {
            plan.days = createPyramidStructure(dayCount: dayCount, start: start, calendar: cal)
        } else {
            // Default: rest days for weekly plans; user edits day types.
            plan.days = (0..<dayCount).map { i in PlanDay(date: addDays(i), type: .rest) }
        }

        context.insert(plan)
        try? context.save()
        return plan
    }
    
    private static func createPyramidStructure(dayCount: Int, start: Date, calendar: Calendar) -> [PlanDay] {
        var days: [PlanDay] = []
        let weeksCount = dayCount / 7
        
        for week in 0..<weeksCount {
            let weekStart = calendar.date(byAdding: .day, value: week * 7, to: start)!
            
            // Create a varied pyramid structure
            let weekPattern: [DayType] = {
                switch week % 3 {
                case 0: // Heavy week
                    return [.climbingFull, .rest, .climbingFull, .rest, .climbingSmall, .rest, .rest]
                case 1: // Medium week
                    return [.climbingSmall, .rest, .climbingFull, .rest, .climbingSmall, .rest, .rest]
                case 2: // Light week
                    return [.climbingSmall, .rest, .climbingSmall, .rest, .rest, .rest, .rest]
                default:
                    return [.rest, .rest, .rest, .rest, .rest, .rest, .rest]
                }
            }()
            
            for (dayIndex, dayType) in weekPattern.enumerated() {
                let dayDate = calendar.date(byAdding: .day, value: dayIndex, to: weekStart)!
                days.append(PlanDay(date: dayDate, type: dayType))
            }
        }
        
        return days
    }
    
    static func appendWeeks(to plan: Plan, count: Int) {
        guard count > 0 else { return }
        let cal = Calendar.current
        let existing = plan.days.sorted { $0.date < $1.date }
        guard let lastDate = existing.last?.date else { return }
        let startNext = cal.date(byAdding: .day, value: 1, to: lastDate)!
        for w in 0..<count {
            for i in 0..<7 {
                let date = cal.date(byAdding: .day, value: w*7 + i, to: startNext)!
                // default to Rest (user will set types)
                plan.days.append(PlanDay(date: date, type: .rest))
            }
        }
    }
}
