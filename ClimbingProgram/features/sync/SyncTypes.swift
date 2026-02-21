//
//  SyncTypes.swift
//  klettrack
//
//  Created by Shahar Noy on 10.02.26.
//

import Foundation

enum SyncEntityName: String, CaseIterable, Codable, Sendable {
    case planKinds = "plan_kinds"
    case dayTypes = "day_types"
    case plans
    case planDays = "plan_days"
    case activities
    case trainingTypes = "training_types"
    case exercises
    case boulderCombinations = "boulder_combinations"
    case boulderCombinationExercises = "boulder_combination_exercises"
    case sessions
    case sessionItems = "session_items"
    case timerTemplates = "timer_templates"
    case timerIntervals = "timer_intervals"
    case timerSessions = "timer_sessions"
    case timerLaps = "timer_laps"
    case climbEntries = "climb_entries"
    case climbStyles = "climb_styles"
    case climbGyms = "climb_gyms"
}

enum SyncMutationType: String, Codable, Sendable {
    case upsert
    case delete
}

enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }
        if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
            return
        }
        if let intValue = try? container.decode(Int.self) {
            self = .number(Double(intValue))
            return
        }
        if let doubleValue = try? container.decode(Double.self) {
            self = .number(doubleValue)
            return
        }
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }
        if let arrayValue = try? container.decode([JSONValue].self) {
            self = .array(arrayValue)
            return
        }
        if let objectValue = try? container.decode([String: JSONValue].self) {
            self = .object(objectValue)
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

extension JSONValue {
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .number(let value) = self else { return nil }
        return Int(value)
    }

    var numberValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }
}

struct SyncPushMutationRequest: Codable, Sendable {
    let opId: String
    let entity: SyncEntityName
    let entityId: String
    let type: SyncMutationType
    let baseVersion: Int
    let updatedAtClient: String?
    let payload: [String: JSONValue]?
}

struct SyncPushRequest: Codable, Sendable {
    let deviceId: String
    let baseCursor: String?
    let mutations: [SyncPushMutationRequest]
}

struct SyncPushConflict: Codable, Sendable {
    let opId: String
    let entity: SyncEntityName
    let entityId: String
    let reason: String
    let serverVersion: Int?
    let serverDoc: [String: JSONValue]?
}

extension SyncPushConflict {
    var displayEntityLabel: String {
        entity.rawValue
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    var displayEntityIdentifier: String {
        let normalized = entityId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.count >= 8 else { return "invalid-id" }
        return normalized
    }

    var displayReason: String {
        switch reason.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "version_mismatch":
            return "This item changed on another device."
        case "invalid_payload":
            return "This update was rejected as invalid."
        case "insert_failed", "update_failed":
            return "The server rejected this update."
        default:
            return "A sync conflict requires your decision."
        }
    }

    var displayServerVersion: String {
        guard let serverVersion else { return "unknown" }
        return "\(serverVersion)"
    }

    var serverPreviewRows: [(key: String, value: String)] {
        guard let serverDoc else { return [] }
        return serverDoc
            .map { (key: $0.key, value: $0.value.conflictDisplayValue) }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }
}

private extension JSONValue {
    var conflictDisplayValue: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .object(let object):
            return "{\(object.count) fields}"
        case .array(let array):
            return "[\(array.count) items]"
        case .null:
            return "null"
        }
    }
}

struct SyncPushFailure: Codable, Sendable {
    let opId: String?
    let reason: String
}

struct SyncPushResponse: Codable, Sendable {
    let acknowledgedOpIds: [String]
    let conflicts: [SyncPushConflict]
    let failed: [SyncPushFailure]
    let newCursor: String
}

struct SyncPullRequest: Codable, Sendable {
    let cursor: String?
    let limit: Int
}

struct SyncPullChange: Codable, Sendable {
    let entity: SyncEntityName
    let type: SyncMutationType
    let entityId: String?
    let version: Int?
    let doc: [String: JSONValue]?
}

struct SyncPullResponse: Codable, Sendable {
    let changes: [SyncPullChange]
    let nextCursor: String
    let hasMore: Bool
}

struct PendingSyncMutation: Sendable {
    let opId: UUID
    let entity: SyncEntityName
    let entityId: UUID
    let mutationType: SyncMutationType
    let baseVersion: Int
    let updatedAtClient: Date?
    let payload: [String: JSONValue]
    let attempts: Int
}

protocol SyncLocallyMutable: AnyObject {
    var updatedAtClient: Date { get set }
    var isSoftDeleted: Bool { get set }
}

enum SyncLocalMutation {
    static func touch<T: SyncLocallyMutable>(_ model: T) {
        model.updatedAtClient = .now
    }

    static func softDelete<T: SyncLocallyMutable>(_ model: T) {
        model.isSoftDeleted = true
        model.updatedAtClient = .now
    }

    static func active<T: SyncLocallyMutable>(_ items: [T]) -> [T] {
        items.filter { !$0.isSoftDeleted }
    }

    static func boulderCombinationExerciseLinkID(combinationID: UUID, exerciseID: UUID) -> UUID {
        SyncStoreActor.boulderCombinationExerciseLinkID(combinationID: combinationID, exerciseID: exerciseID)
    }
}

struct SyncStateSnapshot: Sendable {
    let id: String
    let userId: String?
    let deviceId: String
    let lastCursor: String?
    let lastSuccessfulSyncAt: Date?
    let isSyncEnabled: Bool
}

struct SyncPushProcessingResult: Sendable {
    let acknowledged: Int
    let conflicts: Int
    let failures: Int
}

enum SyncSerialization {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    static func encodePayload(_ payload: [String: JSONValue]) throws -> String {
        let data = try encoder.encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SyncStoreError.invalidPayloadJSON
        }
        return json
    }

    static func decodePayload(_ payloadJSON: String) throws -> [String: JSONValue] {
        guard let data = payloadJSON.data(using: .utf8) else {
            throw SyncStoreError.invalidPayloadJSON
        }
        return try decoder.decode([String: JSONValue].self, from: data)
    }
}
