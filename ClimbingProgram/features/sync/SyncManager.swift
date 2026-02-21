//
//  SyncManager.swift
//  klettrack
//
//  Created by Shahar Noy on 10.02.26.
//

import Foundation
import Observation

@MainActor
@Observable
final class SyncManager {
    private enum AutoConflictResolution {
        case keepMine
        case keepServer
        case manualReview
    }

    enum State: Equatable {
        case idle
        case syncing
        case conflict(Int)
        case failed(String)
    }

    private let apiClient: SyncAPIClient
    private let store: SyncStoreActor
    private let auditStore: SyncConflictAuditStore
    private let debouncer = SyncDebouncer()
    private let retryDebouncer = SyncDebouncer()

    private(set) var state: State = .idle
    private(set) var lastSyncAt: Date?
    private(set) var conflicts: [SyncPushConflict] = []
    private(set) var telemetryEvents: [SyncConflictTelemetryEvent] = []
    private(set) var triggerMetrics = SyncTriggerMetrics()

    private var syncTask: Task<Void, Never>?
    private var queuedSyncRequest = false
    private var consecutiveFailureCount = 0

    private let maxAutomaticRetryCount = 5
    private let maxAutomaticRetryDelaySeconds = 60.0
    init(apiClient: SyncAPIClient, store: SyncStoreActor, auditStore: SyncConflictAuditStore = .shared) {
        self.apiClient = apiClient
        self.store = store
        self.auditStore = auditStore
    }

    func setSyncEnabled(_ isEnabled: Bool, userId: String?) async {
        do {
            try await store.setSyncEnabled(isEnabled, userId: userId)
            if isEnabled {
                consecutiveFailureCount = 0
                triggerSync(reason: "sync_enabled")
            } else {
                consecutiveFailureCount = 0
                conflicts = []
                state = .idle
            }
        } catch {
            state = .failed("Unable to update sync state.")
        }
    }

    @discardableResult
    func enqueueLocalMutation(
        entity: SyncEntityName,
        entityId: UUID,
        mutationType: SyncMutationType,
        baseVersion: Int,
        payload: [String: JSONValue],
        updatedAtClient: Date = .now,
        debounce: Duration = .seconds(2)
    ) async -> Bool {
        do {
            _ = try await store.enqueueMutation(
                entity: entity,
                entityId: entityId,
                mutationType: mutationType,
                baseVersion: baseVersion,
                payload: payload,
                updatedAtClient: updatedAtClient
            )

            await debouncer.schedule(after: debounce) { [weak self] in
                await self?.triggerSync(reason: "local_debounce")
            }
            return true
        } catch {
            state = .failed("Unable to enqueue local change.")
            return false
        }
    }

    func triggerSync(reason: String) {
        triggerMetrics.recordTrigger(reason: reason)
        Task { [weak self] in
            await self?.startSyncIfNeeded()
        }
    }

    func runSyncNow(reason: String) async {
        triggerMetrics.recordTrigger(reason: reason)
        await startSyncIfNeeded()
        await syncTask?.value
    }

    @discardableResult
    func resolveConflictKeepMine(_ conflict: SyncPushConflict) async -> Bool {
        await resolveConflictKeepMine(conflict, triggerSyncAfterResolution: true)
    }

    @discardableResult
    func resolveAllConflictsKeepMine() async -> Int {
        let pendingConflicts = conflicts
        guard !pendingConflicts.isEmpty else { return 0 }

        var resolvedCount = 0
        for conflict in pendingConflicts {
            if await resolveConflictKeepMine(conflict, triggerSyncAfterResolution: false) {
                resolvedCount += 1
            }
        }

        if resolvedCount > 0 {
            triggerSync(reason: "resolve_all_keep_mine")
        }
        return resolvedCount
    }

    @discardableResult
    private func resolveConflictKeepMine(_ conflict: SyncPushConflict, triggerSyncAfterResolution: Bool) async -> Bool {
        do {
            let resolved = try await store.resolveConflictKeepMine(
                opId: conflict.opId,
                serverVersion: conflict.serverVersion
            )
            guard resolved else { return false }
            removeConflict(opId: conflict.opId)
            recordTelemetry(eventType: .keepMine, conflict: conflict)
            if triggerSyncAfterResolution {
                triggerSync(reason: "resolve_keep_mine")
            }
            return true
        } catch {
            state = .failed("Unable to apply Keep Mine resolution.")
            return false
        }
    }

    @discardableResult
    func resolveConflictKeepServer(_ conflict: SyncPushConflict) async -> Bool {
        await resolveConflictKeepServer(conflict, triggerSyncAfterResolution: true)
    }

