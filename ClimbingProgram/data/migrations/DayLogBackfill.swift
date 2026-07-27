//
//  DayLogBackfill.swift
//  klettrack
//

import Foundation
import SwiftData

@MainActor
func backfillDayLogsFromPlanDayNotes(_ context: ModelContext) {
    do {
        let planDays = try context.fetch(
            FetchDescriptor<PlanDay>(sortBy: [SortDescriptor(\.date, order: .forward)])
        )

        for planDay in planDays {
            guard let legacyNote = planDay.dailyNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !legacyNote.isEmpty
            else { continue }

            guard let dayLog = DayLogStore.dayLog(for: planDay.date, in: context) else { continue }
            if dayLog.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                dayLog.note = legacyNote
            }
        }

        try context.save()
    } catch {
        print("backfillDayLogsFromPlanDayNotes failed: \(error.localizedDescription)")
    }
}
