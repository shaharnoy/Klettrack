//
//  ClimbModels.swift
//  ClimbingProgram
//
//  Created by AI Assistant on 28.08.25.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Climb Data Models

@Model
final class ClimbEntry {
    @Attribute(.unique) var id: UUID
    var climbType: ClimbType
    var grade: String
    var angleDegrees: Int?
    var style: String
    var attempts: String?
    var isWorkInProgress: Bool
    var isPreviouslyClimbed: Bool
    var holdColor: HoldColor?
    var gym: String
    var notes: String?
    var dateLogged: Date
    
    init(
        id: UUID = UUID(),
        climbType: ClimbType,
        grade: String,
        angleDegrees: Int? = nil,
        style: String,
        attempts: String? = nil,
        isWorkInProgress: Bool = false,
        isPreviouslyClimbed: Bool = false,
        holdColor: HoldColor? = .none,
        gym: String,
        notes: String? = nil,
        dateLogged: Date = Date()
    ) {
        self.id = id
        self.climbType = climbType
        self.grade = grade
        self.angleDegrees = angleDegrees
        self.style = style
        self.attempts = attempts
        self.isWorkInProgress = isWorkInProgress
        self.isPreviouslyClimbed = isPreviouslyClimbed
        self.holdColor = holdColor
        self.gym = gym
        self.notes = notes
        self.dateLogged = dateLogged
    }
}

// MARK: - Enums

enum ClimbType: String, CaseIterable, Codable {
    case boulder = "Boulder"
    case lead = "Lead"
    
    var displayName: String {
        return rawValue
    }
}

enum HoldColor: String, CaseIterable, Codable {
    case none = "None"
    case red = "Red"
    case blue = "Blue"
    case green = "Green"
    case yellow = "Yellow"
    case orange = "Orange"
    case purple = "Purple"
    case pink = "Pink"
    case black = "Black"
    case white = "White"
    case gray = "Gray"
    case brown = "Brown"
    case cyan = "Cyan"
    case mint = "Mint"
    case indigo = "Indigo"
    case teal = "Teal"
    
    var displayName: String {
        return rawValue
    }
    
    var color: Color {
        switch self {
        case .none:
            return .clear
        case .red:
            return .red
        case .blue:
            return .blue
        case .green:
            return .green
        case .yellow:
            return .yellow
        case .orange:
            return .orange
        case .purple:
            return .purple
        case .pink:
            return .pink
        case .black:
            return .black
        case .white:
            return .white
        case .gray:
            return .gray
        case .brown:
            return .brown
        case .cyan:
            return .cyan
        case .mint:
            return .mint
        case .indigo:
            return .indigo
        case .teal:
            return .teal
        }
    }
}

// MARK: - Default Values for Enums with custom options

struct ClimbingDefaults {
    static let defaultStyles = [
        "Technical",
        "Power",
        "Slab",
        "Overhang",
        "Crimps",
        "Slopers",
        "Coordination",
        "Tension board",
        "Kilter board"
    ]
    
    static let defaultGyms = [
        "Ostbloc",
        "Urban apes",
        "Bouldergarten",
        "Elektra",
        "Magic mountain",
        "Der Kegel"
    ]
}

// MARK: - Style and Gym Management Models

@Model
final class ClimbStyle {
    @Attribute(.unique) var id: UUID
    var name: String
    var isDefault: Bool
    
    init(id: UUID = UUID(), name: String, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

@Model
final class ClimbGym {
    @Attribute(.unique) var id: UUID
    var name: String
    var isDefault: Bool
    
    init(id: UUID = UUID(), name: String, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}
