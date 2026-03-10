//
//  SyncManagerTests.swift
//  Klettrack tests
//  Created by Shahar Noy on 17.02.26.
//
import XCTest
@testable import klettrack

final class SyncManagerTests: XCTestCase {
    func testAutomaticRetryDelayUsesExponentialBackoff() {
        let first = SyncManager.automaticRetryDelaySeconds(
            failureCount: 1,
            jitterSeconds: 0,
            maxDelaySeconds: 60
        )
        let second = SyncManager.automaticRetryDelaySeconds(
            failureCount: 2,
            jitterSeconds: 0,
            maxDelaySeconds: 60
        )
        let third = SyncManager.automaticRetryDelaySeconds(
            failureCount: 3,
            jitterSeconds: 0,
            maxDelaySeconds: 60
        )

        XCTAssertEqual(first, 1, accuracy: 0.001)
        XCTAssertEqual(second, 2, accuracy: 0.001)
        XCTAssertEqual(third, 4, accuracy: 0.001)
    }

    func testAutomaticRetryDelayCapsAtMaxDelay() {
        let capped = SyncManager.automaticRetryDelaySeconds(
            failureCount: 10,
            jitterSeconds: 0.25,
            maxDelaySeconds: 8
        )

        XCTAssertEqual(capped, 8, accuracy: 0.001)
    }

    func testAutomaticRetryDelayNormalizesNegativeInputs() {
        let delay = SyncManager.automaticRetryDelaySeconds(
            failureCount: 0,
            jitterSeconds: -1,
            maxDelaySeconds: 10
        )

        XCTAssertEqual(delay, 1, accuracy: 0.001)
    }

    func testSyncTriggerMetricsNormalizesBlankReasons() {
        var metrics = SyncTriggerMetrics()
        metrics.recordTrigger(reason: "   ")

        XCTAssertEqual(metrics.totalTriggerCount, 1)
        XCTAssertEqual(metrics.triggerCountByReason["unspecified"], 1)
    }

    func testSyncTriggerMetricsTracksReasonCountsAndFailures() {
        var metrics = SyncTriggerMetrics()
        metrics.recordTrigger(reason: "manual")
        metrics.recordTrigger(reason: "manual")
        metrics.recordTrigger(reason: "background_refresh")
        metrics.recordFailure()

        XCTAssertEqual(metrics.totalTriggerCount, 3)
        XCTAssertEqual(metrics.failureCount, 1)
        XCTAssertEqual(metrics.triggerCountByReason["manual"], 2)
        XCTAssertEqual(metrics.triggerCountByReason["background_refresh"], 1)
    }

    func testIsLocalClearlyNewerRespectsThreshold() {
        let server = Date(timeIntervalSince1970: 1_000)
        let localClearlyNewer = server.addingTimeInterval(35)
        let localNotNewEnough = server.addingTimeInterval(10)

        XCTAssertTrue(
            SyncManager.isLocalClearlyNewer(
                localUpdatedAt: localClearlyNewer,
                serverUpdatedAt: server,
                thresholdSeconds: 30
            )
        )
        XCTAssertFalse(
            SyncManager.isLocalClearlyNewer(
                localUpdatedAt: localNotNewEnough,
                serverUpdatedAt: server,
                thresholdSeconds: 30
            )
        )
    }

    func testIsHighRiskConflictTreatsDeletesAndNotesAsManualReview() {
        XCTAssertTrue(
            SyncManager.isHighRiskConflict(
                mutationType: .delete,
                localPayload: [:],
                serverDoc: nil
            )
        )
        XCTAssertTrue(
            SyncManager.isHighRiskConflict(
                mutationType: .upsert,
                localPayload: ["daily_notes": .string("brief note")],
                serverDoc: nil
            )
        )
    }

    func testIsHighRiskConflictTreatsLongTextAsManualReview() {
        let longText = String(repeating: "x", count: 200)
        XCTAssertTrue(
            SyncManager.isHighRiskConflict(
                mutationType: .upsert,
                localPayload: ["name": .string(longText)],
                serverDoc: nil
            )
        )
    }

    func testShouldKeepMineLWWPrefersNewerLocalTimestamp() {
        let server = Date(timeIntervalSince1970: 2_000)
        let local = server.addingTimeInterval(5)

        XCTAssertTrue(
            SyncManager.shouldKeepMineLWW(
                localUpdatedAt: local,
                serverUpdatedAt: server,
                localTieBreaker: "device-a|op-a",
                serverTieBreaker: "device-b|op-b"
            )
        )
    }

    func testShouldKeepMineLWWFallsBackToDeterministicTieBreaker() {
        let timestamp = Date(timeIntervalSince1970: 2_000)

        XCTAssertTrue(
            SyncManager.shouldKeepMineLWW(
                localUpdatedAt: timestamp,
                serverUpdatedAt: timestamp,
                localTieBreaker: "z-device|z-op",
                serverTieBreaker: "a-device|a-op"
            )
        )
        XCTAssertFalse(
            SyncManager.shouldKeepMineLWW(
                localUpdatedAt: timestamp,
                serverUpdatedAt: timestamp,
                localTieBreaker: "a-device|a-op",
                serverTieBreaker: "z-device|z-op"
            )
        )
    }

