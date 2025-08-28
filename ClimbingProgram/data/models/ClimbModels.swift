//
//  ClimbModels.swift
//  ClimbingProgram
//
//  Created by AI Assistant on 28.08.25.
//

import Foundation
import SwiftData

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

// MARK: - Default Values for Enums with custom options

struct ClimbingDefaults {
    static let defaultStyles = [
        "technical",
        "power", 
        "slab",
        "overhang",
        "crimps",
        "pinchy",
        "pumpy",
        "dynamic",
        "other"
    ]
    
    static let defaultGyms = [
        "OstBloc",
        "Urban-Apes", 
        "BoulderGarten",
        "Elektra",
        "MagicMountain",
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