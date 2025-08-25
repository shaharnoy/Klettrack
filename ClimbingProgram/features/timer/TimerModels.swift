//
//  TimerModels.swift
//  ClimbingProgram
//
//  Created by AI Assistant on 25.08.25.
//

import Foundation
import SwiftData

// MARK: - Timer State Enums
enum TimerState {
    case stopped
    case running
    case paused
    case completed
}

enum IntervalPhase {
    case work
    case rest
    case completed
}

// MARK: - Timer Configuration Structs
struct TimerConfiguration {
    let totalTimeSeconds: Int?
    let intervals: [IntervalConfiguration]
    let isRepeating: Bool
    let repeatCount: Int?
    let restTimeBetweenIntervals: Int? // New: rest time between different intervals
    
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
        (workTimeSeconds + restTimeSeconds) * repetitions
    }
}