    func testShouldPreferServerTombstoneWhenServerIsDeleted() {
        XCTAssertTrue(
            SyncManager.shouldPreferServerTombstone(
                serverDoc: ["is_deleted": .bool(true)]
            )
        )
    }

    func testShouldPreferServerTombstoneFalseWhenServerIsActive() {
        XCTAssertFalse(
            SyncManager.shouldPreferServerTombstone(
                serverDoc: ["is_deleted": .bool(false)]
            )
        )
        XCTAssertFalse(
            SyncManager.shouldPreferServerTombstone(
                serverDoc: ["name": .string("Plan")]
            )
        )
    }

    func testPersistedLastSyncAtReturnsStoredValueWhenSyncEnabled() {
        let date = Date(timeIntervalSince1970: 1_234_567)
        let syncState = SyncStateSnapshot(
            id: "default",
            userId: "user-a",
            deviceId: "device-a",
            lastCursor: "cursor-1",
            lastSuccessfulSyncAt: date,
            lastBootstrapSnapshotAt: nil,
            isSyncEnabled: true,
            didBootstrapLocalSnapshot: true
        )

        XCTAssertEqual(SyncManager.persistedLastSyncAt(syncState: syncState), date)
    }

    func testPersistedLastSyncAtClearsWhenSyncDisabled() {
        let syncState = SyncStateSnapshot(
            id: "default",
            userId: "user-a",
            deviceId: "device-a",
            lastCursor: "cursor-1",
            lastSuccessfulSyncAt: Date(timeIntervalSince1970: 1_234_567),
            lastBootstrapSnapshotAt: nil,
            isSyncEnabled: false,
            didBootstrapLocalSnapshot: false
        )

        XCTAssertNil(SyncManager.persistedLastSyncAt(syncState: syncState))
    }

    func testShouldFlagSuspiciousResnapshotSkipsWhenQueueIsDraining() {
        let now = Date(timeIntervalSince1970: 20_000)
        let syncState = SyncStateSnapshot(
            id: "default",
            userId: "user-a",
            deviceId: "device-a",
            lastCursor: "cursor-1",
            lastSuccessfulSyncAt: now.addingTimeInterval(-30),
            lastBootstrapSnapshotAt: now.addingTimeInterval(-300),
            isSyncEnabled: true,
            didBootstrapLocalSnapshot: true
        )
        let priorDiagnostics = [
            SyncCycleDiagnostics(
                timestamp: now.addingTimeInterval(-180),
                queueSizeAtStart: 650,
                durationSeconds: 1,
                acknowledgedCount: 5,
                noopCount: 0,
                conflictCount: 0,
                failedCount: 0
            ),
            SyncCycleDiagnostics(
                timestamp: now.addingTimeInterval(-60),
                queueSizeAtStart: 520,
                durationSeconds: 1,
                acknowledgedCount: 5,
                noopCount: 0,
                conflictCount: 0,
                failedCount: 0
            )
        ]

        XCTAssertFalse(
            SyncManager.shouldFlagSuspiciousResnapshot(
                pendingQueueCount: 470,
                syncState: syncState,
                queueThreshold: 400,
                queueObservationCount: 3,
                priorCycleDiagnostics: priorDiagnostics
            )
        )
    }

    func testShouldFlagSuspiciousResnapshotTriggersWhenHighQueueStagnates() {
        let now = Date(timeIntervalSince1970: 20_000)
        let syncState = SyncStateSnapshot(
            id: "default",
            userId: "user-a",
            deviceId: "device-a",
            lastCursor: "cursor-1",
            lastSuccessfulSyncAt: now.addingTimeInterval(-30),
            lastBootstrapSnapshotAt: now.addingTimeInterval(-300),
            isSyncEnabled: true,
            didBootstrapLocalSnapshot: true
        )
        let priorDiagnostics = [
            SyncCycleDiagnostics(
                timestamp: now.addingTimeInterval(-180),
                queueSizeAtStart: 510,
                durationSeconds: 1,
                acknowledgedCount: 2,
                noopCount: 0,
                conflictCount: 0,
                failedCount: 0
            ),
            SyncCycleDiagnostics(
                timestamp: now.addingTimeInterval(-60),
                queueSizeAtStart: 520,
                durationSeconds: 1,
                acknowledgedCount: 1,
                noopCount: 0,
                conflictCount: 0,
                failedCount: 0
            )
        ]

        XCTAssertTrue(
            SyncManager.shouldFlagSuspiciousResnapshot(
                pendingQueueCount: 540,
                syncState: syncState,
                queueThreshold: 400,
                queueObservationCount: 3,
                priorCycleDiagnostics: priorDiagnostics
            )
        )
    }
}
