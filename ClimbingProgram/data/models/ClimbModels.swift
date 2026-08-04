//
//  ClimbModels.swift
//  Klettrack
//  Created by Shahar Noy on 28.08.25.
//

import Foundation
import SwiftData
import SwiftUI
import Photos


// MARK: - Climb Data Models
@Model
final class ClimbEntry {
    @Attribute(.unique) var id: UUID
    var climbType: ClimbType
    var grade: String
    var feelsLikeGrade: String?
    var angleDegrees: Int?
    var style: String
    var attempts: String?
    var isWorkInProgress: Bool
    var isPreviouslyClimbed: Bool?
    var holdColor: HoldColor?
    var ropeClimbType: RopeClimbType?
    var gym: String
    var notes: String?
    var dateLogged: Date
    var planSourceId: UUID?
    var planDayId: UUID?
    var tb2ClimbUUID: String?
    var kilterLogUuid: String?
    var kilterClimbUuid: String?
    
    //support multiple media files per climb
        @Relationship(deleteRule: .cascade, inverse: \ClimbMedia.climb)
        var media: [ClimbMedia] = []
    
    init(
        id: UUID = UUID(),
        climbType: ClimbType,
        ropeClimbType: RopeClimbType? = nil,
        grade: String,
        feelsLikeGrade: String? = nil,
        angleDegrees: Int? = nil,
        style: String,
        attempts: String? = nil,
        isWorkInProgress: Bool = false,
        isPreviouslyClimbed: Bool = false,
        holdColor: HoldColor? = Optional.none,
        gym: String,
        notes: String? = nil,
        dateLogged: Date = Date(),
        planSourceId: UUID? = nil,
        planDayId: UUID? = nil,
        tb2ClimbUUID: String? = nil,
        kilterLogUuid: String? = nil,
        kilterClimbUuid: String? = nil
    ) {
        self.id = id
        self.climbType = climbType
        self.ropeClimbType = ropeClimbType
        self.grade = grade
        self.feelsLikeGrade = feelsLikeGrade
        self.angleDegrees = angleDegrees
        self.style = style
        self.attempts = attempts
        self.isWorkInProgress = isWorkInProgress
        self.isPreviouslyClimbed = isPreviouslyClimbed
        self.holdColor = holdColor
        self.gym = gym
        self.notes = notes
        self.dateLogged = dateLogged
        self.planSourceId = planSourceId
        self.planDayId = planDayId
        self.tb2ClimbUUID = tb2ClimbUUID
        self.kilterLogUuid = kilterLogUuid
        self.kilterClimbUuid = kilterClimbUuid
    }
}

@Model
final class TB2ClimbMetadata {
    var boardRawValue: String = ""
    var uuid: String = ""
    var name: String = ""
    var updatedAt: String?
    var layoutID: Int?
    var isListed: Bool?

    init(
        boardRawValue: String = "",
        uuid: String = "",
        name: String = "",
        updatedAt: String? = nil,
        layoutID: Int? = nil,
        isListed: Bool? = nil
    ) {
        self.boardRawValue = boardRawValue
        self.uuid = uuid
        self.name = name
        self.updatedAt = updatedAt
        self.layoutID = layoutID
        self.isListed = isListed
    }
}

@Model
final class TB2ClimbStatsMetadata {
    var boardRawValue: String = ""
    var climbUUID: String = ""
    var angle: Int = 0
    var difficultyAverage: Double?
    var displayDifficulty: Double?
    var ascensionistCount: Int?
    var qualityAverage: Double?

    init(
        boardRawValue: String = "",
        climbUUID: String = "",
        angle: Int = 0,
        difficultyAverage: Double? = nil,
        displayDifficulty: Double? = nil,
        ascensionistCount: Int? = nil,
        qualityAverage: Double? = nil
    ) {
        self.boardRawValue = boardRawValue
        self.climbUUID = climbUUID
        self.angle = angle
        self.difficultyAverage = difficultyAverage
        self.displayDifficulty = displayDifficulty
        self.ascensionistCount = ascensionistCount
        self.qualityAverage = qualityAverage
    }
}


// MARK: - Enums

enum ClimbType: String, CaseIterable, Codable {
    case boulder = "Boulder"
    case sport = "Sport"
    
    var displayName: String {
        return rawValue
    }
    
    // Custom decoding for backward compatibility: map "Lead" to .sport
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "Boulder":
            self = .boulder
        case "Sport", "Lead":
            self = .sport
        default:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot initialize ClimbType from invalid String value \(raw)")
        }
    }
    // Optional: if you want custom encoding (not strictly necessary here)
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

//RopeClimbType enum
enum RopeClimbType: String, CaseIterable, Codable {
    case lead = "Lead"
    case topRope = "Top Rope"
    
    var displayName: String { rawValue }
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
        "Der Kegel",
        "Outdoor"
    ]
}

// MARK: - Style and Gym Management Models
@Model
final class ClimbStyle {
    @Attribute(.unique) var id: UUID
    var name: String
    var isDefault: Bool
    var isHidden: Bool = false
    
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

// MARK: - Climb Media
enum ClimbMediaType: String, Codable {
    case photo
    case video
}

@Model
final class ClimbMedia {
    @Attribute(.unique) var id: UUID
    var assetLocalIdentifier: String
    var thumbnailData: Data?
    var typeRaw: String
    var createdAt: Date

    @Relationship var climb: ClimbEntry

    var type: ClimbMediaType {
        get { ClimbMediaType(rawValue: typeRaw) ?? .photo }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        assetLocalIdentifier: String,
        thumbnailData: Data? = nil,
        type: ClimbMediaType,
        createdAt: Date = .now,
        climb: ClimbEntry
    ) {
        self.id = id
        self.assetLocalIdentifier = assetLocalIdentifier
        self.thumbnailData = thumbnailData
        self.typeRaw = type.rawValue
        self.createdAt = createdAt
        self.climb = climb
    }
}
extension ClimbMedia {
    var isMissingAsset: Bool {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetLocalIdentifier], options: nil)
        return result.firstObject == nil
    }
}
