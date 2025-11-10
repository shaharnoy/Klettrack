//
//  ClimbEntrySnapshotter.swift
//  ClimbingProgram
//
//  Created by Shahar Noy on 07.10.25.
//

import Foundation
import SwiftData

struct ClimbEntrySnapshotter: UndoSnapshotting {
    typealias Item = ClimbEntry

    func makeSnapshot(from c: ClimbEntry) -> Any {
        Snapshot(
            id: c.id,
            climbType: c.climbType,
            grade: c.grade,
            angleDegrees: c.angleDegrees,
            style: c.style,
            attempts: c.attempts,
            isWorkInProgress: c.isWorkInProgress,
            isPreviouslyClimbed: c.isPreviouslyClimbed ?? false,
            holdColor: c.holdColor,
            gym: c.gym,
            notes: c.notes,
            dateLogged: c.dateLogged,
            tb2ClimbUUID: c.tb2ClimbUUID
        )
    }

    @MainActor
    func restore(from snapshot: Any, into context: ModelContext) throws {
        guard let s = snapshot as? Snapshot else { return }
        let restored = ClimbEntry(
            id: s.id,
            climbType: s.climbType,
            grade: s.grade,
            angleDegrees: s.angleDegrees,
            style: s.style,
            attempts: s.attempts,
            isWorkInProgress: s.isWorkInProgress,
            isPreviouslyClimbed: s.isPreviouslyClimbed,
            holdColor: s.holdColor,
            gym: s.gym,
            notes: s.notes,
            dateLogged: s.dateLogged,
            tb2ClimbUUID: s.tb2ClimbUUID
        )
        context.insert(restored)
    }

    @MainActor
    func fetchByID(_ id: UUID, in context: ModelContext) throws -> ClimbEntry? {
        let fetch = FetchDescriptor<ClimbEntry>(predicate: #Predicate { $0.id == id })
        return try context.fetch(fetch).first
    }

    struct Snapshot {
        let id: UUID
        let climbType: ClimbType
        let grade: String
        let angleDegrees: Int?
        let style: String
        let attempts: String?
        let isWorkInProgress: Bool
        let isPreviouslyClimbed: Bool
        let holdColor: HoldColor?
        let gym: String
        let notes: String?
        let dateLogged: Date
        let tb2ClimbUUID: String?
    }
}

extension ClimbEntry: UndoIdentifiable {}
