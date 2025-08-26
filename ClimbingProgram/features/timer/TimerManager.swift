//
//  TimerManager.swift
//  ClimbingProgram
//
//  Created by AI Assistant on 25.08.25.
//

import Foundation
import SwiftUI
import Combine
import AVFoundation
import AudioToolbox

@MainActor
class TimerManager: ObservableObject {
    @Published var state: TimerState = .stopped
    @Published var currentTime: Int = 0
    @Published var totalElapsedTime: Int = 0
    @Published var currentInterval: Int = 0
    @Published var currentRepetition: Int = 0
    @Published var currentSequenceRepeat: Int = 0 // Track which repeat of the entire sequence we're on
    @Published var currentPhase: IntervalPhase = .work
    @Published var laps: [TimerLap] = []
    @Published var isInBetweenIntervalRest: Bool = false // New state for rest between intervals
    
    private var timer: Timer?
    private var startTime: Date?
    private var pausedTime: Date?
    private var audioPlayer: AVAudioPlayer?
    private var lastBeepTime: Int = -1 // Track last beep to avoid duplicates
    private var betweenIntervalRestStartTime: Int = 0 // Track when between-interval rest started
    
    var configuration: TimerConfiguration?
    var session: TimerSession?
    
    // MARK: - Initializers
    init() {
        // Initialize with default values - required for tests
    }
    
    // MARK: - Computed Properties
    var isRunning: Bool { state == .running }
    var isPaused: Bool { state == .paused }
    var isStopped: Bool { state == .stopped }
    var isCompleted: Bool { state == .completed }
    
    var currentIntervalConfig: IntervalConfiguration? {
        guard let config = configuration,
              currentInterval < config.intervals.count else { return nil }
        return config.intervals[currentInterval]
    }
    
    var currentPhaseTimeRemaining: Int {
        // Handle rest between intervals
        if isInBetweenIntervalRest {
            guard let config = configuration,
                  let restBetween = config.restTimeBetweenIntervals else { return 0 }
            let restElapsed = currentTime - betweenIntervalRestStartTime
            return max(0, restBetween - restElapsed)
        }
        
        guard let intervalConfig = currentIntervalConfig else { return 0 }
        
        let timeInCurrentInterval = calculateTimeInCurrentInterval()
        let cycleTime = intervalConfig.workTimeSeconds + intervalConfig.restTimeSeconds
        let timeInCurrentCycle = timeInCurrentInterval % cycleTime
        
        switch currentPhase {
        case .work:
            return intervalConfig.workTimeSeconds - timeInCurrentCycle
        case .rest:
            return cycleTime - timeInCurrentCycle
        case .completed:
            return 0
        }
    }
    
    var totalTimeRemaining: Int {
        guard let config = configuration else { return 0 }
        
        if let totalTime = config.totalTimeSeconds {
            return max(0, totalTime - totalElapsedTime)
        }
        
        // Calculate based on intervals
        let totalIntervalTime = config.intervals.reduce(0) { sum, interval in
            sum + interval.totalTimeSeconds
        }
        
        let repeatMultiplier = config.isRepeating ? (config.repeatCount ?? 1) : 1
        var totalProgramTime = totalIntervalTime * repeatMultiplier
        
        // Add rest time between sequences (not between intervals within a sequence)
        if config.isRepeating, let restBetweenIntervals = config.restTimeBetweenIntervals, restBetweenIntervals > 0 {
            // Rest between sequences: (repeatCount - 1) * restTime
            let restPeriodsBetweenSequences = max(0, repeatMultiplier - 1)
            totalProgramTime += restPeriodsBetweenSequences * restBetweenIntervals
        }
        
        return max(0, totalProgramTime - totalElapsedTime)
    }
    
