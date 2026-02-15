//
//  Models.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import Foundation
import SwiftData

@Model
final class Activity {
    @Attribute(.unique) var id: UUID
    var name: String
    var types: [TrainingType] = []
    var syncVersion: Int = 0
    var updatedAtClient: Date = Date.now
    var isDeleted: Bool = false

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

@Model
final class TrainingType {
    @Attribute(.unique) var id: UUID
    var name: String
    var area: String?
    var typeDescription: String?
    var exercises: [Exercise] = []
    var combinations: [BoulderCombination] = []
    var syncVersion: Int = 0
    var updatedAtClient: Date = Date.now
    var isDeleted: Bool = false

    init(
        id: UUID = UUID(),
        name: String,
        area: String? = nil,
        typeDescription: String? = nil
    ) {
        self.id = id
        self.name = name
        self.area = area
        self.typeDescription = typeDescription
    }
}

@Model
final class BoulderCombination {
    @Attribute(.unique) var id: UUID
    var name: String
    var comboDescription: String?
    var exercises: [Exercise] = []
    var syncVersion: Int = 0
    var updatedAtClient: Date = Date.now
    var isDeleted: Bool = false

    init(id: UUID = UUID(), name: String, comboDescription: String? = nil) {
        self.id = id
        self.name = name
        self.comboDescription = comboDescription
    }
}

@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var area: String?
    var order: Int = 0  // maintain exercise order
    var exerciseDescription: String?
    var repsText: String?
    var durationText: String?
    var setsText: String?
    var restText: String?
    var notes: String?
    var syncVersion: Int = 0
    var updatedAtClient: Date = Date.now
    var isDeleted: Bool = false

    init(
        id: UUID = UUID(),
        name: String,
        area: String? = nil,
        order: Int = 0,
        exerciseDescription: String? = nil,
        repsText: String? = nil,
        durationText: String? = nil,
        setsText: String? = nil,
        restText: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.area = area
        self.order = order
        self.exerciseDescription = exerciseDescription
        self.repsText = repsText
        self.durationText = durationText
        self.setsText = setsText
        self.restText = restText
        self.notes = notes
    }
}


// User logging (sessions & what they did)
@Model
final class Session {
    @Attribute(.unique) var id: UUID
    var date: Date
    @Relationship(deleteRule: .cascade, inverse: \SessionItem.session)
    var items: [SessionItem] = []   // links to catalog exercises with performed values
    var syncVersion: Int = 0
    var updatedAtClient: Date = Date.now
    var isDeleted: Bool = false
    init(id: UUID = UUID(), date: Date = .now) { self.id = id; self.date = date }
}

@Model
final class SessionItem {
    @Attribute(.unique) var id: UUID
    @Attribute var sourceTag: String?
    var exerciseName: String
    
    @Relationship var session: Session?
    var sort: Int = 0
    var planSourceId: UUID?
    var planName: String?

    // Structured metrics
    var reps: Double?
    var sets: Double?
    var weightKg: Double?
    var grade: String?
    var notes: String?
    var duration: Double?
    var syncVersion: Int = 0
    var updatedAtClient: Date = Date.now
    var isDeleted: Bool = false

    init(
        id: UUID = UUID(),
        exerciseName: String,
        planSourceId: UUID? = nil,
        planName: String? = nil,
        reps: Double? = nil,
        sets: Double? = nil,
        weightKg: Double? = nil,
        grade: String? = nil,
        notes: String? = nil,
        duration: Double? = nil
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.planSourceId = planSourceId
        self.planName = planName
        self.reps = reps
        self.sets = sets
        self.weightKg = weightKg
        self.grade = grade
        self.notes = notes
        self.duration = duration
    }
}

// MARK: - Timer Models

