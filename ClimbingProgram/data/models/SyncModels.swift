//
//  SyncModels.swift
//  klettrack
//
//  Created by Shahar Noy on 10.02.26.
//

import Foundation
import SwiftData

@Model
final class SyncState {
    var id: String = "default"
    var userId: String? = nil
    var deviceId: String = UUID().uuidString
    var lastCursor: String? = nil
    var lastSuccessfulSyncAt: Date? = nil
    var isSyncEnabled: Bool = false
    var didBootstrapLocalSnapshot: Bool = false

    init(
        id: String = "default",
        userId: String? = nil,
        deviceId: String = UUID().uuidString,
        lastCursor: String? = nil,
        lastSuccessfulSyncAt: Date? = nil,
        isSyncEnabled: Bool = false,
        didBootstrapLocalSnapshot: Bool = false
    ) {
        self.id = id
        self.userId = userId
        self.deviceId = deviceId
        self.lastCursor = lastCursor
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.isSyncEnabled = isSyncEnabled
        self.didBootstrapLocalSnapshot = didBootstrapLocalSnapshot
    }
}

@Model
final class SyncMutation {
    var opId: UUID = UUID()
    var entityName: String = ""
    var entityId: UUID = UUID()
    var mutationType: String = "upsert"
    var baseVersion: Int = 0
    var payloadJSON: String = "{}"
    var createdAt: Date = Date.now
    var updatedAtClient: Date? = nil
    var attempts: Int = 0
    var lastError: String? = nil

    init(
        opId: UUID = UUID(),
        entityName: String = "",
        entityId: UUID = UUID(),
        mutationType: String = "upsert",
        baseVersion: Int = 0,
        payloadJSON: String = "{}",
        createdAt: Date = Date.now,
        updatedAtClient: Date? = nil,
        attempts: Int = 0,
        lastError: String? = nil
    ) {
        self.opId = opId
        self.entityName = entityName
        self.entityId = entityId
        self.mutationType = mutationType
        self.baseVersion = baseVersion
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
        self.updatedAtClient = updatedAtClient
        self.attempts = attempts
        self.lastError = lastError
    }
}
