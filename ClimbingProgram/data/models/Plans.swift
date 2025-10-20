//  Plans.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - New SwiftData Models replacing enums

@Model
final class PlanKindModel {
    @Attribute(.unique) var id: UUID
    // Stable identifier used for lookups and migrations (e.g., "daily", "weekly", "3-2-1", "4-3-2-1")
    var key: String
    // Display name shown in UI (e.g., "Weekly", "3-2-1 (6 weeks)")
    var name: String
    // Total weeks if finite; nil for open-ended repeating kinds
    var totalWeeks: Int?
    // Whether this kind is intended to repeat (e.g., weekly)
    var isRepeating: Bool
    // Sort order for pickers
    var order: Int

    init(
        id: UUID = UUID(),
        key: String,
        name: String,
        totalWeeks: Int? = nil,
        isRepeating: Bool = false,
        order: Int = 0
    ) {
        self.id = id
        self.key = key
        self.name = name
        self.totalWeeks = totalWeeks
        self.isRepeating = isRepeating
        self.order = order
    }
}


@Model
final class DayTypeModel {
    @Attribute(.unique) var id: UUID
    // Stable identifier used for lookups/migrations (e.g., "climbingFull", "core", "rest")
    var key: String
    // Display name shown in UI (e.g., "Climb + Hi-Vol. exercises")
    var name: String
    // Sort order for pickers
    var order: Int
    // Persisted key of a standard iOS Color (e.g., "green", "blue", "orange", etc.)
    var colorKey: String
    // Soft-delete / visibility flag
    var isHidden: Bool = false

    // Allowed built-in color keys
    static let allowedColorKeys: Set<String> = [
        "green","blue","brown","orange","cyan","purple","yellow","red","pink","gray","black","white","mint","indigo","teal"
    ]

    // Convenience computed Color accessor for UI
    var color: Color {
        DayTypeModel.color(for: colorKey)
    }

    static func color(for key: String) -> Color {
        switch key {
        case "green":  return .green
        case "blue":   return .blue
        case "brown":  return .brown
        case "orange": return .orange
        case "cyan":   return .cyan
        case "purple": return .purple
        case "yellow": return .yellow
        case "red":    return .red
        case "pink":   return .pink
        case "gray":   return .gray
        case "black":  return .black
        case "white":  return .white
        case "mint":   return .mint
        case "indigo": return .indigo
        case "teal":   return .teal
        default:       return .gray
        }
    }

    init(
        id: UUID = UUID(),
        key: String,
        name: String,
        order: Int = 0,
        colorKey: String,
        isHidden: Bool = false
    ) {
        self.id = id
        self.key = key
        self.name = name
        self.order = order
        // Validate colorKey against allowed set; default to gray if invalid
        if DayTypeModel.allowedColorKeys.contains(colorKey) {
            self.colorKey = colorKey
        } else {
            self.colorKey = "gray"
        }
        self.isHidden = isHidden
    }
}

// MARK: - Plans

@Model
final class Plan {
    @Attribute(.unique) var id: UUID
    var name: String
    var startDate: Date
    // Relationship to PlanKindModel (replaces enum/raw storage)
    @Relationship(deleteRule: .nullify) var kind: PlanKindModel?
    var days: [PlanDay] = []

    init(id: UUID = UUID(), name: String, kind: PlanKindModel?, startDate: Date) {
        self.id = id
        self.name = name
        self.kind = kind
        self.startDate = startDate
    }
}

@Model
final class PlanDay {
    @Attribute(.unique) var id: UUID
    var date: Date
    // Relationship to DayTypeModel (replaces enum/raw storage)
    @Relationship(deleteRule: .nullify) var type: DayTypeModel?
    var chosenExercises: [String] = []
    var exerciseOrder: [String:Int] = [:]
    var dailyNotes: String? = nil

    init(id: UUID = UUID(), date: Date, type: DayTypeModel? = nil) {
        self.id = id
        self.date = date
        self.type = type
    }
}
