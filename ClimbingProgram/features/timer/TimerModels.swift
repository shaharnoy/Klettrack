//
//  TimerModels.swift
//  Klettrack
//  Created by Shahar Noy on 25.08.25.
//

import Foundation
import SwiftData

// MARK: - Timer State Enums
enum TimerState {
    case stopped
    case getReady
    case running
    case paused
    case completed
    case reseted
}

enum IntervalPhase {
    case work
    case rest
    case completed
    case getReady
}

// MARK: - Timer Configuration Structs
struct TimerConfiguration {
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

struct IntervalConfiguration {
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
