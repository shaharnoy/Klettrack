//
//  Plans.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import Foundation
import SwiftData

enum PlanKind: String, Codable, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"
    case threeTwoOne = "3-2-1 (6 weeks)"
    case fourThreeTwoOne = "4-3-2-1 (10 weeks)"
    var id: String { rawValue }

    var totalWeeks: Int {
        switch self {
        case .weekly: return 1      // repeats; end date open-ended
        case .threeTwoOne: return 6
        case .fourThreeTwoOne: return 10
        case .daily: return 0       // single day; end date not applicable
        }
    }
}

enum DayType: String, Codable, CaseIterable, Identifiable {
    case climbingFull = "Climb + Hi-Vol. exercises"
    case climbingSmall = "Climb + Lo-Vol. exercises"
    case climbingReduced = "Climb Low-Vol. "
    case Perclimbing = "Performance Climbing"
    case core = "Core"
    case antagonist = "Antagonist"
    case rest = "Rest"
    case vacation = "Vacation"
    case sick = "Sick"
    var id: String { rawValue }
}

@Model
final class Plan {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String
    var startDate: Date
    var days: [PlanDay] = []

    var kind: PlanKind {
        get { PlanKind(rawValue: kindRaw) ?? .weekly }
        set { kindRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), name: String, kind: PlanKind, startDate: Date) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.startDate = startDate
    }
}

@Model
final class PlanDay {
    @Attribute(.unique) var id: UUID
    var date: Date
    var typeRaw: String
    var chosenExercises: [String] = []
    var dailyNotes: String? = nil

    var type: DayType {
        get { DayType(rawValue: typeRaw) ?? .rest }
        set { typeRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), date: Date, type: DayType = .rest) {
        self.id = id
        self.date = date
        self.typeRaw = type.rawValue
    }
}