    var progressPercentage: Double {
        guard let config = configuration else { return 0 }
        
        let totalTime: Int
        if let configTotalTime = config.totalTimeSeconds {
            totalTime = configTotalTime
        } else {
            let intervalTime = config.intervals.reduce(0) { $0 + $1.totalTimeSeconds }
            let multiplier = config.isRepeating ? (config.repeatCount ?? 1) : 1
            var calculatedTotalTime = intervalTime * multiplier
            
            // Add rest time between intervals for repeating sequences (same logic as totalTimeRemaining)
            if config.isRepeating, let restBetweenIntervals = config.restTimeBetweenIntervals, restBetweenIntervals > 0 {
                let restPeriodsWithinSequences = max(0, config.intervals.count - 1) * multiplier
                let restPeriodsBetweenSequences = max(0, multiplier - 1)
                let totalRestPeriods = restPeriodsWithinSequences + restPeriodsBetweenSequences
                calculatedTotalTime += totalRestPeriods * restBetweenIntervals
            }
            
            totalTime = calculatedTotalTime
        }
        
        guard totalTime > 0 else { return 0 }
        return Double(totalElapsedTime) / Double(totalTime)
    }
    
    // MARK: - Configuration Management
    func loadConfiguration(_ configuration: TimerConfiguration) {
        self.configuration = configuration
        
        // Reset timer state to show template details without starting
        state = .stopped
        currentTime = 0
        totalElapsedTime = 0
        currentInterval = 0
        currentRepetition = 0
        currentPhase = configuration.hasIntervals ? .work : .work
        laps = []
        
        // Clear any existing session
        session = nil
        
        // Reset timers
        stopTimer()
        startTime = nil
        pausedTime = nil
    }
    
    // MARK: - Timer Control
    func start(with configuration: TimerConfiguration, session: TimerSession? = nil) {
        self.configuration = configuration
        self.session = session
        
        startTime = Date()
        state = .running
        currentTime = 0
        totalElapsedTime = 0
        currentInterval = 0
        currentRepetition = 0
        currentSequenceRepeat = 0 // Initialize sequence repeat counter
        
        // Set initial phase based on first interval configuration
        if configuration.hasIntervals && !configuration.intervals.isEmpty {
            let firstInterval = configuration.intervals[0]
            // If work time is 0, start directly in rest phase
            currentPhase = firstInterval.workTimeSeconds > 0 ? .work : .rest
        } else {
            currentPhase = .work
        }
        
        startTimer()
        playSound(.start)
    }
    
    func pause() {
        guard state == .running else { return }
        
        pausedTime = Date()
        state = .paused
        stopTimer()
        playSound(.pause)
    }
    
    func resume() {
        guard state == .paused else { return }
        
        if let pausedTime = pausedTime {
            let pauseDuration = Date().timeIntervalSince(pausedTime)
            startTime = startTime?.addingTimeInterval(pauseDuration)
        }
        
        state = .running
        startTimer()
        playSound(.resume)
    }
    
    func stop() {
        state = .stopped
        stopTimer()
        
        // Finalize session if exists
        if let session = session {
            session.endDate = Date()
            session.totalElapsedSeconds = totalElapsedTime
            session.completedIntervals = currentInterval
            session.wasCompleted = false
        }
        
        reset()
        playSound(.stop)
    }
    
    func complete() {
        state = .completed
        stopTimer()
        
        // Finalize session if exists
        if let session = session {
            session.endDate = Date()
            session.totalElapsedSeconds = totalElapsedTime
            session.completedIntervals = currentInterval
            session.wasCompleted = true
        }
        
        playSound(.complete)
    }
    
    func addLap(notes: String? = nil) {
        let lap = TimerLap(
            lapNumber: laps.count + 1,
            elapsedSeconds: totalElapsedTime,
            notes: notes
        )
        
        laps.append(lap)
        
        // Add to session if exists
        session?.laps.append(lap)
        
        playSound(.lap)
    }
    
    // MARK: - Private Methods
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTime()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateTime() {
        guard let startTime = startTime else { return }
        
        let elapsed = Int(Date().timeIntervalSince(startTime))
        currentTime = elapsed
        totalElapsedTime = elapsed
        
        updateIntervalProgress()
        checkForCompletion()
    }
    
