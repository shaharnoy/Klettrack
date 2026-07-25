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
    static let showSyncedBoardGradesAsVScale = "featureFlag.showSyncedBoardGradesAsVScale"
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

enum BoardGradeDisplayRules {
    static func displayText(
        grade: String,
        feelsLikeGrade: String?,
        tb2ClimbUUID: String?,
        kilterClimbUuid: String?,
        showSyncedBoardGradesAsVScale: Bool
    ) -> String? {
        let displayLogged = displayGrade(
            grade,
            tb2ClimbUUID: tb2ClimbUUID,
            kilterClimbUuid: kilterClimbUuid,
            showSyncedBoardGradesAsVScale: showSyncedBoardGradesAsVScale
        )
        let displayFeels = displayGrade(
            feelsLikeGrade,
            tb2ClimbUUID: tb2ClimbUUID,
            kilterClimbUuid: kilterClimbUuid,
            showSyncedBoardGradesAsVScale: showSyncedBoardGradesAsVScale
        )

        switch (displayLogged, displayFeels) {
        case let (grade?, feels?):
            return "\(grade) (\(feels))"
        case let (grade?, nil):
            return grade
        case let (nil, feels?):
            return feels
        case (nil, nil):
            return nil
        }
    }

    static func resolvedGrade(
        grade: String,
        feelsLikeGrade: String?,
        preferFeelsLikeGrade: Bool,
        tb2ClimbUUID: String?,
        kilterClimbUuid: String?,
        showSyncedBoardGradesAsVScale: Bool
    ) -> String {
        let logged = displayGrade(
            grade,
            tb2ClimbUUID: tb2ClimbUUID,
            kilterClimbUuid: kilterClimbUuid,
            showSyncedBoardGradesAsVScale: showSyncedBoardGradesAsVScale
        )
        let feels = displayGrade(
            feelsLikeGrade,
            tb2ClimbUUID: tb2ClimbUUID,
            kilterClimbUuid: kilterClimbUuid,
            showSyncedBoardGradesAsVScale: showSyncedBoardGradesAsVScale
        )

        if preferFeelsLikeGrade {
            if let feels { return feels }
            if let logged { return logged }
        } else {
            if let logged { return logged }
            if let feels { return feels }
        }

        let fallbackLogged = grade.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallbackLogged.isEmpty { return fallbackLogged }
        let fallbackFeels = feelsLikeGrade?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fallbackFeels, !fallbackFeels.isEmpty { return fallbackFeels }
        return "Unknown"
    }

    static func displayGradeOptions(
        grade: String,
        feelsLikeGrade: String?,
        tb2ClimbUUID: String?,
        kilterClimbUuid: String?,
        showSyncedBoardGradesAsVScale: Bool
    ) -> [String] {
        [
            displayGrade(
                grade,
                tb2ClimbUUID: tb2ClimbUUID,
                kilterClimbUuid: kilterClimbUuid,
                showSyncedBoardGradesAsVScale: showSyncedBoardGradesAsVScale
            ),
            displayGrade(
                feelsLikeGrade,
                tb2ClimbUUID: tb2ClimbUUID,
                kilterClimbUuid: kilterClimbUuid,
                showSyncedBoardGradesAsVScale: showSyncedBoardGradesAsVScale
            )
        ].compactMap { $0 }
    }

    static func displayGrade(
        _ grade: String?,
        tb2ClimbUUID: String?,
        kilterClimbUuid: String?,
        showSyncedBoardGradesAsVScale: Bool
    ) -> String? {
        guard let grade else { return nil }
        let trimmed = grade.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "unknown" else { return nil }

        guard showSyncedBoardGradesAsVScale, isSyncedBoardClimb(tb2ClimbUUID: tb2ClimbUUID, kilterClimbUuid: kilterClimbUuid) else {
            return trimmed
        }

        return BoardGradeMapper.vGrade(fromFontGrade: trimmed) ?? trimmed
    }

    private static func isSyncedBoardClimb(tb2ClimbUUID: String?, kilterClimbUuid: String?) -> Bool {
        [tb2ClimbUUID, kilterClimbUuid].contains { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
