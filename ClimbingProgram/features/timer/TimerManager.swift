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
    
    // MARK: - Background State Management
    private var backgroundTime: Date?
    private var wasInBackground: Bool = false
    private var notificationCenter = NotificationCenter.default
    
    // MARK: - Initializers
    init() {
        // Initialize with default values - required for tests
        setupBackgroundHandling()
    }
    
    deinit {
        // Remove observers synchronously - this is safe and doesn't require MainActor
        notificationCenter.removeObserver(self)
    }
    
    // MARK: - Computed Properties
    var isRunning: Bool { state == .running }
    var isPaused: Bool { state == .paused }
    var isStopped: Bool { state == .stopped }
    var isCompleted: Bool { state == .completed }
    var isReset: Bool { state == .reseted }
    var isGetReady: Bool { state == .getReady }
    
    var currentIntervalConfig: IntervalConfiguration? {
        guard let config = configuration,
              currentInterval < config.intervals.count else { return nil }
        return config.intervals[currentInterval]
    }
    
    /// The primary display time - counts down for total time mode, shows remaining time for current phase in interval mode
    var displayTime: Int {
        guard let config = configuration else { return 0 }
        
        // Handle Get Ready phase - show countdown from 5 to 1
        if state == .getReady {
            return max(0, 5 - currentTime)
        }
        
        if config.hasTotalTime && !config.hasIntervals {
            // Total time mode: count down from total time
            return max(0, config.totalTimeSeconds! - totalElapsedTime)
        } else {
            // Interval mode: show current phase time remaining
            return currentPhaseTimeRemaining
        }
    }
    
    var currentPhaseTimeRemaining: Int {
        // Handle rest between sequences
        if isInBetweenIntervalRest {
            guard let config = configuration,
                  let restBetween = config.restTimeBetweenIntervals else { return 0 }
            let restElapsed = currentTime - betweenIntervalRestStartTime
            return max(0, restBetween - restElapsed)
        }
        
        guard let intervalConfig = currentIntervalConfig else { return 0 }
        
        let timeInCurrentInterval = calculateTimeInCurrentInterval()
        let singleCycleTime = intervalConfig.workTimeSeconds + intervalConfig.restTimeSeconds
        let currentCycle = timeInCurrentInterval / singleCycleTime
        let timeInCurrentCycle = timeInCurrentInterval % singleCycleTime
        
        // Handle the last repetition differently (no rest after final work)
        if currentCycle == intervalConfig.repetitions - 1 {
            // Last repetition - only work phase
            if timeInCurrentCycle < intervalConfig.workTimeSeconds {
                return intervalConfig.workTimeSeconds - timeInCurrentCycle
            } else {
                return 0 // Completed final work period
            }
        } else {
            // Normal work-rest cycles
            switch currentPhase {
            case .work:
                return intervalConfig.workTimeSeconds - timeInCurrentCycle
            case .rest:
                return singleCycleTime - timeInCurrentCycle
            case .completed:
                return 0
            case .getReady:
                return 5 // Get ready phase is always 5 seconds
            }
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

        // Add rest time between sequences if configured
        if config.isRepeating, let restBetweenSequences = config.restTimeBetweenIntervals, restBetweenSequences > 0 {
            // Rest between sequences: (repeatCount - 1) * restTime
            let restPeriodsBetweenSequences = max(0, repeatMultiplier - 1)
            totalProgramTime += restPeriodsBetweenSequences * restBetweenSequences
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
            
            // Add rest time between sequences
            if config.isRepeating, let restBetweenSequences = config.restTimeBetweenIntervals, restBetweenSequences > 0 {
                let restPeriodsBetweenSequences = max(0, multiplier - 1)
                calculatedTotalTime += restPeriodsBetweenSequences * restBetweenSequences
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
        
        // Always start with Get Ready phase for 5 seconds
        state = .getReady
        currentTime = 0
        totalElapsedTime = 0
        currentInterval = 0
        currentRepetition = 0
        currentSequenceRepeat = 0
        currentPhase = .getReady
        isInBetweenIntervalRest = false
        betweenIntervalRestStartTime = 0
        laps = []
        lastBeepTime = -1
        
        startTime = Date()
        startTimer()
        //playSound(.start) //since it always starts with 5 seconds getReady, skip the start sound
    }
    
    
    // MARK: - Get Ready Phase Management
    private func handleGetReadyPhase() {
        let getReadyTimeRemaining = 5 - currentTime
        
        // Use the same precise countdown beep logic as other phases
        // Countdown beeps for get ready phase (all 5 seconds)
        if getReadyTimeRemaining >= 1 && getReadyTimeRemaining <= 5 && lastBeepTime != getReadyTimeRemaining {
            lastBeepTime = getReadyTimeRemaining
            
            // Schedule the beep to play precisely at the beginning of the second
            // This helps synchronize the beep with the actual countdown timing
            DispatchQueue.main.async { [weak self] in
                self?.playCountdownBeep()
            }
        }
        
        // Transition from Get Ready to actual timer
        if currentTime >= 5 {
            state = .running
            currentTime = 0
            totalElapsedTime = 0
            startTime = Date() // Reset start time for actual timer
            
            // Set initial phase based on configuration
            if let config = configuration {
                if config.hasIntervals && !config.intervals.isEmpty {
                    let firstInterval = config.intervals[0]
                    currentPhase = firstInterval.workTimeSeconds > 0 ? .work : .rest
                } else {
                    currentPhase = .work
                }
            }
            
            // Play transition sound
            playSound(.restToWork) // Sound to indicate actual timer is starting
            lastBeepTime = -1 // Reset beep tracking
        }
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
    }
    
    // MARK: - Restart Functionality
    func restart() {
        guard configuration != nil else { return }
        
        // Stop current timer
        stopTimer()
        
        // Reset all timing variables but keep the configuration
        currentTime = 0
        totalElapsedTime = 0
        currentInterval = 0
        currentRepetition = 0
        currentSequenceRepeat = 0
        currentPhase = .work
        isInBetweenIntervalRest = false
        betweenIntervalRestStartTime = 0
        startTime = nil
        pausedTime = nil
        laps.removeAll()
        lastBeepTime = -1
        
        // Keep the configuration but clear the session (new session will be created)
        session = nil
        
        // Set state to stopped so user can start again
        state = .stopped
        
        playSound(.stop)
    }
    
    // MARK: - Private Methods
    private func startTimer() {
        // Use a more frequent timer for better precision (0.1 seconds instead of 1.0)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
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
        
        // Use more precise time calculation
        let preciseElapsed = Date().timeIntervalSince(startTime)
        let elapsed = Int(preciseElapsed)
        
        // Only update if the second has actually changed to avoid redundant calculations
        guard elapsed != currentTime else { return }
        
        currentTime = elapsed
        totalElapsedTime = elapsed
        
        // Handle Get Ready phase first
        if state == .getReady {
            handleGetReadyPhase()
            return
        }
        
        // Always update interval progress for interval-based timers
        if let config = configuration, config.hasIntervals {
            updateIntervalProgress()
        }
        
        // Always check for completion regardless of timer type
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
        
        // Calculate time within current interval (excluding previous intervals and rest periods)
        let timeInCurrentInterval = calculateTimeInCurrentInterval()
        
        // New logic: Calculate which work/rest cycle we're in and the phase
        let singleCycleTime = interval.workTimeSeconds + interval.restTimeSeconds
        let currentCycle = timeInCurrentInterval / singleCycleTime
        let timeInCurrentCycle = timeInCurrentInterval % singleCycleTime
        
        // Determine current phase and time remaining
        let (newPhase, timeRemainingInPhase): (IntervalPhase, Int)
        
        if currentCycle >= interval.repetitions {
            // We've completed all repetitions, should move to next interval
            newPhase = .completed
            timeRemainingInPhase = 0
        } else if currentCycle == interval.repetitions - 1 {
            // Last repetition - only work phase, no rest after
            if timeInCurrentCycle < interval.workTimeSeconds {
                newPhase = .work
                timeRemainingInPhase = interval.workTimeSeconds - timeInCurrentCycle
            } else {
                // Completed final work period - move to next interval
                newPhase = .completed
                timeRemainingInPhase = 0
            }
        } else {
            // Normal work-rest cycles (not the last repetition)
            if timeInCurrentCycle < interval.workTimeSeconds {
                newPhase = .work
                timeRemainingInPhase = interval.workTimeSeconds - timeInCurrentCycle
            } else {
                newPhase = .rest
                timeRemainingInPhase = singleCycleTime - timeInCurrentCycle
            }
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
        if newPhase != .completed {
            checkCountdownBeeps(timeRemaining: timeRemainingInPhase)
        }
        
        // Update repetition counter
        let newRepetition = min(currentCycle + (timeInCurrentCycle >= interval.workTimeSeconds ? 1 : 0), interval.repetitions)
        if newRepetition > currentRepetition {
            currentRepetition = newRepetition
        }
        
        // Check if we've completed ALL repetitions for this interval
        if currentRepetition >= interval.repetitions && timeInCurrentInterval >= interval.totalTimeSeconds {
            moveToNextInterval()
        }
    }
    
    private func calculateTimeInCurrentInterval() -> Int {
        guard let config = configuration else { return 0 }
        
        var totalPreviousTime = 0
        
        // Add time from previous sequence repeats (including rest periods between sequences)
        if currentSequenceRepeat > 0 {
            let timePerSequence = config.intervals.reduce(0) { sum, interval in
                sum + interval.totalTimeSeconds
            }
            
            totalPreviousTime += currentSequenceRepeat * timePerSequence
            
            // Add rest time between previous sequences
            if let restBetweenSequences = config.restTimeBetweenIntervals, restBetweenSequences > 0 {
                totalPreviousTime += currentSequenceRepeat * restBetweenSequences
            }
        }
        
        // Add time from all previous intervals in current sequence
        for i in 0..<currentInterval {
            let prevInterval = config.intervals[i]
            totalPreviousTime += prevInterval.totalTimeSeconds
            
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
            // Complete the rest between sequences - start next sequence
            isInBetweenIntervalRest = false
            currentPhase = .work
            lastBeepTime = -1
            // Play the same sound as when transitioning from rest to work
            playSound(.restToWork)
            // currentInterval is already set to 0 from checkForCompletion
            // currentRepetition is already set to 0 from checkForCompletion
        }
    }
    
    private func moveToNextInterval() {
        guard let config = configuration else { return }
        
        // Check if this is the last interval in the current sequence
        let nextInterval = currentInterval + 1
        
        if nextInterval >= config.intervals.count {
            // We've completed all intervals in the current sequence
            // This will trigger the sequence repeat logic in checkForCompletion
            currentInterval = nextInterval // This will make currentInterval >= totalIntervals
        } else {
            // Move to the next interval within the current sequence
            completeIntervalTransition()
        }
    }
    
    private func completeIntervalTransition() {
        isInBetweenIntervalRest = false
        
        // If we're completing a rest between sequences, don't increment currentInterval
        // because it was already reset to 0 in checkForCompletion()
        if !isInBetweenIntervalRest {
            currentInterval += 1
        }
        
        currentRepetition = 0
        
        if currentInterval < configuration?.intervals.count ?? 0 {
            currentPhase = .work
            lastBeepTime = -1
        }
    }
    
    private func checkCountdownBeeps(timeRemaining: Int) {
        // Only beep for the last 3 seconds and ensure we haven't already beeped for this second
        if timeRemaining >= 1 && timeRemaining <= 3 && lastBeepTime != timeRemaining {
            lastBeepTime = timeRemaining
            
            // Schedule the beep to play precisely at the beginning of the second
            // This helps synchronize the beep with the actual countdown timing
            DispatchQueue.main.async { [weak self] in
                self?.playCountdownBeep()
            }
        }
    }
    
    private func playCountdownBeep() {
        // Use a distinct sound for countdown beeps with haptic feedback for better user experience
        AudioServicesPlaySystemSound(1103) // SMS received sound (short beep)
        
        // Add subtle haptic feedback for countdown beeps (optional)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
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
            
            // Don't process completion if we're already in rest between sequences
            if isInBetweenIntervalRest {
                return
            }
            
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
    
    func reset() {
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
        state = .reseted
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

// MARK: - Background Handling Setup
extension TimerManager {
    private func setupBackgroundHandling() {
        // Use more specific notifications for actual background/foreground transitions
        notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppDidEnterBackground()
            }
        }
        
        notificationCenter.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppWillEnterForeground()
            }
        }
    }
    
    private func handleAppDidEnterBackground() {
        // Only track background time if timer is running
        guard state == .running else { return }
        
        backgroundTime = Date()
        wasInBackground = true
        // Keep timer running - iOS will suspend it, but we'll recalculate on return
    }
    
    private func handleAppWillEnterForeground() {
        // Only handle if we were actually in background and timer is running
        guard state == .running, wasInBackground else {
            backgroundTime = nil
            wasInBackground = false
            return
        }
        
        // If we have a background time, catch up with error handling
        if let backgroundTime = backgroundTime, let startTime = startTime {
            // Calculate the total elapsed time based on current time
            let totalElapsed = Int(Date().timeIntervalSince(startTime))
            
            // Validate that the elapsed time makes sense
            guard totalElapsed >= 0 && totalElapsed < 86400 else { // Sanity check: less than 24 hours
                // If time calculation seems wrong, stop the timer to prevent inconsistent state
                stop()
                return
            }
            
            // Calculate background duration for validation
            let backgroundDuration = Int(Date().timeIntervalSince(backgroundTime))
            
            // Only proceed if background duration is reasonable
            guard backgroundDuration >= 0 && backgroundDuration < 3600 else { // Less than 1 hour in background
                // If we were in background too long, the timer state might be unreliable
                stop()
                return
            }
            
            // Update our state to match reality
            currentTime = totalElapsed
            totalElapsedTime = totalElapsed
            
            // Update interval progress to catch up
            updateIntervalProgress()
            checkForCompletion()
        }
        
        // Clear background state
        backgroundTime = nil
        wasInBackground = false
        
        // Ensure timer is running if we're in running state
        if timer == nil {
            startTimer()
        }
    }
}
