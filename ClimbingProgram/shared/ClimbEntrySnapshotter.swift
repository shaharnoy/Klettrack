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
        // Snapshot associated media (if any)
        let mediaSnapshots: [Snapshot.MediaSnapshot] = (c.media).map { m in
            Snapshot.MediaSnapshot(
                id: m.id,
                assetLocalIdentifier: m.assetLocalIdentifier,
                thumbnailData: m.thumbnailData,
                typeRaw: m.type.rawValue,
                createdAt: m.createdAt
            )
        }


        return Snapshot(
            id: c.id,
            climbType: c.climbType,
            ropeClimbType: c.ropeClimbType,
            grade: c.grade,
            feelsLikeGrade: c.feelsLikeGrade,
            angleDegrees: c.angleDegrees,
            style: c.style,
            attempts: c.attempts,
            isWorkInProgress: c.isWorkInProgress,
            isPreviouslyClimbed: c.isPreviouslyClimbed ?? false,
            holdColor: c.holdColor,
            gym: c.gym,
            notes: c.notes,
            dateLogged: c.dateLogged,
            tb2ClimbUUID: c.tb2ClimbUUID,
            media: mediaSnapshots
        )
    }

    @MainActor
    func restore(from snapshot: Any, into context: ModelContext) throws {
        guard let s = snapshot as? Snapshot else { return }

        // 1) Restore the climb itself
        let restored = ClimbEntry(
            id: s.id,
            climbType: s.climbType,
            ropeClimbType: s.ropeClimbType,
            grade: s.grade,
            feelsLikeGrade: s.feelsLikeGrade,
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
        SyncLocalMutation.touch(restored)

        // 2) Restore associated media and re-link to this climb
        for m in s.media {
            let mediaType = ClimbMediaType(rawValue: m.typeRaw) ?? .photo
            let media = ClimbMedia(
                id: m.id,
                assetLocalIdentifier: m.assetLocalIdentifier,
                thumbnailData: m.thumbnailData,
                type: mediaType,
                createdAt: m.createdAt,
                climb: restored
            )
            context.insert(media)
            SyncLocalMutation.touch(media)
        }
    }

    @MainActor
    func fetchByID(_ id: UUID, in context: ModelContext) throws -> ClimbEntry? {
        let fetch = FetchDescriptor<ClimbEntry>(predicate: #Predicate { $0.id == id })
        return try context.fetch(fetch).first
    }

    struct Snapshot {
        let id: UUID
        let climbType: ClimbType
        let ropeClimbType: RopeClimbType?
        let grade: String
        let feelsLikeGrade: String?
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

        // NEW: snapshot of all media entries for this climb
        let media: [MediaSnapshot]

        struct MediaSnapshot {
            let id: UUID
            let assetLocalIdentifier: String
            let thumbnailData: Data?
            /// Raw string for the media type ("photo" / "video") to avoid protocol issues
            let typeRaw: String
            let createdAt: Date
        }
    }
}

extension ClimbEntry: UndoIdentifiable {}
