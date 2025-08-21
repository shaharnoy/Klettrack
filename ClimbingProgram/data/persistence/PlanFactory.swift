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

        // Default: rest days; user edits day types.
        plan.days = (0..<dayCount).map { i in PlanDay(date: addDays(i), type: .rest) }

        context.insert(plan)
        try? context.save()
        return plan
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
