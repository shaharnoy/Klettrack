//
//  SyncConflictAuditStore.swift
//  klettrack
//
//  Created by Shahar Noy on 10.02.26.
//

import Foundation

actor SyncConflictAuditStore {
    static let shared = SyncConflictAuditStore()

    private let defaults: UserDefaults
    private let key = "sync.conflict.audit.events"
    private let maxEntries = 200
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func append(event: SyncConflictTelemetryEvent) {
        var entries = loadEntries()
        entries.insert(event, at: 0)

        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }

        guard let data = try? encoder.encode(entries) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    private func loadEntries() -> [SyncConflictTelemetryEvent] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }
        return (try? decoder.decode([SyncConflictTelemetryEvent].self, from: data)) ?? []
    }
}
