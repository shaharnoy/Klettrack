//
//  KilterSyncManager.swift
//  Klettrack
//

import Foundation
import SwiftData

enum KilterSyncManager {
    enum SyncStage: Equatable, Sendable {
        case loggingIn
        case fetchingLogs
        case applyingRows
        case finished
    }

    struct SyncProgress: Sendable {
        let stage: SyncStage
    }

    struct Row: Sendable {
        let logUuid: String
        let climbUuid: String
        let day: Date
        let topped: Bool
        let angle: Int?
        let attempts: Int
        let flashed: Bool
        let climbName: String?
        let grade: String?
        let feelsLikeGrade: String?
    }

    static func sync(
        using creds: KilterCredentials,
        into context: ModelContext,
        client: KilterClient = KilterClient(),
        progress: (@MainActor (SyncProgress) -> Void)? = nil
    ) async throws {
        await progress?(SyncProgress(stage: .loggingIn))
        var token = try await client.login(username: creds.username, password: creds.password)
        let logs: [KilterLog]
        do {
            await progress?(SyncProgress(stage: .fetchingLogs))
            logs = try await client.fetchLogs(accessToken: token.accessToken)
        } catch let error as NSError where error.domain == "Kilter" && error.code == 401 {
            await progress?(SyncProgress(stage: .loggingIn))
            token = try await client.login(username: creds.username, password: creds.password)
            await progress?(SyncProgress(stage: .fetchingLogs))
            logs = try await client.fetchLogs(accessToken: token.accessToken)
        }

        let rows = logs.compactMap { log -> Row? in
            guard let date = BoardDateParser.parse(log.createdAt) else { return nil }
            return Row(
                logUuid: log.logUuid,
                climbUuid: log.climbUuid,
                day: date,
                topped: log.topped,
                angle: log.angle,
                attempts: log.attempts,
                flashed: log.flashed,
                climbName: log.climbName,
                grade: BoardGradeMapper.grade(of: log.currentDifficultyId),
                feelsLikeGrade: BoardGradeMapper.grade(of: log.climbRating?.difficultyGradeId)
            )
        }
        .sorted { $0.day < $1.day }

        await progress?(SyncProgress(stage: .applyingRows))
        try await applyRows(rows, into: context)
        await progress?(SyncProgress(stage: .finished))
    }

    @MainActor
    internal static func applyRows(_ rows: [Row], into context: ModelContext) throws {
        for row in rows {
            let existing = findExistingEntry(for: row, in: context)
            let previously = wasPreviouslyClimbed(
                in: context,
                kilterClimbUuid: row.climbUuid,
                angleDegrees: row.angle,
                before: row.day,
                excludingLogUuid: existing?.kilterLogUuid ?? row.logUuid
            )

            if let existing {
                update(existing, with: row, previouslyClimbed: previously)
            } else {
                let entry = ClimbEntry(
                    id: stableID(logUuid: row.logUuid),
                    climbType: .boulder,
                    grade: row.grade ?? "",
                    feelsLikeGrade: row.feelsLikeGrade,
                    angleDegrees: row.angle,
                    style: "Kilter board",
                    attempts: String(row.attempts),
                    isWorkInProgress: !row.topped,
                    isPreviouslyClimbed: previously,
                    holdColor: nil,
                    gym: row.climbName ?? "",
                    notes: row.climbName,
                    dateLogged: row.day,
                    kilterLogUuid: row.logUuid,
                    kilterClimbUuid: row.climbUuid
                )
                context.insert(entry)
            }
        }
        try context.save()
    }

    @MainActor
    internal static func wasPreviouslyClimbed(
        in context: ModelContext,
        kilterClimbUuid: String,
        angleDegrees: Int?,
        before day: Date,
        excludingLogUuid: String? = nil
    ) -> Bool {
        let uuidOpt: String? = kilterClimbUuid
        let angleConst: Int? = angleDegrees
        let dayConst: Date = day

        do {
            let descriptor: FetchDescriptor<ClimbEntry>
            if let excludingLogUuid {
                let excluded: String? = excludingLogUuid
                descriptor = FetchDescriptor<ClimbEntry>(
                    predicate: #Predicate { entry in
                        entry.kilterClimbUuid == uuidOpt &&
                        entry.kilterLogUuid != excluded &&
                        entry.angleDegrees == angleConst &&
                        entry.dateLogged < dayConst &&
                        entry.isWorkInProgress == false
                    },
                    sortBy: [SortDescriptor(\ClimbEntry.dateLogged)]
                )
            } else {
                descriptor = FetchDescriptor<ClimbEntry>(
                    predicate: #Predicate { entry in
                        entry.kilterClimbUuid == uuidOpt &&
                        entry.angleDegrees == angleConst &&
                        entry.dateLogged < dayConst &&
                        entry.isWorkInProgress == false
                    },
                    sortBy: [SortDescriptor(\ClimbEntry.dateLogged)]
                )
            }
            let priorCompleted = try context.fetch(descriptor)
            return !priorCompleted.isEmpty
        } catch {
            return false
        }
    }

    private static func findExistingEntry(for row: Row, in context: ModelContext) -> ClimbEntry? {
        let logUuid: String? = row.logUuid
        if let existing = (try? context.fetch(FetchDescriptor<ClimbEntry>(
            predicate: #Predicate { entry in entry.kilterLogUuid == logUuid }
        )))?.first {
            return existing
        }

        let stable = stableID(logUuid: row.logUuid)
        return (try? context.fetch(FetchDescriptor<ClimbEntry>(
            predicate: #Predicate { entry in entry.id == stable }
        )))?.first
    }

    private static func update(_ entry: ClimbEntry, with row: Row, previouslyClimbed: Bool) {
        entry.climbType = .boulder
        entry.grade = row.grade ?? ""
        entry.feelsLikeGrade = row.feelsLikeGrade
        entry.angleDegrees = row.angle
        entry.style = "Kilter board"
        entry.attempts = String(row.attempts)
        entry.isWorkInProgress = !row.topped
        entry.isPreviouslyClimbed = previouslyClimbed
        entry.holdColor = nil
        entry.gym = row.climbName ?? ""
        entry.notes = row.climbName
        entry.dateLogged = row.day
        entry.tb2ClimbUUID = nil
        entry.kilterLogUuid = row.logUuid
        entry.kilterClimbUuid = row.climbUuid
    }

    private static func stableID(logUuid: String) -> UUID {
        BoardSyncIdentity.deterministicUUID(from: "kilter|\(logUuid)")
    }
}