    @discardableResult
    func resolveAllConflictsKeepServer() async -> Int {
        let pendingConflicts = conflicts
        guard !pendingConflicts.isEmpty else { return 0 }

        var resolvedCount = 0
        for conflict in pendingConflicts {
            if await resolveConflictKeepServer(conflict, triggerSyncAfterResolution: false) {
                resolvedCount += 1
            }
        }

        if resolvedCount > 0 {
            triggerSync(reason: "resolve_all_keep_server")
        }
        return resolvedCount
    }

    @discardableResult
    private func resolveConflictKeepServer(_ conflict: SyncPushConflict, triggerSyncAfterResolution: Bool) async -> Bool {
        do {
            let resolved = try await store.resolveConflictKeepServer(opId: conflict.opId)
            guard resolved else { return false }
            removeConflict(opId: conflict.opId)
            recordTelemetry(eventType: .keepServer, conflict: conflict)
            if triggerSyncAfterResolution {
                triggerSync(reason: "resolve_keep_server")
            }
            return true
        } catch {
            state = .failed("Unable to apply Keep Server resolution.")
            return false
        }
    }

    private func startSyncIfNeeded() async {
        if syncTask != nil {
            queuedSyncRequest = true
            return
        }

        syncTask = Task { [weak self] in
            guard let self else { return }
            await self.runSyncLoop()
        }
    }

    private func runSyncLoop() async {
        defer {
            syncTask = nil
        }

        while true {
            queuedSyncRequest = false

            do {
                try await performSingleSyncCycle()
            } catch is CancellationError {
                state = .idle
            } catch {
                consecutiveFailureCount += 1
                triggerMetrics.recordFailure()
                state = .failed("Sync failed. Please try again.")
                await scheduleAutomaticRetryIfNeeded()
            }

            if !queuedSyncRequest {
                break
            }
        }
    }

    private func performSingleSyncCycle() async throws {
        let syncState = try await store.loadOrCreateSyncState()
        guard syncState.isSyncEnabled else {
            state = .idle
            return
        }

        _ = try await store.enqueueLocalSnapshotIfNeeded()

        state = .syncing

        let pushConflicts = try await pushPendingMutations(baseCursor: syncState.lastCursor, deviceId: syncState.deviceId)
        conflicts = pushConflicts
        try await pullAllChanges(cursor: syncState.lastCursor)

        consecutiveFailureCount = 0
        lastSyncAt = .now
        if !pushConflicts.isEmpty {
            state = .conflict(pushConflicts.count)
        } else {
            state = .idle
        }
    }

    private func pushPendingMutations(baseCursor: String?, deviceId: String) async throws -> [SyncPushConflict] {
        var conflictMap: [String: SyncPushConflict] = [:]

        while true {
            let pending = try await store.fetchPendingMutations(limit: 100)
            guard !pending.isEmpty else { break }

            let request = SyncPushRequest(
                deviceId: deviceId,
                baseCursor: baseCursor,
                mutations: pending.map { mutation in
                    SyncPushMutationRequest(
                        opId: mutation.opId.uuidString.lowercased(),
                        entity: mutation.entity,
                        entityId: mutation.entityId.uuidString.lowercased(),
                        type: mutation.mutationType,
                        baseVersion: mutation.baseVersion,
                        updatedAtClient: mutation.updatedAtClient?.iso8601WithFractionalSeconds,
                        payload: mutation.mutationType == .delete ? nil : mutation.payload
                    )
                }
            )

            let response = try await apiClient.push(request: request)
            let unresolvedConflicts = try await resolveVersionConflictsAutomatically(
                response.conflicts,
                deviceId: deviceId
            )
            let processedResponse = SyncPushResponse(
                acknowledgedOpIds: response.acknowledgedOpIds,
                conflicts: unresolvedConflicts,
                failed: response.failed,
                newCursor: response.newCursor
            )
            let processingResult = try await store.processPushResponse(processedResponse)

            for conflict in unresolvedConflicts {
                conflictMap[conflict.opId.lowercased()] = conflict
                recordTelemetry(eventType: .detected, conflict: conflict)
            }

            if processingResult.acknowledged == 0 && (processingResult.failures > 0 || processingResult.conflicts > 0) {
                break
            }
        }

        return Array(conflictMap.values)
    }