    internal func updateIntervalProgress() {
        guard let config = configuration, config.hasIntervals else { return }
        guard currentInterval < config.intervals.count else { return }
        
        // Handle rest between intervals state
        if isInBetweenIntervalRest {
            handleBetweenIntervalRest()
            return
        }
        
        let interval = config.intervals[currentInterval]
        let cycleTime = interval.workTimeSeconds + interval.restTimeSeconds
        
        // Calculate time within current interval (excluding previous intervals and rest periods)
        let timeInCurrentInterval = calculateTimeInCurrentInterval()
        let timeInCurrentCycle = timeInCurrentInterval % cycleTime
        
        // Determine current phase and time remaining in current phase
        let (newPhase, timeRemainingInPhase) = if timeInCurrentCycle < interval.workTimeSeconds {
            (IntervalPhase.work, interval.workTimeSeconds - timeInCurrentCycle)
        } else {
            (IntervalPhase.rest, cycleTime - timeInCurrentCycle)
        }
        
        // Phase change detection
        if currentPhase != newPhase {
            let previousPhase = currentPhase
            currentPhase = newPhase
            
            // Different sounds for different transitions
            if previousPhase == .work && newPhase == .rest {
                playSound(.workToRest)
            } else if previousPhase == .rest && newPhase == .work {
                playSound(.restToWork)
            }
            
            lastBeepTime = -1 // Reset beep tracking for new phase
        }
        
        // Countdown beeps for last 3 seconds of each phase
        checkCountdownBeeps(timeRemaining: timeRemainingInPhase)
        
        // Check if we completed a cycle (work + rest)
        let completedCycles = timeInCurrentInterval / cycleTime
        let newRepetition = min(completedCycles, interval.repetitions)
        
        if newRepetition > currentRepetition {
            currentRepetition = newRepetition
            
            // Only move to next interval when ALL repetitions are complete
            if currentRepetition >= interval.repetitions {
                // Check if we're at the end of a cycle and not in the middle of one
                let isAtEndOfCycle = (timeInCurrentInterval % cycleTime == 0) && timeInCurrentInterval > 0
                if isAtEndOfCycle {
                    moveToNextInterval()
                }
            }
        }
    }
    
    private func calculateTimeInCurrentInterval() -> Int {
        guard let config = configuration else { return 0 }
        
        var totalPreviousTime = 0
        
        // Add time from previous sequence repeats
        if currentSequenceRepeat > 0 {
            let timePerSequence = config.intervals.reduce(0) { sum, interval in
                sum + interval.totalTimeSeconds
            }
            // Add rest between intervals for each previous sequence
            let restBetweenIntervalsPerSequence = config.intervals.count > 1 ?
                (config.intervals.count - 1) * (config.restTimeBetweenIntervals ?? 0) : 0
            
            totalPreviousTime += currentSequenceRepeat * (timePerSequence + restBetweenIntervalsPerSequence)
        }
        
        // Add time from all previous intervals in current sequence
        for i in 0..<currentInterval {
            let prevInterval = config.intervals[i]
            totalPreviousTime += prevInterval.totalTimeSeconds
            
            // Add rest between intervals if applicable (only if not the last interval)
            if i < config.intervals.count - 1,
               let restBetween = config.restTimeBetweenIntervals, restBetween > 0 {
                totalPreviousTime += restBetween
            }
        }
        
        return currentTime - totalPreviousTime
    }
    
    private func handleBetweenIntervalRest() {
        guard let config = configuration,
              let restBetween = config.restTimeBetweenIntervals else { return }
        
        let restElapsed = currentTime - betweenIntervalRestStartTime
        let restRemaining = restBetween - restElapsed
        
        // Show rest countdown
        checkCountdownBeeps(timeRemaining: restRemaining)
        
        // Check if rest period is complete
        if restElapsed >= restBetween {
            completeIntervalTransition()
        }
    }
    
    private func moveToNextInterval() {
        guard let config = configuration else { return }
        
        let nextInterval = currentInterval + 1
        
        // Check if there's a next interval and we need rest between intervals
        if nextInterval < config.intervals.count,
           let restBetween = config.restTimeBetweenIntervals,
           restBetween > 0 {
            
            // Start rest between intervals
            isInBetweenIntervalRest = true
            betweenIntervalRestStartTime = currentTime
            currentPhase = .rest
            playSound(.intervalToInterval)
            lastBeepTime = -1
        } else {
            // Move to next interval immediately
            completeIntervalTransition()
        }
    }
    