@Model
final class TimerTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var templateDescription: String?
    
    // Timer configuration
    var totalTimeSeconds: Int?
    var intervals: [TimerInterval] = []
    var isRepeating: Bool
    var repeatCount: Int?
    var restTimeBetweenIntervals: Int?
    
    // Metadata
    var createdDate: Date
    var lastUsedDate: Date?
    var useCount: Int
    var syncVersion: Int = 0
    var updatedAtClient: Date = Date.now
    var isDeleted: Bool = false
    
    init(
        id: UUID = UUID(),
        name: String,
        templateDescription: String? = nil,
        totalTimeSeconds: Int? = nil,
        isRepeating: Bool = false,
        repeatCount: Int? = nil,
        restTimeBetweenIntervals: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.templateDescription = templateDescription
        self.totalTimeSeconds = totalTimeSeconds
        self.isRepeating = isRepeating
        self.repeatCount = repeatCount
        self.restTimeBetweenIntervals = restTimeBetweenIntervals
        self.createdDate = Date()
        self.useCount = 0
    }
    
    // Computed property to get the effective total time
    var effectiveTotalTimeSeconds: Int? {
        // If we have an explicit total time, use it
        if let totalTime = totalTimeSeconds {
            return totalTime
        }
        
        // Otherwise, calculate from intervals
        guard !intervals.isEmpty else { return nil }
        
        // Per-cycle time from configured intervals
        let perCycleTime = intervals.reduce(0) { total, interval in
            let singleCycleTime = (interval.workTimeSeconds + interval.restTimeSeconds) * interval.repetitions
            return total + singleCycleTime
        }
        
        // Handle repeats and rest between cycles (repeats)
        guard isRepeating, let repeats = repeatCount, repeats > 1 else {
            return perCycleTime
        }
        
        let restBetweenCycles = (restTimeBetweenIntervals ?? 0) * (repeats - 1)
        return (perCycleTime * repeats) + restBetweenCycles
    }
}

@Model
final class TimerInterval {
    @Attribute(.unique) var id: UUID
    var name: String
    var workTimeSeconds: Int
    var restTimeSeconds: Int
    var repetitions: Int
    var order: Int
    var syncVersion: Int = 0
    var updatedAtClient: Date = Date.now
    var isDeleted: Bool = false
    
    init(
        id: UUID = UUID(),
        name: String,
        workTimeSeconds: Int,
        restTimeSeconds: Int,
        repetitions: Int,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.workTimeSeconds = workTimeSeconds
        self.restTimeSeconds = restTimeSeconds
        self.repetitions = repetitions
        self.order = order
    }
}

@Model
final class TimerSession {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date?
    var templateId: UUID?
    var templateName: String?
    var planDayId: UUID?
    var totalElapsedSeconds: Int
    var completedIntervals: Int
    var laps: [TimerLap] = []
    var wasCompleted: Bool
    var dailynotes: String?
    var syncVersion: Int = 0
    var updatedAtClient: Date = Date.now
    var isDeleted: Bool = false
        
    
    init(
        id: UUID = UUID(),
        templateId: UUID? = nil,
        templateName: String? = nil,
        planDayId: UUID? = nil
    ) {
        self.id = id
        self.startDate = Date()
        self.templateId = templateId
        self.templateName = templateName
        self.planDayId = planDayId
        self.totalElapsedSeconds = 0
        self.completedIntervals = 0
        self.wasCompleted = false
    }
}

@Model
final class TimerLap {
    @Attribute(.unique) var id: UUID
    var lapNumber: Int
    var timestamp: Date
    var elapsedSeconds: Int
    var notes: String?
    var syncVersion: Int = 0
    var updatedAtClient: Date = Date.now
    var isDeleted: Bool = false
    
    init(
        id: UUID = UUID(),
        lapNumber: Int,
        elapsedSeconds: Int,
        notes: String? = nil
    ) {
        self.id = id
        self.lapNumber = lapNumber
        self.timestamp = Date()
        self.elapsedSeconds = elapsedSeconds
        self.notes = notes
    }
}

extension Activity: SyncLocallyMutable {}
extension TrainingType: SyncLocallyMutable {}
extension Exercise: SyncLocallyMutable {}
extension BoulderCombination: SyncLocallyMutable {}
extension Session: SyncLocallyMutable {}
extension SessionItem: SyncLocallyMutable {}
extension TimerTemplate: SyncLocallyMutable {}
extension TimerInterval: SyncLocallyMutable {}
extension TimerSession: SyncLocallyMutable {}
extension TimerLap: SyncLocallyMutable {}