    private func resolveVersionConflictsAutomatically(
        _ conflicts: [SyncPushConflict],
        deviceId: String
    ) async throws -> [SyncPushConflict] {
        var unresolved: [SyncPushConflict] = []

        for conflict in conflicts {
            guard conflict.reason.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase == "version_mismatch" else {
                unresolved.append(conflict)
                continue
            }

            guard let pending = try await store.fetchPendingMutation(opId: conflict.opId) else {
                unresolved.append(conflict)
                continue
            }

            let strategy = automaticResolutionStrategy(
                conflict: conflict,
                pending: pending,
                deviceId: deviceId
            )
            switch strategy {
            case .keepMine:
                let resolved = try await store.resolveConflictKeepMine(
                    opId: conflict.opId,
                    serverVersion: conflict.serverVersion
                )
                if resolved {
                    recordTelemetry(eventType: .keepMine, conflict: conflict)
                } else {
                    unresolved.append(conflict)
                }

            case .keepServer:
                let resolved = try await store.resolveConflictKeepServer(opId: conflict.opId)
                if resolved {
                    recordTelemetry(eventType: .keepServer, conflict: conflict)
                } else {
                    unresolved.append(conflict)
                }

            case .manualReview:
                unresolved.append(conflict)
            }
        }

        return unresolved
    }

    private func automaticResolutionStrategy(
        conflict: SyncPushConflict,
        pending: PendingSyncMutation,
        deviceId: String
    ) -> AutoConflictResolution {
        if Self.shouldPreferServerTombstone(serverDoc: conflict.serverDoc) {
            // Tombstones should dominate stale local upserts to avoid row resurrection.
            return .keepServer
        }

        if pending.mutationType == .delete {
            // For existing rows, keep local delete intent and rebase to server version.
            // If server row is already missing, dropping local delete is safe.
            return conflict.serverVersion == nil ? .keepServer : .keepMine
        }

        if conflict.serverVersion == nil {
            // Missing server row on first-account/bootstrap sync:
            // local upserts should create it.
            return .keepMine
        }

        let serverUpdatedAt = Self.extractServerUpdatedAt(serverDoc: conflict.serverDoc)
        let localUpdatedAt = pending.updatedAtClient

        if let localUpdatedAt, let serverUpdatedAt {
            if localUpdatedAt > serverUpdatedAt {
                return .keepMine
            }
            if localUpdatedAt < serverUpdatedAt {
                return .keepServer
            }
        } else if localUpdatedAt != nil {
            return .keepMine
        } else if serverUpdatedAt != nil {
            return .keepServer
        }

        let localTieBreaker = "\(deviceId.lowercased())|\(pending.opId.uuidString.lowercased())"
        let serverTieBreaker = conflict.serverDoc?["last_op_id"]?.stringValue?.lowercased() ?? ""
        return Self.shouldKeepMineLWW(
            localUpdatedAt: localUpdatedAt,
            serverUpdatedAt: serverUpdatedAt,
            localTieBreaker: localTieBreaker,
            serverTieBreaker: serverTieBreaker
        ) ? .keepMine : .keepServer
    }

    private func pullAllChanges(cursor: String?) async throws {
        var currentCursor = cursor

        while true {
            let response = try await apiClient.pull(request: SyncPullRequest(cursor: currentCursor, limit: 200))
            try await store.applyPullResponse(response)
            currentCursor = response.nextCursor

            if !response.hasMore {
                break
            }
        }
    }

    private func removeConflict(opId: String) {
        conflicts.removeAll { $0.opId.caseInsensitiveCompare(opId) == .orderedSame }
        if conflicts.isEmpty, case .conflict = state {
            state = .idle
        } else if case .conflict = state {
            state = .conflict(conflicts.count)
        }
    }

    private func recordTelemetry(eventType: SyncConflictTelemetryEvent.EventType, conflict: SyncPushConflict) {
        let event = SyncConflictTelemetryEvent(
            eventType: eventType,
            entity: conflict.entity.rawValue,
            entityId: conflict.entityId,
            reason: conflict.reason
        )

        telemetryEvents.insert(event, at: 0)

        if telemetryEvents.count > 50 {
            telemetryEvents.removeLast(telemetryEvents.count - 50)
        }

        Task {
            await auditStore.append(event: event)
        }
    }

    private func scheduleAutomaticRetryIfNeeded() async {
        guard consecutiveFailureCount > 0 else { return }
        guard consecutiveFailureCount <= maxAutomaticRetryCount else { return }

        guard let syncState = try? await store.loadOrCreateSyncState(), syncState.isSyncEnabled else {
            return
        }

        let jitterSeconds = Double.random(in: 0...0.25)
        let delaySeconds = Self.automaticRetryDelaySeconds(
            failureCount: consecutiveFailureCount,
            jitterSeconds: jitterSeconds,
            maxDelaySeconds: maxAutomaticRetryDelaySeconds
        )

        await retryDebouncer.schedule(after: .seconds(delaySeconds)) { [weak self] in
            await self?.triggerSync(reason: "auto_retry")
        }
    }

