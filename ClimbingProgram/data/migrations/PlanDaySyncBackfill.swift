//
//  PlanDaySyncBackfill.swift
//  klettrack
//
//  Created by Shahar Noy on 10.02.26.
//

import Foundation
import SwiftData

@MainActor
func backfillPlanDaySyncFields(_ context: ModelContext) {
    do {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        var idByName: [String: UUID] = [:]
        for exercise in exercises {
            let trimmed = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if idByName[trimmed] == nil {
                idByName[trimmed] = exercise.id
            }
        }

        let days = try context.fetch(FetchDescriptor<PlanDay>())
        var changedRows = 0

        for day in days {
            var changed = false

            if day.chosenExerciseIDs.isEmpty, !day.chosenExercises.isEmpty {
                let mapped = day.chosenExercises.compactMap { idByName[$0] }
                if !mapped.isEmpty {
                    day.chosenExerciseIDs = mapped
                    changed = true
                }
            }

            if day.exerciseOrderByID.isEmpty, !day.exerciseOrder.isEmpty {
                var mappedOrder: [String: Int] = [:]
                for (exerciseName, order) in day.exerciseOrder {
                    guard let exerciseID = idByName[exerciseName] else { continue }
                    mappedOrder[exerciseID.uuidString] = order
                }
                if !mappedOrder.isEmpty {
                    day.exerciseOrderByID = mappedOrder
                    changed = true
                }
            }

            if changed {
                day.updatedAtClient = .now
                changedRows += 1
            }
        }

        if changedRows > 0 {
            try? context.save()
            print("Backfilled plan day sync fields for \(changedRows) rows.")
        }
    } catch {
        print("backfillPlanDaySyncFields failed: \(error.localizedDescription)")
    }
}
