//
//  SyncStoreActor.swift
//  klettrack
//
//  Created by Shahar Noy on 10.02.26.
//

import Foundation
import SwiftData
import CryptoKit

enum SyncStoreError: Error, Sendable, LocalizedError {
    case invalidEntity(String)
    case invalidMutationType(String)
    case invalidUUID(String)
    case invalidPayloadJSON
    case missingDocument(SyncEntityName)

    var errorDescription: String? {
        switch self {
        case .invalidEntity(let value):
            return "Unsupported sync entity: \(value)"
        case .invalidMutationType(let value):
            return "Unsupported mutation type: \(value)"
        case .invalidUUID(let value):
            return "Invalid UUID value: \(value)"
        case .invalidPayloadJSON:
            return "Invalid JSON payload in local mutation queue."
        case .missingDocument(let entity):
            return "Missing document for upsert on \(entity.rawValue)."
        }
    }
}

@ModelActor
actor SyncStoreActor {
    private let tombstoneRetentionDays = 30
    private var pendingPlanLinksByDayID: [UUID: UUID] = [:]

    func loadOrCreateSyncState() throws -> SyncStateSnapshot {
        let state = try ensureSyncStateModel()
        return state.snapshot
    }

    func setSyncEnabled(_ isEnabled: Bool, userId: String?) throws {
        let state = try ensureSyncStateModel()
        let previousUserId = state.userId
        state.isSyncEnabled = isEnabled
        state.userId = userId
        state.lastSuccessfulSyncAt = nil

        // Account switch: reset bootstrap/cursor and drop stale outbox rows.
        if previousUserId != userId {
            state.lastCursor = nil
            state.didBootstrapLocalSnapshot = false
            let mutations = try modelContext.fetch(FetchDescriptor<SyncMutation>())
            for mutation in mutations {
                modelContext.delete(mutation)
            }
        }

        try saveIfNeeded()
    }

    func prepareForSignedOutState(clearPendingMutations: Bool) throws {
        let state = try ensureSyncStateModel()
        state.userId = nil
        state.isSyncEnabled = false
        state.lastCursor = nil
        state.lastSuccessfulSyncAt = nil
        state.didBootstrapLocalSnapshot = false

        if clearPendingMutations {
            let mutations = try modelContext.fetch(FetchDescriptor<SyncMutation>())
            for mutation in mutations {
                modelContext.delete(mutation)
            }
        }

        try saveIfNeeded()
    }

    /// Enqueues local snapshot changes so existing pre-sync data and new unsynced local changes are uploaded.
    @discardableResult
    func enqueueLocalSnapshotIfNeeded() throws -> Bool {
        let state = try ensureSyncStateModel()
        guard state.isSyncEnabled else { return false }
        let isFullBootstrap = !state.didBootstrapLocalSnapshot
        let watermark = state.lastSuccessfulSyncAt
        let snapshotContext = ModelContext(modelContainer)

        let existingMutations = try modelContext.fetch(FetchDescriptor<SyncMutation>())
        var pendingKeys = Set(existingMutations.map {
            "\($0.entityName)|\($0.entityId.uuidString.lowercased())"
        })
        var didEnqueue = false

        func shouldEnqueue(syncVersion: Int, updatedAtClient: Date) -> Bool {
            if isFullBootstrap {
                return true
            }
            if syncVersion == 0 {
                return true
            }
            guard let watermark else { return true }
            return updatedAtClient > watermark
        }

        func enqueueIfNeeded(
            entity: SyncEntityName,
            entityId: UUID,
            mutationType: SyncMutationType,
            baseVersion: Int,
            payload: [String: JSONValue],
            updatedAtClient: Date
        ) throws {
            guard shouldEnqueue(syncVersion: baseVersion, updatedAtClient: updatedAtClient) else {
                return
            }

            let pendingKey = "\(entity.rawValue)|\(entityId.uuidString.lowercased())"
            if pendingKeys.contains(pendingKey), mutationType != .delete {
                return
            }

            _ = try enqueueMutation(
                entity: entity,
                entityId: entityId,
                mutationType: mutationType,
                baseVersion: baseVersion,
                payload: payload,
                updatedAtClient: updatedAtClient,
                shouldSave: false
            )
            pendingKeys.insert(pendingKey)
            didEnqueue = true
        }

        let plans = try snapshotContext.fetch(FetchDescriptor<Plan>())
        let planKinds = try snapshotContext.fetch(FetchDescriptor<PlanKindModel>())
        let dayTypes = try snapshotContext.fetch(FetchDescriptor<DayTypeModel>())
        let planDays = try snapshotContext.fetch(FetchDescriptor<PlanDay>())
        let activities = try snapshotContext.fetch(FetchDescriptor<Activity>())
        let trainingTypes = try snapshotContext.fetch(FetchDescriptor<TrainingType>())
        let exercises = try snapshotContext.fetch(FetchDescriptor<Exercise>())
        let combinations = try snapshotContext.fetch(FetchDescriptor<BoulderCombination>())
        let sessions = try snapshotContext.fetch(FetchDescriptor<Session>())
        let sessionItems = try snapshotContext.fetch(FetchDescriptor<SessionItem>())
        let timerTemplates = try snapshotContext.fetch(FetchDescriptor<TimerTemplate>())
        let timerIntervals = try snapshotContext.fetch(FetchDescriptor<TimerInterval>())
        let timerSessions = try snapshotContext.fetch(FetchDescriptor<TimerSession>())
        let timerLaps = try snapshotContext.fetch(FetchDescriptor<TimerLap>())
        let climbEntries = try snapshotContext.fetch(FetchDescriptor<ClimbEntry>())
        let climbStyles = try snapshotContext.fetch(FetchDescriptor<ClimbStyle>())
        let climbGyms = try snapshotContext.fetch(FetchDescriptor<ClimbGym>())

        let planByDayID = Dictionary(
            uniqueKeysWithValues: plans.flatMap { plan in
                plan.days.map { day in (day.id, plan.id) }
            }
        )
        let activityByTrainingTypeID = Dictionary(
            uniqueKeysWithValues: activities.flatMap { activity in
                activity.types.map { type in (type.id, activity.id) }
            }
        )
        let trainingTypeByExerciseID = Dictionary(
            uniqueKeysWithValues: trainingTypes.flatMap { type in
                type.exercises.map { exercise in (exercise.id, type.id) }
            }
        )
        let trainingTypeByCombinationID = Dictionary(
            uniqueKeysWithValues: trainingTypes.flatMap { type in
                type.combinations.map { combination in (combination.id, type.id) }
            }
        )
        let sessionByItemID = Dictionary(
            uniqueKeysWithValues: sessions.flatMap { session in
                session.items.map { item in (item.id, session.id) }
            }
        )
        let templateByIntervalID = Dictionary(
            uniqueKeysWithValues: timerTemplates.flatMap { template in
                template.intervals.map { interval in (interval.id, template.id) }
            }
        )
        let timerSessionByLapID = Dictionary(
            uniqueKeysWithValues: timerSessions.flatMap { session in
                session.laps.map { lap in (lap.id, session.id) }
            }
        )

        for model in planKinds {
            try enqueueIfNeeded(
                entity: .planKinds,
                entityId: model.id,
                mutationType: model.isSoftDeleted ? .delete : .upsert,
                baseVersion: model.syncVersion,
                payload: [
                    "key": .string(model.key),
                    "name": .string(model.name),
                    "total_weeks": model.totalWeeks.map { .number(Double($0)) } ?? .null,
                    "is_repeating": .bool(model.isRepeating),
                    "display_order": .number(Double(model.order))
                ],
                updatedAtClient: model.updatedAtClient
            )
        }

        for model in dayTypes {
            try enqueueIfNeeded(
                entity: .dayTypes,
                entityId: model.id,
                mutationType: model.isSoftDeleted ? .delete : .upsert,
                baseVersion: model.syncVersion,
                payload: [
                    "key": .string(model.key),
                    "name": .string(model.name),
                    "display_order": .number(Double(model.order)),
                    "color_key": .string(model.colorKey),
                    "is_default": .bool(model.isdefault),
                    "is_hidden": .bool(model.isHidden)
                ],
                updatedAtClient: model.updatedAtClient
            )
        }

        for model in plans {
            try enqueueIfNeeded(
                entity: .plans,
                entityId: model.id,
                mutationType: model.isSoftDeleted ? .delete : .upsert,
                baseVersion: model.syncVersion,
                payload: [
                    "name": .string(model.name),
                    "kind_id": model.kind.map { .string($0.id.uuidString.lowercased()) } ?? .null,
                    "start_date": .string(model.startDate.iso8601WithFractionalSeconds),
                    "recurring_chosen_exercises_by_weekday": .object(encodeWeekdayExerciseMap(model.recurringChosenExercisesByWeekday)),
                    "recurring_exercise_order_by_weekday": .object(encodeWeekdayOrderMap(model.recurringExerciseOrderByWeekday)),
                    "recurring_day_type_id_by_weekday": .object(encodeWeekdayUUIDMap(model.recurringDayTypeIdByWeekday))
                ],
                updatedAtClient: model.updatedAtClient
            )
        }

        for model in planDays {
            try enqueueIfNeeded(
                entity: .planDays,
                entityId: model.id,
                mutationType: model.isSoftDeleted ? .delete : .upsert,
                baseVersion: model.syncVersion,
                payload: [
                    "plan_id": planByDayID[model.id].map { .string($0.uuidString.lowercased()) } ?? .null,
                    "day_date": .string(model.date.iso8601WithFractionalSeconds),
                    "day_type_id": model.type.map { .string($0.id.uuidString.lowercased()) } ?? .null,
                    "chosen_exercise_ids": .array(model.chosenExerciseIDs.map { .string($0.uuidString.lowercased()) }),
                    "exercise_order_by_id": .object(model.exerciseOrderByID.reduce(into: [:]) { result, item in
                        result[item.key.lowercased()] = .number(Double(item.value))
                    }),
                    "daily_notes": model.dailyNotes.map(JSONValue.string) ?? .null
                ],
                updatedAtClient: model.updatedAtClient
            )
        }

        for model in activities {
            try enqueueIfNeeded(
                entity: .activities,
                entityId: model.id,
                mutationType: model.isSoftDeleted ? .delete : .upsert,
                baseVersion: model.syncVersion,
                payload: ["name": .string(model.name)],
                updatedAtClient: model.updatedAtClient
            )
        }

        for model in trainingTypes {
            try enqueueIfNeeded(
                entity: .trainingTypes,
                entityId: model.id,
                mutationType: model.isSoftDeleted ? .delete : .upsert,
                baseVersion: model.syncVersion,
                payload: [
                    "activity_id": activityByTrainingTypeID[model.id].map { .string($0.uuidString.lowercased()) } ?? .null,
                    "name": .string(model.name),
                    "area": model.area.map(JSONValue.string) ?? .null,
                    "type_description": model.typeDescription.map(JSONValue.string) ?? .null
                ],
                updatedAtClient: model.updatedAtClient
            )
        }

        for model in exercises {
            try enqueueIfNeeded(
                entity: .exercises,
                entityId: model.id,
                mutationType: model.isSoftDeleted ? .delete : .upsert,
                baseVersion: model.syncVersion,
                payload: [
                    "training_type_id": trainingTypeByExerciseID[model.id].map { .string($0.uuidString.lowercased()) } ?? .null,
                    "name": .string(model.name),
                    "area": model.area.map(JSONValue.string) ?? .null,
                    "display_order": .number(Double(model.order)),
                    "exercise_description": model.exerciseDescription.map(JSONValue.string) ?? .null,
                    "reps_text": model.repsText.map(JSONValue.string) ?? .null,
                    "duration_text": model.durationText.map(JSONValue.string) ?? .null,
                    "sets_text": model.setsText.map(JSONValue.string) ?? .null,
                    "rest_text": model.restText.map(JSONValue.string) ?? .null,
                    "notes": model.notes.map(JSONValue.string) ?? .null
                ],
                updatedAtClient: model.updatedAtClient
            )
        }

        for model in combinations {
            try enqueueIfNeeded(
                entity: .boulderCombinations,
                entityId: model.id,
                mutationType: model.isSoftDeleted ? .delete : .upsert,
                baseVersion: model.syncVersion,
                payload: [
                    "training_type_id": trainingTypeByCombinationID[model.id].map { .string($0.uuidString.lowercased()) } ?? .null,
                    "name": .string(model.name),
                    "combo_description": model.comboDescription.map(JSONValue.string) ?? .null
                ],
                updatedAtClient: model.updatedAtClient
            )
        }

        for model in sessions {
            try enqueueIfNeeded(
                entity: .sessions,
                entityId: model.id,
                mutationType: model.isSoftDeleted ? .delete : .upsert,
                baseVersion: model.syncVersion,
                payload: [
                    "session_date": .string(model.date.iso8601WithFractionalSeconds)
                ],
                updatedAtClient: model.updatedAtClient
            )
        }

        for model in sessionItems {
            try enqueueIfNeeded(
                entity: .sessionItems,
                entityId: model.id,
                mutationType: model.isSoftDeleted ? .delete : .upsert,
                baseVersion: model.syncVersion,
                payload: [
                    "session_id": sessionByItemID[model.id].map { .string($0.uuidString.lowercased()) } ?? .null,
                    "source_tag": model.sourceTag.map(JSONValue.string) ?? .null,
                    "exercise_name": .string(model.exerciseName),
                    "sort_order": .number(Double(model.sort)),
                    "plan_source_id": model.planSourceId.map { .string($0.uuidString.lowercased()) } ?? .null,
                    "plan_name": model.planName.map(JSONValue.string) ?? .null,
                    "reps": model.reps.map(JSONValue.number) ?? .null,
                    "sets": model.sets.map(JSONValue.number) ?? .null,
                    "weight_kg": model.weightKg.map(JSONValue.number) ?? .null,
                    "grade": model.grade.map(JSONValue.string) ?? .null,
                    "notes": model.notes.map(JSONValue.string) ?? .null,
                    "duration": model.duration.map(JSONValue.number) ?? .null
                ],
                updatedAtClient: model.updatedAtClient
            )
        }

        for model in timerTemplates {
            try enqueueIfNeeded(
                entity: .timerTemplates,
                entityId: model.id,
                mutationType: model.isSoftDeleted ? .delete : .upsert,
                baseVersion: model.syncVersion,
                payload: [
                    "name": .string(model.name),
                    "template_description": model.templateDescription.map(JSONValue.string) ?? .null,
                    "total_time_seconds": model.totalTimeSeconds.map { .number(Double($0)) } ?? .null,
                    "is_repeating": .bool(model.isRepeating),
                    "repeat_count": model.repeatCount.map { .number(Double($0)) } ?? .null,
                    "rest_time_between_intervals": model.restTimeBetweenIntervals.map { .number(Double($0)) } ?? .null,
                    "created_date": .string(model.createdDate.iso8601WithFractionalSeconds),
                    "last_used_date": model.lastUsedDate.map { .string($0.iso8601WithFractionalSeconds) } ?? .null,
                    "use_count": .number(Double(model.useCount))
                ],
                updatedAtClient: model.updatedAtClient
            )
        }

        for model in timerIntervals {
            try enqueueIfNeeded(
                entity: .timerIntervals,
                entityId: model.id,
                mutationType: model.isSoftDeleted ? .delete : .upsert,
                baseVersion: model.syncVersion,
                payload: [
                    "timer_template_id": templateByIntervalID[model.id].map { .string($0.uuidString.lowercased()) } ?? .null,
                    "name": .string(model.name),
                    "work_time_seconds": .number(Double(model.workTimeSeconds)),
                    "rest_time_seconds": .number(Double(model.restTimeSeconds)),
                    "repetitions": .number(Double(model.repetitions)),
                    "display_order": .number(Double(model.order))
                ],
                updatedAtClient: model.updatedAtClient
            )
        }

        for model in timerSessions {
            try enqueueIfNeeded(
                entity: .timerSessions,
                entityId: model.id,
                mutationType: model.isSoftDeleted ? .delete : .upsert,
                baseVersion: model.syncVersion,
                payload: [
                    "start_date": .string(model.startDate.iso8601WithFractionalSeconds),
                    "end_date": model.endDate.map { .string($0.iso8601WithFractionalSeconds) } ?? .null,
                    "timer_template_id": model.templateId.map { .string($0.uuidString.lowercased()) } ?? .null,
                    "template_name": model.templateName.map(JSONValue.string) ?? .null,
                    "plan_day_id": model.planDayId.map { .string($0.uuidString.lowercased()) } ?? .null,
                    "total_elapsed_seconds": .number(Double(model.totalElapsedSeconds)),
                    "completed_intervals": .number(Double(model.completedIntervals)),
                    "was_completed": .bool(model.wasCompleted),
                    "daily_notes": model.dailynotes.map(JSONValue.string) ?? .null
                ],
                updatedAtClient: model.updatedAtClient
            )
        }

        for model in timerLaps {
            try enqueueIfNeeded(
                entity: .timerLaps,
                entityId: model.id,
                mutationType: model.isSoftDeleted ? .delete : .upsert,
                baseVersion: model.syncVersion,
                payload: [
                    "timer_session_id": timerSessionByLapID[model.id].map { .string($0.uuidString.lowercased()) } ?? .null,
                    "lap_number": .number(Double(model.lapNumber)),
                    "timestamp": .string(model.timestamp.iso8601WithFractionalSeconds),
                    "elapsed_seconds": .number(Double(model.elapsedSeconds)),
                    "notes": model.notes.map(JSONValue.string) ?? .null
                ],
                updatedAtClient: model.updatedAtClient
            )
        }

        for model in climbEntries {
            try enqueueIfNeeded(
                entity: .climbEntries,
                entityId: model.id,
                mutationType: model.isSoftDeleted ? .delete : .upsert,
                baseVersion: model.syncVersion,
                payload: [
                    "climb_type": .string(model.climbType.rawValue),
                    "rope_climb_type": model.ropeClimbType.map { .string($0.rawValue) } ?? .null,
                    "grade": .string(model.grade),
                    "feels_like_grade": model.feelsLikeGrade.map(JSONValue.string) ?? .null,
                    "angle_degrees": model.angleDegrees.map { .number(Double($0)) } ?? .null,
                    "style": .string(model.style),
                    "attempts": model.attempts.map(JSONValue.string) ?? .null,
                    "is_work_in_progress": .bool(model.isWorkInProgress),
                    "is_previously_climbed": model.isPreviouslyClimbed.map(JSONValue.bool) ?? .null,
                    "hold_color": model.holdColor.map { .string($0.rawValue) } ?? .null,
                    "gym": .string(model.gym),
                    "notes": model.notes.map(JSONValue.string) ?? .null,
                    "date_logged": .string(model.dateLogged.iso8601WithFractionalSeconds),
                    "tb2_climb_uuid": model.tb2ClimbUUID.map(JSONValue.string) ?? .null
                ],
                updatedAtClient: model.updatedAtClient
            )
        }

        for model in climbStyles {
            try enqueueIfNeeded(
                entity: .climbStyles,
                entityId: model.id,
                mutationType: model.isSoftDeleted ? .delete : .upsert,
                baseVersion: model.syncVersion,
                payload: [
                    "name": .string(model.name),
                    "is_default": .bool(model.isDefault),
                    "is_hidden": .bool(model.isHidden)
                ],
                updatedAtClient: model.updatedAtClient
            )
        }

        for model in climbGyms {
            try enqueueIfNeeded(
                entity: .climbGyms,
                entityId: model.id,
                mutationType: model.isSoftDeleted ? .delete : .upsert,
                baseVersion: model.syncVersion,
                payload: [
                    "name": .string(model.name),
                    "is_default": .bool(model.isDefault)
                ],
                updatedAtClient: model.updatedAtClient
            )
        }


        for combination in combinations {
            for (index, exercise) in combination.exercises.enumerated() {
                let linkID = Self.boulderCombinationExerciseLinkID(
                    combinationID: combination.id,
                    exerciseID: exercise.id
                )
                try enqueueIfNeeded(
                    entity: .boulderCombinationExercises,
                    entityId: linkID,
                    mutationType: .upsert,
                    baseVersion: 0,
                    payload: [
                        "boulder_combination_id": .string(combination.id.uuidString.lowercased()),
                        "exercise_id": .string(exercise.id.uuidString.lowercased()),
                        "display_order": .number(Double(index))
                    ],
                    updatedAtClient: combination.updatedAtClient
                )
            }
        }

        state.didBootstrapLocalSnapshot = true
        try saveIfNeeded()
        return didEnqueue
    }

    @discardableResult
    func enqueueMutation(
        entity: SyncEntityName,
        entityId: UUID,
        mutationType: SyncMutationType,
        baseVersion: Int,
        payload: [String: JSONValue],
        updatedAtClient: Date? = .now
    ) throws -> UUID {
        try enqueueMutation(
            entity: entity,
            entityId: entityId,
            mutationType: mutationType,
            baseVersion: baseVersion,
            payload: payload,
            updatedAtClient: updatedAtClient,
            shouldSave: true
        )
    }

    @discardableResult
    private func enqueueMutation(
        entity: SyncEntityName,
        entityId: UUID,
        mutationType: SyncMutationType,
        baseVersion: Int,
        payload: [String: JSONValue],
        updatedAtClient: Date? = .now,
        shouldSave: Bool
    ) throws -> UUID {
        // Keep only the newest pending mutation per entity+entity id.
        // This prevents stale upserts from reviving rows after a local delete.
        let existingDescriptor = FetchDescriptor<SyncMutation>(
            predicate: #Predicate {
                $0.entityName == entity.rawValue && $0.entityId == entityId
            }
        )
        let existingRows = try modelContext.fetch(existingDescriptor)
        for row in existingRows {
            modelContext.delete(row)
        }

        let mutation = SyncMutation()
        mutation.opId = UUID()
        mutation.entityName = entity.rawValue
        mutation.entityId = entityId
        mutation.mutationType = mutationType.rawValue
        mutation.baseVersion = baseVersion
        mutation.payloadJSON = try SyncSerialization.encodePayload(payload)
        mutation.createdAt = .now
        mutation.updatedAtClient = updatedAtClient
        mutation.attempts = 0
        mutation.lastError = nil
        modelContext.insert(mutation)
        if shouldSave {
            try saveIfNeeded()
        }
        return mutation.opId
    }

    func fetchPendingMutations(limit: Int) throws -> [PendingSyncMutation] {
        let rows = try modelContext.fetch(FetchDescriptor<SyncMutation>())
        let sortedRows = rows.sorted { lhs, rhs in
            let lhsIsDelete = lhs.mutationType == SyncMutationType.delete.rawValue
            let rhsIsDelete = rhs.mutationType == SyncMutationType.delete.rawValue
            if lhsIsDelete != rhsIsDelete {
                return lhsIsDelete && !rhsIsDelete
            }
            if lhs.attempts != rhs.attempts {
                return lhs.attempts < rhs.attempts
            }
            return lhs.createdAt < rhs.createdAt
        }

        return try sortedRows.prefix(max(1, limit)).map { row in
            guard let entity = SyncEntityName(rawValue: row.entityName) else {
                throw SyncStoreError.invalidEntity(row.entityName)
            }
            guard let mutationType = SyncMutationType(rawValue: row.mutationType) else {
                throw SyncStoreError.invalidMutationType(row.mutationType)
            }
            let payload = try SyncSerialization.decodePayload(row.payloadJSON)
            return PendingSyncMutation(
                opId: row.opId,
                entity: entity,
                entityId: row.entityId,
                mutationType: mutationType,
                baseVersion: row.baseVersion,
                updatedAtClient: row.updatedAtClient ?? row.createdAt,
                payload: payload,
                attempts: row.attempts
            )
        }
    }

    func fetchPendingMutation(opId: String) throws -> PendingSyncMutation? {
        guard let row = try findMutationRow(opId: opId) else {
            return nil
        }
        return try mapPendingMutation(row)
    }

    func processPushResponse(_ response: SyncPushResponse) throws -> SyncPushProcessingResult {
        let mutationRows = try modelContext.fetch(FetchDescriptor<SyncMutation>())
        let rowsByID = Dictionary(uniqueKeysWithValues: mutationRows.map { ($0.opId.uuidString.lowercased(), $0) })

        var acknowledgedCount = 0
        var conflictCount = 0
        var failureCount = 0

        for opId in response.acknowledgedOpIds {
            guard let row = rowsByID[opId.lowercased()] else { continue }
            modelContext.delete(row)
            acknowledgedCount += 1
        }

        for failed in response.failed {
            guard let opId = failed.opId?.lowercased(), let row = rowsByID[opId] else { continue }
            row.attempts += 1
            row.lastError = failed.reason
            row.createdAt = .now
            failureCount += 1
        }

        for conflict in response.conflicts {
            guard let row = rowsByID[conflict.opId.lowercased()] else { continue }
            row.attempts += 1
            row.lastError = conflict.reason
            row.createdAt = .now
            conflictCount += 1
        }

        try saveIfNeeded()
        return SyncPushProcessingResult(
            acknowledged: acknowledgedCount,
            conflicts: conflictCount,
            failures: failureCount
        )
    }

    @discardableResult
    func resolveConflictKeepMine(opId: String, serverVersion: Int?) throws -> Bool {
        guard let row = try findMutationRow(opId: opId) else {
            return false
        }

        // When server row does not exist (nil serverVersion), rebase to insert path.
        row.baseVersion = max(0, serverVersion ?? 0)
        row.attempts = 0
        row.lastError = nil
        row.createdAt = .now
        try saveIfNeeded()
        return true
    }

    @discardableResult
    func resolveConflictKeepServer(opId: String) throws -> Bool {
        guard let row = try findMutationRow(opId: opId) else {
            return false
        }

        modelContext.delete(row)
        try saveIfNeeded()
        return true
    }

    func applyPullResponse(_ response: SyncPullResponse) throws {
        for change in response.changes {
            switch change.type {
            case .upsert:
                guard let document = change.doc else {
                    throw SyncStoreError.missingDocument(change.entity)
                }
                try applyUpsert(entity: change.entity, document: document)
            case .delete:
                guard let entityId = change.entityId else { continue }
                try applyDelete(entity: change.entity, entityId: entityId, version: change.version)
            }
        }

        let state = try ensureSyncStateModel()
        state.lastCursor = response.nextCursor
        state.lastSuccessfulSyncAt = .now
        try compactLocalTombstonesIfNeeded(retentionDays: tombstoneRetentionDays)
        try saveIfNeeded()
    }

    func activityState(id: UUID) throws -> (isSoftDeleted: Bool, version: Int)? {
        guard let activity = try modelContext.fetch(FetchDescriptor<Activity>()).first(where: { $0.id == id }) else {
            return nil
        }
        return (activity.isSoftDeleted, activity.syncVersion)
    }

    private func findMutationRow(opId: String) throws -> SyncMutation? {
        guard let parsed = UUID(uuidString: opId) else {
            return nil
        }
        let descriptor = FetchDescriptor<SyncMutation>(
            predicate: #Predicate { $0.opId == parsed }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func mapPendingMutation(_ row: SyncMutation) throws -> PendingSyncMutation {
        guard let entity = SyncEntityName(rawValue: row.entityName) else {
            throw SyncStoreError.invalidEntity(row.entityName)
        }
        guard let mutationType = SyncMutationType(rawValue: row.mutationType) else {
            throw SyncStoreError.invalidMutationType(row.mutationType)
        }
        let payload = try SyncSerialization.decodePayload(row.payloadJSON)
        return PendingSyncMutation(
            opId: row.opId,
            entity: entity,
            entityId: row.entityId,
            mutationType: mutationType,
            baseVersion: row.baseVersion,
            updatedAtClient: row.updatedAtClient ?? row.createdAt,
            payload: payload,
            attempts: row.attempts
        )
    }

    private func applyUpsert(entity: SyncEntityName, document: [String: JSONValue]) throws {
        switch entity {
        case .planKinds:
            try applyPlanKind(document: document)
        case .dayTypes:
            try applyDayType(document: document)
        case .plans:
            try applyPlan(document: document)
        case .planDays:
            try applyPlanDay(document: document)
        case .activities:
            try applyActivity(document: document)
        case .trainingTypes:
            try applyTrainingType(document: document)
        case .exercises:
            try applyExercise(document: document)
        case .boulderCombinations:
            try applyBoulderCombination(document: document)
        case .boulderCombinationExercises:
            try applyBoulderCombinationExercise(document: document)
        case .sessions:
            try applySession(document: document)
        case .sessionItems:
            try applySessionItem(document: document)
        case .timerTemplates:
            try applyTimerTemplate(document: document)
        case .timerIntervals:
            try applyTimerInterval(document: document)
        case .timerSessions:
            try applyTimerSession(document: document)
        case .timerLaps:
            try applyTimerLap(document: document)
        case .climbEntries:
            try applyClimbEntry(document: document)
        case .climbStyles:
            try applyClimbStyle(document: document)
        case .climbGyms:
            try applyClimbGym(document: document)
        }
    }

    private func applyDelete(entity: SyncEntityName, entityId: String, version: Int?) throws {
        guard let id = UUID(uuidString: entityId) else {
            throw SyncStoreError.invalidUUID(entityId)
        }

        switch entity {
        case .planKinds:
            if let model = try modelContext.fetch(FetchDescriptor<PlanKindModel>()).first(where: { $0.id == id }) {
                model.isSoftDeleted = true
                model.syncVersion = version ?? model.syncVersion
            }
        case .dayTypes:
            if let model = try modelContext.fetch(FetchDescriptor<DayTypeModel>()).first(where: { $0.id == id }) {
                model.isSoftDeleted = true
                model.syncVersion = version ?? model.syncVersion
            }
        case .plans:
            if let model = try modelContext.fetch(FetchDescriptor<Plan>()).first(where: { $0.id == id }) {
                model.isSoftDeleted = true
                model.syncVersion = version ?? model.syncVersion
            }
        case .planDays:
            if let model = try modelContext.fetch(FetchDescriptor<PlanDay>()).first(where: { $0.id == id }) {
                model.isSoftDeleted = true
                model.syncVersion = version ?? model.syncVersion
            }
        case .activities:
            if let model = try modelContext.fetch(FetchDescriptor<Activity>()).first(where: { $0.id == id }) {
                model.isSoftDeleted = true
                model.syncVersion = version ?? model.syncVersion
            }
        case .trainingTypes:
            if let model = try modelContext.fetch(FetchDescriptor<TrainingType>()).first(where: { $0.id == id }) {
                model.isSoftDeleted = true
                model.syncVersion = version ?? model.syncVersion
            }
        case .exercises:
            if let model = try modelContext.fetch(FetchDescriptor<Exercise>()).first(where: { $0.id == id }) {
                model.isSoftDeleted = true
                model.syncVersion = version ?? model.syncVersion
            }
        case .boulderCombinations:
            if let model = try modelContext.fetch(FetchDescriptor<BoulderCombination>()).first(where: { $0.id == id }) {
                model.isSoftDeleted = true
                model.syncVersion = version ?? model.syncVersion
            }
        case .boulderCombinationExercises:
            try removeBoulderCombinationExercise(linkID: id)
        case .sessions:
            if let model = try modelContext.fetch(FetchDescriptor<Session>()).first(where: { $0.id == id }) {
                model.isSoftDeleted = true
                model.syncVersion = version ?? model.syncVersion
            }
        case .sessionItems:
            if let model = try modelContext.fetch(FetchDescriptor<SessionItem>()).first(where: { $0.id == id }) {
                model.isSoftDeleted = true
                model.syncVersion = version ?? model.syncVersion
            }
        case .timerTemplates:
            if let model = try modelContext.fetch(FetchDescriptor<TimerTemplate>()).first(where: { $0.id == id }) {
                model.isSoftDeleted = true
                model.syncVersion = version ?? model.syncVersion
            }
        case .timerIntervals:
            if let model = try modelContext.fetch(FetchDescriptor<TimerInterval>()).first(where: { $0.id == id }) {
                model.isSoftDeleted = true
                model.syncVersion = version ?? model.syncVersion
            }
        case .timerSessions:
            if let model = try modelContext.fetch(FetchDescriptor<TimerSession>()).first(where: { $0.id == id }) {
                model.isSoftDeleted = true
                model.syncVersion = version ?? model.syncVersion
            }
        case .timerLaps:
            if let model = try modelContext.fetch(FetchDescriptor<TimerLap>()).first(where: { $0.id == id }) {
                model.isSoftDeleted = true
                model.syncVersion = version ?? model.syncVersion
            }
        case .climbEntries:
            if let model = try modelContext.fetch(FetchDescriptor<ClimbEntry>()).first(where: { $0.id == id }) {
                model.isSoftDeleted = true
                model.syncVersion = version ?? model.syncVersion
            }
        case .climbStyles:
            if let model = try modelContext.fetch(FetchDescriptor<ClimbStyle>()).first(where: { $0.id == id }) {
                model.isSoftDeleted = true
                model.syncVersion = version ?? model.syncVersion
            }
        case .climbGyms:
            if let model = try modelContext.fetch(FetchDescriptor<ClimbGym>()).first(where: { $0.id == id }) {
                model.isSoftDeleted = true
                model.syncVersion = version ?? model.syncVersion
            }
        }
    }

    private func applyPlanKind(document: [String: JSONValue]) throws {
        let id = try requiredUUID("id", in: document)
        let model = try fetchOrCreatePlanKind(id: id)
        model.key = document["key"]?.stringValue ?? model.key
        model.name = document["name"]?.stringValue ?? model.name
        model.totalWeeks = document["total_weeks"]?.intValue
        model.isRepeating = document["is_repeating"]?.boolValue ?? model.isRepeating
        model.order = document["display_order"]?.intValue ?? model.order
        applyCommonMetadata(to: model, document: document)
    }

    private func applyDayType(document: [String: JSONValue]) throws {
        let id = try requiredUUID("id", in: document)
        let model = try fetchOrCreateDayType(id: id)
        model.key = document["key"]?.stringValue ?? model.key
        model.name = document["name"]?.stringValue ?? model.name
        model.order = document["display_order"]?.intValue ?? model.order
        if let colorKey = document["color_key"]?.stringValue {
            model.colorKey = DayTypeModel.allowedColorKeys.contains(colorKey) ? colorKey : "gray"
        }
        model.isdefault = document["is_default"]?.boolValue ?? model.isdefault
        model.isHidden = document["is_hidden"]?.boolValue ?? model.isHidden
        applyCommonMetadata(to: model, document: document)
    }

    private func applyPlan(document: [String: JSONValue]) throws {
        let id = try requiredUUID("id", in: document)
        let model = try fetchOrCreatePlan(id: id)
        model.name = document["name"]?.stringValue ?? model.name

        if let startDate = parseDate(document["start_date"]) {
            model.startDate = startDate
        }
        if let kindID = parseUUID(document["kind_id"]) {
            model.kind = try fetchOrCreatePlanKind(id: kindID)
        } else {
            model.kind = nil
        }

        model.recurringChosenExercisesByWeekday = decodeWeekdayExerciseMap(document["recurring_chosen_exercises_by_weekday"])
        model.recurringExerciseOrderByWeekday = decodeWeekdayOrderMap(document["recurring_exercise_order_by_weekday"])
        model.recurringDayTypeIdByWeekday = decodeWeekdayUUIDMap(document["recurring_day_type_id_by_weekday"])
        applyCommonMetadata(to: model, document: document)
        try attachDeferredPlanDaysIfNeeded(to: model)
    }

    private func applyPlanDay(document: [String: JSONValue]) throws {
        let id = try requiredUUID("id", in: document)
        let model = try fetchOrCreatePlanDay(id: id)
        if let date = parseDate(document["day_date"]) {
            model.date = date
        }

        if let dayTypeID = parseUUID(document["day_type_id"]) {
            model.type = try fetchOrCreateDayType(id: dayTypeID)
        } else {
            model.type = nil
        }

        if let planID = parseUUID(document["plan_id"]) {
            pendingPlanLinksByDayID[model.id] = planID
            if let plan = try fetchPlan(id: planID), !plan.isSoftDeleted {
                if !plan.days.contains(where: { $0.id == model.id }) {
                    plan.days.append(model)
                }
                pendingPlanLinksByDayID.removeValue(forKey: model.id)
            }
        } else {
            pendingPlanLinksByDayID.removeValue(forKey: model.id)
        }

        model.chosenExerciseIDs = deduplicatedUUIDsPreservingOrder(
            decodeUUIDArray(document["chosen_exercise_ids"])
        )
        let chosenExerciseIDSet = Set(model.chosenExerciseIDs.map { $0.uuidString.lowercased() })
        model.exerciseOrderByID = decodeStringIntMap(document["exercise_order_by_id"]).reduce(into: [:]) { result, item in
            let normalizedID = item.key.lowercased()
            guard chosenExerciseIDSet.contains(normalizedID), result[normalizedID] == nil else { return }
            result[normalizedID] = item.value
        }
        model.dailyNotes = document["daily_notes"]?.stringValue

        // Keep legacy name-based fields in sync during migration window.
        let exercises = try fetchExercises(ids: model.chosenExerciseIDs)
        model.chosenExercises = exercises.map(\.name)
        model.exerciseOrder = decodeLegacyOrder(
            orderByID: model.exerciseOrderByID,
            exercises: exercises
        )
        applyCommonMetadata(to: model, document: document)
    }

    private func applyActivity(document: [String: JSONValue]) throws {
        let id = try requiredUUID("id", in: document)
        let model = try fetchOrCreateActivity(id: id)
        model.name = document["name"]?.stringValue ?? model.name
        applyCommonMetadata(to: model, document: document)
    }

    private func applyTrainingType(document: [String: JSONValue]) throws {
        let id = try requiredUUID("id", in: document)
        let model = try fetchOrCreateTrainingType(id: id)
        model.name = document["name"]?.stringValue ?? model.name
        model.area = document["area"]?.stringValue
        model.typeDescription = document["type_description"]?.stringValue
        applyCommonMetadata(to: model, document: document)

        if let activityID = parseUUID(document["activity_id"]) {
            let owner = try fetchOrCreateActivity(id: activityID)
            if !owner.types.contains(where: { $0.id == model.id }) {
                owner.types.append(model)
            }
            try removeTrainingType(model.id, fromAllExcept: owner.id)
        }
    }

    private func applyExercise(document: [String: JSONValue]) throws {
        let id = try requiredUUID("id", in: document)
        let model = try fetchOrCreateExercise(id: id)
        model.name = document["name"]?.stringValue ?? model.name
        model.area = document["area"]?.stringValue
        model.order = document["display_order"]?.intValue ?? model.order
        model.exerciseDescription = document["exercise_description"]?.stringValue
        model.repsText = document["reps_text"]?.stringValue
        model.durationText = document["duration_text"]?.stringValue
        model.setsText = document["sets_text"]?.stringValue
        model.restText = document["rest_text"]?.stringValue
        model.notes = document["notes"]?.stringValue
        applyCommonMetadata(to: model, document: document)

        if let trainingTypeID = parseUUID(document["training_type_id"]) {
            let owner = try fetchOrCreateTrainingType(id: trainingTypeID)
            if !owner.exercises.contains(where: { $0.id == model.id }) {
                owner.exercises.append(model)
            }
            try removeExercise(model.id, fromAllExcept: owner.id)
        }
    }

    private func applyBoulderCombination(document: [String: JSONValue]) throws {
        let id = try requiredUUID("id", in: document)
        let model = try fetchOrCreateBoulderCombination(id: id)
        model.name = document["name"]?.stringValue ?? model.name
        model.comboDescription = document["combo_description"]?.stringValue
        applyCommonMetadata(to: model, document: document)

        if let trainingTypeID = parseUUID(document["training_type_id"]) {
            let owner = try fetchOrCreateTrainingType(id: trainingTypeID)
            if !owner.combinations.contains(where: { $0.id == model.id }) {
                owner.combinations.append(model)
            }
            try removeBoulderCombination(model.id, fromAllExcept: owner.id)
        }
    }

    private func applyBoulderCombinationExercise(document: [String: JSONValue]) throws {
        guard let combinationID = parseUUID(document["boulder_combination_id"]),
              let exerciseID = parseUUID(document["exercise_id"]) else {
            return
        }

        let combination = try fetchOrCreateBoulderCombination(id: combinationID)
        let exercise = try fetchOrCreateExercise(id: exerciseID)
        if !combination.exercises.contains(where: { $0.id == exercise.id }) {
            combination.exercises.append(exercise)
        }
    }

    private func applySession(document: [String: JSONValue]) throws {
        let id = try requiredUUID("id", in: document)
        let model = try fetchOrCreateSession(id: id)
        if let date = parseDate(document["session_date"]) {
            model.date = date
        }
        applyCommonMetadata(to: model, document: document)
    }

    private func applySessionItem(document: [String: JSONValue]) throws {
        let id = try requiredUUID("id", in: document)
        let model = try fetchOrCreateSessionItem(id: id)
        model.sourceTag = document["source_tag"]?.stringValue
        model.exerciseName = document["exercise_name"]?.stringValue ?? model.exerciseName
        model.sort = document["sort_order"]?.intValue ?? model.sort
        model.planSourceId = parseUUID(document["plan_source_id"])
        model.planName = document["plan_name"]?.stringValue
        model.reps = document["reps"]?.numberValue
        model.sets = document["sets"]?.numberValue
        model.weightKg = document["weight_kg"]?.numberValue
        model.grade = document["grade"]?.stringValue
        model.notes = document["notes"]?.stringValue
        model.duration = document["duration"]?.numberValue

        if let sessionID = parseUUID(document["session_id"]) {
            let session = try fetchOrCreateSession(id: sessionID)
            model.session = session
            if !session.items.contains(where: { $0.id == model.id }) {
                session.items.append(model)
            }
        } else {
            model.session = nil
        }
        applyCommonMetadata(to: model, document: document)
    }

    private func applyTimerTemplate(document: [String: JSONValue]) throws {
        let id = try requiredUUID("id", in: document)
        let model = try fetchOrCreateTimerTemplate(id: id)
        model.name = document["name"]?.stringValue ?? model.name
        model.templateDescription = document["template_description"]?.stringValue
        model.totalTimeSeconds = document["total_time_seconds"]?.intValue
        model.isRepeating = document["is_repeating"]?.boolValue ?? model.isRepeating
        model.repeatCount = document["repeat_count"]?.intValue
        model.restTimeBetweenIntervals = document["rest_time_between_intervals"]?.intValue
        if let createdDate = parseDate(document["created_date"]) {
            model.createdDate = createdDate
        }
        model.lastUsedDate = parseDate(document["last_used_date"])
        model.useCount = document["use_count"]?.intValue ?? model.useCount
        applyCommonMetadata(to: model, document: document)
    }

    private func applyTimerInterval(document: [String: JSONValue]) throws {
        let id = try requiredUUID("id", in: document)
        let model = try fetchOrCreateTimerInterval(id: id)
        model.name = document["name"]?.stringValue ?? model.name
        model.workTimeSeconds = document["work_time_seconds"]?.intValue ?? model.workTimeSeconds
        model.restTimeSeconds = document["rest_time_seconds"]?.intValue ?? model.restTimeSeconds
        model.repetitions = document["repetitions"]?.intValue ?? model.repetitions
        model.order = document["display_order"]?.intValue ?? model.order
        applyCommonMetadata(to: model, document: document)

        if let templateID = parseUUID(document["timer_template_id"]) {
            let template = try fetchOrCreateTimerTemplate(id: templateID)
            if !template.intervals.contains(where: { $0.id == model.id }) {
                template.intervals.append(model)
            }
            try removeTimerInterval(model.id, fromAllExcept: template.id)
        }
    }

    private func applyTimerSession(document: [String: JSONValue]) throws {
        let id = try requiredUUID("id", in: document)
        let model = try fetchOrCreateTimerSession(id: id)
        if let startDate = parseDate(document["start_date"]) {
            model.startDate = startDate
        }
        model.endDate = parseDate(document["end_date"])
        model.templateId = parseUUID(document["timer_template_id"])
        model.templateName = document["template_name"]?.stringValue
        model.planDayId = parseUUID(document["plan_day_id"])
        model.totalElapsedSeconds = document["total_elapsed_seconds"]?.intValue ?? model.totalElapsedSeconds
        model.completedIntervals = document["completed_intervals"]?.intValue ?? model.completedIntervals
        model.wasCompleted = document["was_completed"]?.boolValue ?? model.wasCompleted
        model.dailynotes = document["daily_notes"]?.stringValue
        applyCommonMetadata(to: model, document: document)
    }

    private func applyTimerLap(document: [String: JSONValue]) throws {
        let id = try requiredUUID("id", in: document)
        let model = try fetchOrCreateTimerLap(id: id)
        model.lapNumber = document["lap_number"]?.intValue ?? model.lapNumber
        if let timestamp = parseDate(document["timestamp"]) {
            model.timestamp = timestamp
        }
        model.elapsedSeconds = document["elapsed_seconds"]?.intValue ?? model.elapsedSeconds
        model.notes = document["notes"]?.stringValue
        applyCommonMetadata(to: model, document: document)

        if let timerSessionID = parseUUID(document["timer_session_id"]) {
            let session = try fetchOrCreateTimerSession(id: timerSessionID)
            if !session.laps.contains(where: { $0.id == model.id }) {
                session.laps.append(model)
            }
            try removeTimerLap(model.id, fromAllExcept: session.id)
        }
    }

    private func applyClimbEntry(document: [String: JSONValue]) throws {
        let id = try requiredUUID("id", in: document)
        let model = try fetchOrCreateClimbEntry(id: id)
        if let climbTypeRaw = document["climb_type"]?.stringValue,
           let climbType = ClimbType(rawValue: climbTypeRaw) {
            model.climbType = climbType
        }
        if let ropeTypeRaw = document["rope_climb_type"]?.stringValue {
            model.ropeClimbType = RopeClimbType(rawValue: ropeTypeRaw)
        } else {
            model.ropeClimbType = nil
        }
        model.grade = document["grade"]?.stringValue ?? model.grade
        model.feelsLikeGrade = document["feels_like_grade"]?.stringValue
        model.angleDegrees = document["angle_degrees"]?.intValue
        model.style = document["style"]?.stringValue ?? model.style
        model.attempts = document["attempts"]?.stringValue
        model.isWorkInProgress = document["is_work_in_progress"]?.boolValue ?? model.isWorkInProgress
        model.isPreviouslyClimbed = document["is_previously_climbed"]?.boolValue
        if let holdColorRaw = document["hold_color"]?.stringValue {
            model.holdColor = HoldColor(rawValue: holdColorRaw)
        } else {
            model.holdColor = nil
        }
        model.gym = document["gym"]?.stringValue ?? model.gym
        model.notes = document["notes"]?.stringValue
        if let loggedDate = parseDate(document["date_logged"]) {
            model.dateLogged = loggedDate
        }
        model.tb2ClimbUUID = document["tb2_climb_uuid"]?.stringValue
        applyCommonMetadata(to: model, document: document)
    }

    private func applyClimbStyle(document: [String: JSONValue]) throws {
        let id = try requiredUUID("id", in: document)
        let model = try fetchOrCreateClimbStyle(id: id)
        model.name = document["name"]?.stringValue ?? model.name
        model.isDefault = document["is_default"]?.boolValue ?? model.isDefault
        model.isHidden = document["is_hidden"]?.boolValue ?? model.isHidden
        applyCommonMetadata(to: model, document: document)
    }

    private func applyClimbGym(document: [String: JSONValue]) throws {
        let id = try requiredUUID("id", in: document)
        let model = try fetchOrCreateClimbGym(id: id)
        model.name = document["name"]?.stringValue ?? model.name
        model.isDefault = document["is_default"]?.boolValue ?? model.isDefault
        applyCommonMetadata(to: model, document: document)
    }

    private func applyCommonMetadata(to model: PlanKindModel, document: [String: JSONValue]) {
        model.syncVersion = document["version"]?.intValue ?? model.syncVersion
        model.updatedAtClient = parseDate(document["updated_at_client"]) ?? model.updatedAtClient
        model.isSoftDeleted = document["is_deleted"]?.boolValue ?? model.isSoftDeleted
    }

    private func applyCommonMetadata(to model: DayTypeModel, document: [String: JSONValue]) {
        model.syncVersion = document["version"]?.intValue ?? model.syncVersion
        model.updatedAtClient = parseDate(document["updated_at_client"]) ?? model.updatedAtClient
        model.isSoftDeleted = document["is_deleted"]?.boolValue ?? model.isSoftDeleted
    }

    private func applyCommonMetadata(to model: Plan, document: [String: JSONValue]) {
        model.syncVersion = document["version"]?.intValue ?? model.syncVersion
        model.updatedAtClient = parseDate(document["updated_at_client"]) ?? model.updatedAtClient
        model.isSoftDeleted = document["is_deleted"]?.boolValue ?? model.isSoftDeleted
    }

    private func applyCommonMetadata(to model: PlanDay, document: [String: JSONValue]) {
        model.syncVersion = document["version"]?.intValue ?? model.syncVersion
        model.updatedAtClient = parseDate(document["updated_at_client"]) ?? model.updatedAtClient
        model.isSoftDeleted = document["is_deleted"]?.boolValue ?? model.isSoftDeleted
    }

    private func applyCommonMetadata(to model: Activity, document: [String: JSONValue]) {
        model.syncVersion = document["version"]?.intValue ?? model.syncVersion
        model.updatedAtClient = parseDate(document["updated_at_client"]) ?? model.updatedAtClient
        model.isSoftDeleted = document["is_deleted"]?.boolValue ?? model.isSoftDeleted
    }

    private func applyCommonMetadata(to model: TrainingType, document: [String: JSONValue]) {
        model.syncVersion = document["version"]?.intValue ?? model.syncVersion
        model.updatedAtClient = parseDate(document["updated_at_client"]) ?? model.updatedAtClient
        model.isSoftDeleted = document["is_deleted"]?.boolValue ?? model.isSoftDeleted
    }

    private func applyCommonMetadata(to model: Exercise, document: [String: JSONValue]) {
        model.syncVersion = document["version"]?.intValue ?? model.syncVersion
        model.updatedAtClient = parseDate(document["updated_at_client"]) ?? model.updatedAtClient
        model.isSoftDeleted = document["is_deleted"]?.boolValue ?? model.isSoftDeleted
    }

    private func applyCommonMetadata(to model: BoulderCombination, document: [String: JSONValue]) {
        model.syncVersion = document["version"]?.intValue ?? model.syncVersion
        model.updatedAtClient = parseDate(document["updated_at_client"]) ?? model.updatedAtClient
        model.isSoftDeleted = document["is_deleted"]?.boolValue ?? model.isSoftDeleted
    }

    private func applyCommonMetadata(to model: Session, document: [String: JSONValue]) {
        model.syncVersion = document["version"]?.intValue ?? model.syncVersion
        model.updatedAtClient = parseDate(document["updated_at_client"]) ?? model.updatedAtClient
        model.isSoftDeleted = document["is_deleted"]?.boolValue ?? model.isSoftDeleted
    }

    private func applyCommonMetadata(to model: SessionItem, document: [String: JSONValue]) {
        model.syncVersion = document["version"]?.intValue ?? model.syncVersion
        model.updatedAtClient = parseDate(document["updated_at_client"]) ?? model.updatedAtClient
        model.isSoftDeleted = document["is_deleted"]?.boolValue ?? model.isSoftDeleted
    }

    private func applyCommonMetadata(to model: TimerTemplate, document: [String: JSONValue]) {
        model.syncVersion = document["version"]?.intValue ?? model.syncVersion
        model.updatedAtClient = parseDate(document["updated_at_client"]) ?? model.updatedAtClient
        model.isSoftDeleted = document["is_deleted"]?.boolValue ?? model.isSoftDeleted
    }

    private func applyCommonMetadata(to model: TimerInterval, document: [String: JSONValue]) {
        model.syncVersion = document["version"]?.intValue ?? model.syncVersion
        model.updatedAtClient = parseDate(document["updated_at_client"]) ?? model.updatedAtClient
        model.isSoftDeleted = document["is_deleted"]?.boolValue ?? model.isSoftDeleted
    }

    private func applyCommonMetadata(to model: TimerSession, document: [String: JSONValue]) {
        model.syncVersion = document["version"]?.intValue ?? model.syncVersion
        model.updatedAtClient = parseDate(document["updated_at_client"]) ?? model.updatedAtClient
        model.isSoftDeleted = document["is_deleted"]?.boolValue ?? model.isSoftDeleted
    }

    private func applyCommonMetadata(to model: TimerLap, document: [String: JSONValue]) {
        model.syncVersion = document["version"]?.intValue ?? model.syncVersion
        model.updatedAtClient = parseDate(document["updated_at_client"]) ?? model.updatedAtClient
        model.isSoftDeleted = document["is_deleted"]?.boolValue ?? model.isSoftDeleted
    }

    private func applyCommonMetadata(to model: ClimbEntry, document: [String: JSONValue]) {
        model.syncVersion = document["version"]?.intValue ?? model.syncVersion
        model.updatedAtClient = parseDate(document["updated_at_client"]) ?? model.updatedAtClient
        model.isSoftDeleted = document["is_deleted"]?.boolValue ?? model.isSoftDeleted
    }

    private func applyCommonMetadata(to model: ClimbStyle, document: [String: JSONValue]) {
        model.syncVersion = document["version"]?.intValue ?? model.syncVersion
        model.updatedAtClient = parseDate(document["updated_at_client"]) ?? model.updatedAtClient
        model.isSoftDeleted = document["is_deleted"]?.boolValue ?? model.isSoftDeleted
    }

    private func applyCommonMetadata(to model: ClimbGym, document: [String: JSONValue]) {
        model.syncVersion = document["version"]?.intValue ?? model.syncVersion
        model.updatedAtClient = parseDate(document["updated_at_client"]) ?? model.updatedAtClient
        model.isSoftDeleted = document["is_deleted"]?.boolValue ?? model.isSoftDeleted
    }

    private func fetchExercises(ids: [UUID]) throws -> [Exercise] {
        var result: [Exercise] = []
        for id in ids {
            result.append(try fetchOrCreateExercise(id: id))
        }
        return result
    }

    private func decodeLegacyOrder(orderByID: [String: Int], exercises: [Exercise]) -> [String: Int] {
        var namesByID: [String: String] = [:]
        for exercise in exercises {
            namesByID[exercise.id.uuidString.lowercased()] = exercise.name
        }
        var result: [String: Int] = [:]
        for (id, index) in orderByID {
            if let name = namesByID[id.lowercased()] {
                result[name] = index
            }
        }
        return result
    }

    private func deduplicatedUUIDsPreservingOrder(_ ids: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        var result: [UUID] = []
        for id in ids where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    private func decodeUUIDArray(_ json: JSONValue?) -> [UUID] {
        guard let array = json?.arrayValue else { return [] }
        return array.compactMap { parseUUID($0) }
    }

    private func decodeStringIntMap(_ json: JSONValue?) -> [String: Int] {
        guard let map = json?.objectValue else { return [:] }
        var result: [String: Int] = [:]
        for (key, value) in map {
            if let int = value.intValue {
                result[key] = int
            }
        }
        return result
    }

    private func decodeWeekdayExerciseMap(_ json: JSONValue?) -> [Int: [String]] {
        guard let map = json?.objectValue else { return [:] }
        var result: [Int: [String]] = [:]
        for (key, value) in map {
            guard let day = Int(key), let list = value.arrayValue else { continue }
            result[day] = list.compactMap(\.stringValue)
        }
        return result
    }

    private func decodeWeekdayOrderMap(_ json: JSONValue?) -> [Int: [String: Int]] {
        guard let map = json?.objectValue else { return [:] }
        var result: [Int: [String: Int]] = [:]
        for (key, value) in map {
            guard let day = Int(key), let rawOrder = value.objectValue else { continue }
            var converted: [String: Int] = [:]
            for (orderKey, orderValue) in rawOrder {
                if let intValue = orderValue.intValue {
                    converted[orderKey] = intValue
                }
            }
            result[day] = converted
        }
        return result
    }

    private func decodeWeekdayUUIDMap(_ json: JSONValue?) -> [Int: UUID] {
        guard let map = json?.objectValue else { return [:] }
        var result: [Int: UUID] = [:]
        for (key, value) in map {
            guard let day = Int(key), let uuid = parseUUID(value) else { continue }
            result[day] = uuid
        }
        return result
    }

    private func parseUUID(_ json: JSONValue?) -> UUID? {
        guard let raw = json?.stringValue else { return nil }
        return UUID(uuidString: raw)
    }

    private func parseDate(_ json: JSONValue?) -> Date? {
        guard let raw = json?.stringValue else { return nil }
        return raw.asISO8601Date()
    }

    private func encodeWeekdayExerciseMap(_ map: [Int: [String]]) -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        for (weekday, values) in map {
            result[String(weekday)] = .array(values.map { .string($0.lowercased()) })
        }
        return result
    }

    private func encodeWeekdayOrderMap(_ map: [Int: [String: Int]]) -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        for (weekday, orderMap) in map {
            let encoded = orderMap.reduce(into: [String: JSONValue]()) { partialResult, item in
                partialResult[item.key.lowercased()] = .number(Double(item.value))
            }
            result[String(weekday)] = .object(encoded)
        }
        return result
    }

    private func encodeWeekdayUUIDMap(_ map: [Int: UUID]) -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        for (weekday, identifier) in map {
            result[String(weekday)] = .string(identifier.uuidString.lowercased())
        }
        return result
    }

    private func requiredUUID(_ key: String, in document: [String: JSONValue]) throws -> UUID {
        guard let value = parseUUID(document[key]) else {
            throw SyncStoreError.invalidUUID(key)
        }
        return value
    }

    private func fetchOrCreatePlanKind(id: UUID) throws -> PlanKindModel {
        if let existing = try modelContext.fetch(FetchDescriptor<PlanKindModel>()).first(where: { $0.id == id }) {
            return existing
        }
        let created = PlanKindModel(id: id, key: "", name: "")
        modelContext.insert(created)
        return created
    }

    private func fetchOrCreateDayType(id: UUID) throws -> DayTypeModel {
        if let existing = try modelContext.fetch(FetchDescriptor<DayTypeModel>()).first(where: { $0.id == id }) {
            return existing
        }
        let created = DayTypeModel(id: id, key: "", name: "", colorKey: "gray")
        modelContext.insert(created)
        return created
    }

    private func fetchOrCreatePlan(id: UUID) throws -> Plan {
        if let existing = try fetchPlan(id: id) {
            return existing
        }
        let created = Plan(id: id, name: "", kind: nil, startDate: .now)
        modelContext.insert(created)
        return created
    }

    private func fetchPlan(id: UUID) throws -> Plan? {
        try modelContext.fetch(FetchDescriptor<Plan>()).first(where: { $0.id == id })
    }

    private func attachDeferredPlanDaysIfNeeded(to plan: Plan) throws {
        guard !plan.isSoftDeleted else { return }
        let dayIDs = pendingPlanLinksByDayID.compactMap { (dayID, planID) in
            planID == plan.id ? dayID : nil
        }
        guard !dayIDs.isEmpty else { return }

        let planDays = try modelContext.fetch(FetchDescriptor<PlanDay>())
        let planDaysByID = Dictionary(uniqueKeysWithValues: planDays.map { ($0.id, $0) })
        for dayID in dayIDs {
            guard let day = planDaysByID[dayID] else {
                pendingPlanLinksByDayID.removeValue(forKey: dayID)
                continue
            }
            if !plan.days.contains(where: { $0.id == dayID }) {
                plan.days.append(day)
            }
            pendingPlanLinksByDayID.removeValue(forKey: dayID)
        }
    }

    private func fetchOrCreatePlanDay(id: UUID) throws -> PlanDay {
        if let existing = try modelContext.fetch(FetchDescriptor<PlanDay>()).first(where: { $0.id == id }) {
            return existing
        }
        let created = PlanDay(id: id, date: .now)
        modelContext.insert(created)
        return created
    }

    private func fetchOrCreateActivity(id: UUID) throws -> Activity {
        if let existing = try modelContext.fetch(FetchDescriptor<Activity>()).first(where: { $0.id == id }) {
            return existing
        }
        let created = Activity(id: id, name: "")
        modelContext.insert(created)
        return created
    }

    private func fetchOrCreateTrainingType(id: UUID) throws -> TrainingType {
        if let existing = try modelContext.fetch(FetchDescriptor<TrainingType>()).first(where: { $0.id == id }) {
            return existing
        }
        let created = TrainingType(id: id, name: "")
        modelContext.insert(created)
        return created
    }

    private func fetchOrCreateExercise(id: UUID) throws -> Exercise {
        if let existing = try modelContext.fetch(FetchDescriptor<Exercise>()).first(where: { $0.id == id }) {
            return existing
        }
        let created = Exercise(id: id, name: "")
        modelContext.insert(created)
        return created
    }

    private func fetchOrCreateBoulderCombination(id: UUID) throws -> BoulderCombination {
        if let existing = try modelContext.fetch(FetchDescriptor<BoulderCombination>()).first(where: { $0.id == id }) {
            return existing
        }
        let created = BoulderCombination(id: id, name: "")
        modelContext.insert(created)
        return created
    }

    private func fetchOrCreateSession(id: UUID) throws -> Session {
        if let existing = try modelContext.fetch(FetchDescriptor<Session>()).first(where: { $0.id == id }) {
            return existing
        }
        let created = Session(id: id, date: .now)
        modelContext.insert(created)
        return created
    }

    private func fetchOrCreateSessionItem(id: UUID) throws -> SessionItem {
        if let existing = try modelContext.fetch(FetchDescriptor<SessionItem>()).first(where: { $0.id == id }) {
            return existing
        }
        let created = SessionItem(id: id, exerciseName: "")
        modelContext.insert(created)
        return created
    }

    private func fetchOrCreateTimerTemplate(id: UUID) throws -> TimerTemplate {
        if let existing = try modelContext.fetch(FetchDescriptor<TimerTemplate>()).first(where: { $0.id == id }) {
            return existing
        }
        let created = TimerTemplate(id: id, name: "")
        modelContext.insert(created)
        return created
    }

    private func fetchOrCreateTimerInterval(id: UUID) throws -> TimerInterval {
        if let existing = try modelContext.fetch(FetchDescriptor<TimerInterval>()).first(where: { $0.id == id }) {
            return existing
        }
        let created = TimerInterval(id: id, name: "", workTimeSeconds: 0, restTimeSeconds: 0, repetitions: 1)
        modelContext.insert(created)
        return created
    }

    private func fetchOrCreateTimerSession(id: UUID) throws -> TimerSession {
        if let existing = try modelContext.fetch(FetchDescriptor<TimerSession>()).first(where: { $0.id == id }) {
            return existing
        }
        let created = TimerSession(id: id)
        modelContext.insert(created)
        return created
    }

    private func fetchOrCreateTimerLap(id: UUID) throws -> TimerLap {
        if let existing = try modelContext.fetch(FetchDescriptor<TimerLap>()).first(where: { $0.id == id }) {
            return existing
        }
        let created = TimerLap(id: id, lapNumber: 1, elapsedSeconds: 0)
        modelContext.insert(created)
        return created
    }

    private func fetchOrCreateClimbEntry(id: UUID) throws -> ClimbEntry {
        if let existing = try modelContext.fetch(FetchDescriptor<ClimbEntry>()).first(where: { $0.id == id }) {
            return existing
        }
        let created = ClimbEntry(id: id, climbType: .boulder, grade: "", style: "", gym: "")
        modelContext.insert(created)
        return created
    }

    private func fetchOrCreateClimbStyle(id: UUID) throws -> ClimbStyle {
        if let existing = try modelContext.fetch(FetchDescriptor<ClimbStyle>()).first(where: { $0.id == id }) {
            return existing
        }
        let created = ClimbStyle(id: id, name: "")
        modelContext.insert(created)
        return created
    }

    private func fetchOrCreateClimbGym(id: UUID) throws -> ClimbGym {
        if let existing = try modelContext.fetch(FetchDescriptor<ClimbGym>()).first(where: { $0.id == id }) {
            return existing
        }
        let created = ClimbGym(id: id, name: "")
        modelContext.insert(created)
        return created
    }

    private func removeTrainingType(_ trainingTypeID: UUID, fromAllExcept activityID: UUID) throws {
        let activities = try modelContext.fetch(FetchDescriptor<Activity>())
        for activity in activities where activity.id != activityID {
            if let index = activity.types.firstIndex(where: { $0.id == trainingTypeID }) {
                activity.types.remove(at: index)
            }
        }
    }

    private func removeExercise(_ exerciseID: UUID, fromAllExcept trainingTypeID: UUID) throws {
        let trainingTypes = try modelContext.fetch(FetchDescriptor<TrainingType>())
        for trainingType in trainingTypes where trainingType.id != trainingTypeID {
            if let index = trainingType.exercises.firstIndex(where: { $0.id == exerciseID }) {
                trainingType.exercises.remove(at: index)
            }
        }
    }

    private func removeBoulderCombination(_ combinationID: UUID, fromAllExcept trainingTypeID: UUID) throws {
        let trainingTypes = try modelContext.fetch(FetchDescriptor<TrainingType>())
        for trainingType in trainingTypes where trainingType.id != trainingTypeID {
            if let index = trainingType.combinations.firstIndex(where: { $0.id == combinationID }) {
                trainingType.combinations.remove(at: index)
            }
        }
    }

    private func removeBoulderCombinationExercise(linkID: UUID) throws {
        let trainingTypes = try modelContext.fetch(FetchDescriptor<TrainingType>())
        for trainingType in trainingTypes {
            for combination in trainingType.combinations {
                guard let exercise = combination.exercises.first(where: { exercise in
                    Self.boulderCombinationExerciseLinkID(
                        combinationID: combination.id,
                        exerciseID: exercise.id
                    ) == linkID
                }) else {
                    continue
                }
                combination.exercises.removeAll { $0.id == exercise.id }
                return
            }
        }
    }

    private func removeTimerInterval(_ intervalID: UUID, fromAllExcept templateID: UUID) throws {
        let templates = try modelContext.fetch(FetchDescriptor<TimerTemplate>())
        for template in templates where template.id != templateID {
            if let index = template.intervals.firstIndex(where: { $0.id == intervalID }) {
                template.intervals.remove(at: index)
            }
        }
    }

    private func removeTimerLap(_ lapID: UUID, fromAllExcept sessionID: UUID) throws {
        let sessions = try modelContext.fetch(FetchDescriptor<TimerSession>())
        for session in sessions where session.id != sessionID {
            if let index = session.laps.firstIndex(where: { $0.id == lapID }) {
                session.laps.remove(at: index)
            }
        }
    }

    private func saveIfNeeded() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    private func compactLocalTombstonesIfNeeded(retentionDays: Int) throws {
        let retention = max(1, retentionDays)
        let cutoff = Date.now.addingTimeInterval(-Double(retention) * 24 * 60 * 60)

        func deleteTombstones<T: PersistentModel & SyncLocallyMutable>(
            of type: T.Type,
            where matches: (T) -> Bool
        ) throws {
            let rows = try modelContext.fetch(FetchDescriptor<T>())
            for row in rows where matches(row) {
                modelContext.delete(row)
            }
        }

        try deleteTombstones(of: PlanKindModel.self) { $0.isSoftDeleted && $0.syncVersion > 0 && $0.updatedAtClient < cutoff }
        try deleteTombstones(of: DayTypeModel.self) { $0.isSoftDeleted && $0.syncVersion > 0 && $0.updatedAtClient < cutoff }
        try deleteTombstones(of: Plan.self) { $0.isSoftDeleted && $0.syncVersion > 0 && $0.updatedAtClient < cutoff }
        try deleteTombstones(of: PlanDay.self) { $0.isSoftDeleted && $0.syncVersion > 0 && $0.updatedAtClient < cutoff }
        try deleteTombstones(of: Activity.self) { $0.isSoftDeleted && $0.syncVersion > 0 && $0.updatedAtClient < cutoff }
        try deleteTombstones(of: TrainingType.self) { $0.isSoftDeleted && $0.syncVersion > 0 && $0.updatedAtClient < cutoff }
        try deleteTombstones(of: Exercise.self) { $0.isSoftDeleted && $0.syncVersion > 0 && $0.updatedAtClient < cutoff }
        try deleteTombstones(of: BoulderCombination.self) { $0.isSoftDeleted && $0.syncVersion > 0 && $0.updatedAtClient < cutoff }
        try deleteTombstones(of: Session.self) { $0.isSoftDeleted && $0.syncVersion > 0 && $0.updatedAtClient < cutoff }
        try deleteTombstones(of: SessionItem.self) { $0.isSoftDeleted && $0.syncVersion > 0 && $0.updatedAtClient < cutoff }
        try deleteTombstones(of: TimerTemplate.self) { $0.isSoftDeleted && $0.syncVersion > 0 && $0.updatedAtClient < cutoff }
        try deleteTombstones(of: TimerInterval.self) { $0.isSoftDeleted && $0.syncVersion > 0 && $0.updatedAtClient < cutoff }
        try deleteTombstones(of: TimerSession.self) { $0.isSoftDeleted && $0.syncVersion > 0 && $0.updatedAtClient < cutoff }
        try deleteTombstones(of: TimerLap.self) { $0.isSoftDeleted && $0.syncVersion > 0 && $0.updatedAtClient < cutoff }
        try deleteTombstones(of: ClimbEntry.self) { $0.isSoftDeleted && $0.syncVersion > 0 && $0.updatedAtClient < cutoff }
        try deleteTombstones(of: ClimbStyle.self) { $0.isSoftDeleted && $0.syncVersion > 0 && $0.updatedAtClient < cutoff }
        try deleteTombstones(of: ClimbGym.self) { $0.isSoftDeleted && $0.syncVersion > 0 && $0.updatedAtClient < cutoff }
    }

    private func ensureSyncStateModel() throws -> SyncState {
        let descriptor = FetchDescriptor<SyncState>()
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let created = SyncState()
        modelContext.insert(created)
        try saveIfNeeded()
        return created
    }

    nonisolated static func boulderCombinationExerciseLinkID(
        combinationID: UUID,
        exerciseID: UUID
    ) -> UUID {
        let raw = "\(combinationID.uuidString.lowercased())|\(exerciseID.uuidString.lowercased())"
        let digest = SHA256.hash(data: Data(raw.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuidBytes: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuidBytes)
    }

}

private extension SyncState {
    var snapshot: SyncStateSnapshot {
        SyncStateSnapshot(
            id: id,
            userId: userId,
            deviceId: deviceId,
            lastCursor: lastCursor,
            lastSuccessfulSyncAt: lastSuccessfulSyncAt,
            isSyncEnabled: isSyncEnabled
        )
    }
}

private extension String {
    func asISO8601Date() -> Date? {
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601.date(from: self) {
            return date
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: self)
    }
}

private extension Date {
    var iso8601WithFractionalSeconds: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}
