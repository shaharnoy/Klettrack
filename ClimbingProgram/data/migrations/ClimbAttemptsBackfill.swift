//
//  ClimbAttemptsBackfill.swift
//  klettrack
//
//  Created by Codex on 17.02.26.
//

import Foundation
import SwiftData

@MainActor
func backfillClimbEntryAttempts(_ context: ModelContext) {
    do {
        let climbs = try context.fetch(FetchDescriptor<ClimbEntry>())
        var changedRows = 0

        for climb in climbs where !climb.isDeleted {
            let trimmedAttempts = climb.attempts?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmedAttempts.isEmpty {
                climb.attempts = "1"
                changedRows += 1
            }
        }

        if changedRows > 0 {
            try context.save()
            print("Backfilled climb attempts for \(changedRows) rows.")
        }
    } catch {
        print("backfillClimbEntryAttempts failed: \(error.localizedDescription)")
    }
}