    private func completeIntervalTransition() {
        isInBetweenIntervalRest = false
        currentInterval += 1
        currentRepetition = 0
        
        if currentInterval < configuration?.intervals.count ?? 0 {
            currentPhase = .work
            lastBeepTime = -1
        }
    }
    
    private func checkCountdownBeeps(timeRemaining: Int) {
        // Play beep sound for last 3 seconds (3, 2, and 1 second remaining)
        if (timeRemaining == 3 || timeRemaining == 2 || timeRemaining == 1) && lastBeepTime != timeRemaining {
            lastBeepTime = timeRemaining
            playCountdownBeep()
        }
    }
    
    private func playCountdownBeep() {
        // Use a distinct sound for countdown beeps
        AudioServicesPlaySystemSound(1103) // SMS received sound (short beep)
    }
    
    internal func checkForCompletion() {
        guard let config = configuration else { return }
        
        // Check total time completion
        if let totalTime = config.totalTimeSeconds, totalElapsedTime >= totalTime {
            complete()
            return
        }
        
        // Check interval completion
        if config.hasIntervals {
            let totalIntervals = config.intervals.count
            let repeatCount = config.isRepeating ? (config.repeatCount ?? 1) : 1
            
            // Check if we've completed all intervals in the current sequence
            if currentInterval >= totalIntervals {
                // We've finished one complete sequence of intervals
                currentSequenceRepeat += 1
                
                // Check if we've completed all repeats
                if currentSequenceRepeat >= repeatCount {
                    complete()
                    return
                } else {
                    // Start rest period between sequences if configured
                    if let restBetweenSequences = config.restTimeBetweenIntervals, restBetweenSequences > 0 {
                        // Start rest between sequences
                        isInBetweenIntervalRest = true
                        betweenIntervalRestStartTime = currentTime
                        currentPhase = .rest
                        currentInterval = 0 // Reset for next sequence
                        currentRepetition = 0
                        playSound(.intervalToInterval)
                        lastBeepTime = -1
                    } else {
                        // No rest between sequences, start next sequence immediately
                        currentInterval = 0
                        currentRepetition = 0
                        currentPhase = .work
                        isInBetweenIntervalRest = false
                        lastBeepTime = -1
                        playSound(.intervalToInterval)
                    }
                }
            }
        }
    }
    
    private func reset() {
        currentTime = 0
        totalElapsedTime = 0
        currentInterval = 0
        currentRepetition = 0
        currentSequenceRepeat = 0 // Reset sequence repeat counter
        currentPhase = .work
        isInBetweenIntervalRest = false // Reset between-interval rest state
        betweenIntervalRestStartTime = 0 // Reset rest start time
        startTime = nil
        pausedTime = nil
        configuration = nil
        session = nil
        laps.removeAll()
        lastBeepTime = -1 // Reset beep tracking
    }
    
    // MARK: - Audio Feedback
    private enum SoundType {
        case start, pause, resume, stop, complete, lap, phaseChange, intervalChange, workToRest, restToWork, intervalToInterval
    }
    
    private func playSound(_ type: SoundType) {
        // Simple system sound feedback
        // In a real app, you might want custom sounds
        switch type {
        case .start, .resume:
            AudioServicesPlaySystemSound(1104) // Begin record sound
        case .pause, .stop:
            AudioServicesPlaySystemSound(1105) // End record sound
        case .complete:
            AudioServicesPlaySystemSound(1016) // Tock sound
        case .lap:
            AudioServicesPlaySystemSound(1057) // Tink sound
        case .phaseChange, .intervalChange:
            AudioServicesPlaySystemSound(1054) // Timer sound
        case .workToRest:
            AudioServicesPlaySystemSound(1053) // Chime sound
        case .restToWork:
            AudioServicesPlaySystemSound(1052) // Bell sound
        case .intervalToInterval:
            AudioServicesPlaySystemSound(1051) // Tri-tone sound
        }
    }
}

// MARK: - Timer Extensions
extension TimerManager {
    func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return String(format: "%d:%02d:%02d", hours, remainingMinutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
    
    func formatTimeDetailed(_ seconds: Int) -> (hours: Int, minutes: Int, seconds: Int) {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return (h, m, s)
    }
}
