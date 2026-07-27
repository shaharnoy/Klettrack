//
//  TimerModels.swift
//  Klettrack
//  Created by Shahar Noy on 25.08.25.
//

import Foundation
import SwiftData

// MARK: - Timer State Enums
enum TimerState: Equatable {
    case stopped
    case getReady
    case running
    case paused
    case completed
    case reseted
    /// Rep-based set sequence: waiting for the user to confirm the current set is done.
    /// Nothing is counting in this state.
    case awaitingUser
}

enum IntervalPhase {
    case work
    case rest
    case betweenSets
    case completed
    case getReady
}

// MARK: - Timer Configuration Structs
struct TimerConfiguration: Equatable {
    let totalTimeSeconds: Int?
    let intervals: [IntervalConfiguration]
    let isRepeating: Bool
    let repeatCount: Int?
    let restTimeBetweenIntervals: Int? // Rest time between different intervals
    let getReady: Bool // Yes/No get ready phase at start - always 5 seconds
    
    init(totalTimeSeconds: Int? = nil,
         intervals: [IntervalConfiguration] = [],
         isRepeating: Bool = false,
         repeatCount: Int? = nil,
         restTimeBetweenIntervals: Int? = nil,
         getReady: Bool = true) {
        self.totalTimeSeconds = totalTimeSeconds
        self.intervals = intervals
        self.isRepeating = isRepeating
        self.repeatCount = repeatCount
        self.restTimeBetweenIntervals = restTimeBetweenIntervals
        self.getReady = getReady
    }
    
    var hasIntervals: Bool {
        !intervals.isEmpty
    }
    
    var hasTotalTime: Bool {
        totalTimeSeconds != nil && totalTimeSeconds! > 0
    }
}

struct IntervalConfiguration: Equatable {
    let name: String
    let workTimeSeconds: Int
    let restTimeSeconds: Int
    let repetitions: Int

    var totalTimeSeconds: Int {
        // Work periods: repetitions
        // Rest periods: repetitions - 1 (no rest after the last work period)
        let totalWorkTime = workTimeSeconds * repetitions
        let totalRestTime = restTimeSeconds * max(0, repetitions - 1)
        return totalWorkTime + totalRestTime
    }
}

extension TimerTemplate {
    /// The single template → configuration mapping, shared by every place that starts a template.
    func makeConfiguration() -> TimerConfiguration {
        TimerConfiguration(
            totalTimeSeconds: totalTimeSeconds,
            intervals: intervals
                .sorted { $0.order < $1.order }
                .map {
                    IntervalConfiguration(
                        name: $0.name,
                        workTimeSeconds: $0.workTimeSeconds,
                        restTimeSeconds: $0.restTimeSeconds,
                        repetitions: $0.repetitions
                    )
                },
            isRepeating: isRepeating,
            repeatCount: repeatCount,
            restTimeBetweenIntervals: restTimeBetweenIntervals
        )
    }
}

// MARK: - Audio System
enum TimerSound {
    case start
    case pause
    case resume
    case stop
    case countdown
    case phaseTransition
    case complete
}