    nonisolated static func automaticRetryDelaySeconds(
        failureCount: Int,
        jitterSeconds: Double,
        maxDelaySeconds: Double
    ) -> Double {
        let normalizedFailureCount = max(1, failureCount)
        let normalizedJitter = min(max(0, jitterSeconds), 0.25)
        let maxDelay = max(1, maxDelaySeconds)
        let exponential = pow(2, Double(normalizedFailureCount - 1))
        let boundedBase = min(exponential, maxDelay)
        return min(boundedBase + normalizedJitter, maxDelay)
    }

    nonisolated static func isLocalClearlyNewer(
        localUpdatedAt: Date?,
        serverUpdatedAt: Date?,
        thresholdSeconds: Double
    ) -> Bool {
        guard let localUpdatedAt, let serverUpdatedAt else {
            return false
        }
        let threshold = max(1, thresholdSeconds)
        return localUpdatedAt.timeIntervalSince(serverUpdatedAt) >= threshold
    }

    nonisolated static func isHighRiskConflict(
        mutationType: SyncMutationType,
        localPayload: [String: JSONValue],
        serverDoc: [String: JSONValue]?
    ) -> Bool {
        if mutationType == .delete {
            return true
        }

        let sensitiveKeyFragments = ["note", "description", "comment", "summary"]
        let localSensitive = localPayload.keys.contains { key in
            let normalized = key.localizedLowercase
            return sensitiveKeyFragments.contains(where: normalized.contains)
        }
        if localSensitive {
            return true
        }

        if localPayload.values.contains(where: Self.isLongTextValue) {
            return true
        }

        if let serverDoc {
            if serverDoc.values.contains(where: Self.isLongTextValue) {
                return true
            }
        }

        return false
    }

    nonisolated static func shouldKeepMineLWW(
        localUpdatedAt: Date?,
        serverUpdatedAt: Date?,
        localTieBreaker: String,
        serverTieBreaker: String
    ) -> Bool {
        if let localUpdatedAt, let serverUpdatedAt {
            if localUpdatedAt > serverUpdatedAt {
                return true
            }
            if localUpdatedAt < serverUpdatedAt {
                return false
            }
        } else if localUpdatedAt != nil {
            return true
        } else if serverUpdatedAt != nil {
            return false
        }

        return localTieBreaker.localizedCompare(serverTieBreaker) == .orderedDescending
    }

    nonisolated static func shouldPreferServerTombstone(serverDoc: [String: JSONValue]?) -> Bool {
        serverDoc?["is_deleted"]?.boolValue ?? false
    }

    private nonisolated static func isLongTextValue(_ value: JSONValue) -> Bool {
        guard case .string(let text) = value else { return false }
        return text.count >= 140
    }

    private nonisolated static func extractServerUpdatedAt(serverDoc: [String: JSONValue]?) -> Date? {
        guard let serverDoc else { return nil }

        if let updatedAtClient = serverDoc["updated_at_client"]?.stringValue,
           let parsed = updatedAtClient.asISO8601Date {
            return parsed
        }

        if let updatedAt = serverDoc["updated_at"]?.stringValue,
           let parsed = updatedAt.asISO8601Date {
            return parsed
        }

        return nil
    }
}

struct SyncConflictTelemetryEvent: Sendable, Identifiable, Codable {
    enum EventType: String, Sendable, Codable {
        case detected
        case keepMine
        case keepServer
    }

    let id: UUID
    let eventType: EventType
    let timestamp: Date
    let entity: String
    let entityId: String
    let reason: String

    init(id: UUID = UUID(), eventType: EventType, entity: String, entityId: String, reason: String, timestamp: Date = .now) {
        self.id = id
        self.eventType = eventType
        self.entity = entity
        self.entityId = entityId
        self.reason = reason
        self.timestamp = timestamp
    }
}

struct SyncTriggerMetrics: Sendable {
    private(set) var totalTriggerCount = 0
    private(set) var failureCount = 0
    private(set) var lastTriggerAt: Date?
    private(set) var triggerCountByReason: [String: Int] = [:]

    mutating func recordTrigger(reason: String, at date: Date = .now) {
        let normalized = Self.normalizedReason(reason)
        totalTriggerCount += 1
        lastTriggerAt = date
        triggerCountByReason[normalized, default: 0] += 1
    }

    mutating func recordFailure() {
        failureCount += 1
    }

    nonisolated static func normalizedReason(_ reason: String) -> String {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unspecified" : trimmed
    }
}

private extension Date {
    var iso8601WithFractionalSeconds: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}

private extension String {
    var asISO8601Date: Date? {
        let withFractions = ISO8601DateFormatter()
        withFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = withFractions.date(from: self) {
            return parsed
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: self)
    }
}
