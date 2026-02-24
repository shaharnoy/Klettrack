//
//  PlanSyncIntegrityBackfill.swift
//  klettrack
//
//  Created by Codex on 24.02.26.
//

import Foundation
import SwiftData

@MainActor
func backfillPlanSyncIntegrity(_ context: ModelContext) {
    do {
        let plans = try context.fetch(FetchDescriptor<Plan>())
        let planKinds = try context.fetch(FetchDescriptor<PlanKindModel>())
        let planDays = try context.fetch(FetchDescriptor<PlanDay>())

        let linkedPlanDayIDs = Set(plans.flatMap(\.days).map(\.id))
        var changedRows = 0

        for kind in planKinds {
            if let totalWeeks = kind.totalWeeks, totalWeeks <= 0 {
                kind.totalWeeks = nil
                kind.updatedAtClient = .now
                changedRows += 1
            }
        }

        for day in planDays where !linkedPlanDayIDs.contains(day.id) && !day.isSoftDeleted {
            // Orphan plan days cannot be pushed because server requires plan_id.
            // Tombstoning keeps sync healthy while preserving deterministic cleanup behavior.
            day.isSoftDeleted = true
            day.updatedAtClient = .now
            changedRows += 1
        }

        if changedRows > 0 {
            try? context.save()
            print("Backfilled plan sync integrity for \(changedRows) rows.")
        }
    } catch {
        print("backfillPlanSyncIntegrity failed: \(error.localizedDescription)")
    }
}
