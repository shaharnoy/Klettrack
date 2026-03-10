//
//  FeatureFlags.swift
//  Klettrack
//  Created by Shahar Noy on 08.02.26.
//

import Foundation

enum FeatureFlags {
    static let forcePreferMyGradeInProgress = "featureFlag.forcePreferMyGradeInProgress"
    static let showNotesWhenGymMissing = "featureFlag.showNotesWhenGymMissing"
    static let persistProgressFilters = "featureFlag.persistProgressFilters"
    static let klettrackWebSettings = "featureFlag.klettrackWebSettings"

    static var isKlettrackWebSettingsEnabled: Bool {
        UserDefaults.standard.bool(forKey: klettrackWebSettings)
    }
}

enum FeatureFlagRules {
    static func rowDetailText(
        gym: String,
        notes: String?,
        showNotesWhenGymMissing: Bool
    ) -> String? {
        let trimmedGym = gym.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedGym.isEmpty && trimmedGym != "Unknown" {
            return gym
        }

        guard showNotesWhenGymMissing else { return nil }
        guard let notes else { return nil }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNotes.isEmpty else { return nil }
        return trimmedNotes
    }
}
