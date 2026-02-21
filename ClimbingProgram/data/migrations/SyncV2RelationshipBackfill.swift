//
//  SyncV2RelationshipBackfill.swift
//  klettrack
//
//  Created by Codex on 14.02.26.
//

import Foundation
import SwiftData

@MainActor
func backfillSyncV2RelationshipsAndMetadata(_ context: ModelContext) {
    do {
        var changedRows = 0

        let sessions = try context.fetch(FetchDescriptor<Session>())
        for session in sessions {
            for item in session.items where item.session?.id != session.id {
                item.session = session
                item.updatedAtClient = .now
                changedRows += 1
            }
        }

        let templates = try context.fetch(FetchDescriptor<TimerTemplate>())
        for template in templates {
            for interval in template.intervals {
                interval.updatedAtClient = .now
                changedRows += 1
            }
        }

        let timerSessions = try context.fetch(FetchDescriptor<TimerSession>())
        for timerSession in timerSessions {
            for lap in timerSession.laps {
                lap.updatedAtClient = .now
                changedRows += 1
            }
        }

        let climbEntries = try context.fetch(FetchDescriptor<ClimbEntry>())
        for climbEntry in climbEntries {
            for media in climbEntry.media where media.climb.id != climbEntry.id {
                media.climb = climbEntry
                media.updatedAtClient = .now
                changedRows += 1
            }
        }

        if changedRows > 0 {
            try? context.save()
            print("Backfilled v2 sync relationships for \(changedRows) rows.")
        }
    } catch {
        print("backfillSyncV2RelationshipsAndMetadata failed: \(error.localizedDescription)")
    }
}
