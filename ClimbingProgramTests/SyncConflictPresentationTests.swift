//
//  SyncConflictPresentationTests.swift
//  Klettrack tests
//  Created by Shahar Noy on 17.02.26.
//
import XCTest
@testable import klettrack

final class SyncConflictPresentationTests: XCTestCase {
    func testConflictDisplayReasonMapsVersionMismatch() {
        let conflict = SyncPushConflict(
            opId: UUID().uuidString,
            entity: .planDays,
            entityId: UUID().uuidString,
            reason: "version_mismatch",
            serverVersion: 3,
            serverDoc: nil
        )

        XCTAssertEqual(conflict.displayReason, "This item changed on another device.")
    }

    func testConflictAuditStorePersistsLatestEvent() async {
        guard let defaults = UserDefaults(suiteName: "SyncConflictAuditStoreTests") else {
            XCTFail("Expected isolated UserDefaults suite for audit store test.")
            return
        }
        defaults.removePersistentDomain(forName: "SyncConflictAuditStoreTests")

        let store = SyncConflictAuditStore(defaults: defaults)
        let event = SyncConflictTelemetryEvent(
            eventType: .keepMine,
            entity: "plans",
            entityId: UUID().uuidString,
            reason: "version_mismatch"
        )

        await store.append(event: event)

        let data = defaults.data(forKey: "sync.conflict.audit.events")
        XCTAssertNotNil(data)
    }

    func testConflictServerPreviewRowsProvidesSortedReadableValues() {
        let conflict = SyncPushConflict(
            opId: UUID().uuidString,
            entity: .plans,
            entityId: UUID().uuidString,
            reason: "version_mismatch",
            serverVersion: 7,
            serverDoc: [
                "z_name": .string("Moonboard"),
                "a_is_deleted": .bool(false),
                "b_order": .number(2)
            ]
        )

        XCTAssertEqual(conflict.displayServerVersion, "7")
        XCTAssertEqual(conflict.serverPreviewRows.map(\.key), ["a_is_deleted", "b_order", "z_name"])
        XCTAssertEqual(conflict.serverPreviewRows.first?.value, "false")
    }
}
