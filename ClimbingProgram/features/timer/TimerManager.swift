//
//  TimerManager.swift
//  Klettrack
//  Created by Shahar Noy on 25.08.25.
//

import Foundation
import SwiftUI
import Combine
import AVFoundation
import AudioToolbox

@MainActor
class TimerManager: ObservableObject {
    // MARK: - Published state (used by the UI)
    @Published var state: TimerState = .stopped
    @Published var currentTime: Int = 0                 // whole seconds since current phase start (or since startDate in our accounting)
    @Published var totalElapsedTime: Int = 0            // whole seconds since timer started (excludes get-ready once transitioned)
    @Published var currentInterval: Int = 0
    @Published var currentRepetition: Int = 0
    @Published var currentSequenceRepeat: Int = 0       // which repeat of the whole intervals sequence we’re on (0-based)
    @Published var currentPhase: IntervalPhase = .work
    @Published var laps: [TimerLap] = []
    @Published var isInBetweenIntervalRest: Bool = false

    // MARK: - Internals
    private var lastLapTime: Int = 0
    private var timer: Timer?
    private var startTime: Date?
    private var pausedTime: Date?
    private var lastBeepTime: Int = -1                  // stores the “remaining seconds” we already beeped for in this phase
    private var betweenIntervalRestStartTime: Int = 0

    // Pause bookkeeping (to correctly resume get-ready)
    private var wasPausedDuringGetReady: Bool = false

    // Background handling
    private var backgroundTime: Date?
    private var wasInBackground: Bool = false
    private var notificationCenter = NotificationCenter.default

    // Data
    var configuration: TimerConfiguration?
    var session: TimerSession?

    // MARK: - Init / Deinit
    init() {
        setupBackgroundHandling()
    }

    deinit {
        notificationCenter.removeObserver(self)
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Computed flags
    var isRunning: Bool   { state == .running }
    var isPaused: Bool    { state == .paused }
    var isStopped: Bool   { state == .stopped }
    var isCompleted: Bool { state == .completed }
    var isReset: Bool     { state == .reseted }
    var isGetReady: Bool  { state == .getReady }

    var currentIntervalConfig: IntervalConfiguration? {
        guard let config = configuration,
              currentInterval < config.intervals.count else { return nil }
        return config.intervals[currentInterval]
    }

    /// Primary display the UI uses
    var displayTime: Int {
        guard let config = configuration else { return 0 }

        // Get Ready shows 5 → 0
        if state == .getReady {
            return max(0, 5 - currentTime)
        }

        if config.hasTotalTime && !config.hasIntervals {
            // Total-time: iOS-like laps count from last lap
            return totalElapsedTime - lastLapTime
        } else {
            // Interval mode: show remaining in the current phase
            return currentPhaseTimeRemaining
        }
    }

    /// Remaining time in the current *interval* phase (work/rest), or “rest between sets”
    var currentPhaseTimeRemaining: Int {
        if isInBetweenIntervalRest {
            guard let config = configuration,
                  let restBetween = config.restTimeBetweenIntervals else { return 0 }
            let restElapsed = currentTime - betweenIntervalRestStartTime
            return max(0, restBetween - restElapsed)
        }

        guard let intervalConfig = currentIntervalConfig else { return 0 }

        let timeInCurrentInterval = calculateTimeInCurrentInterval()
        let singleCycleTime = intervalConfig.workTimeSeconds + intervalConfig.restTimeSeconds
        let currentCycle = singleCycleTime == 0 ? 0 : timeInCurrentInterval / singleCycleTime
        let timeInCurrentCycle = singleCycleTime == 0 ? 0 : timeInCurrentInterval % singleCycleTime

        // Last repetition has no trailing rest
        if currentCycle == intervalConfig.repetitions - 1 {
            if timeInCurrentCycle < intervalConfig.workTimeSeconds {
                return intervalConfig.workTimeSeconds - timeInCurrentCycle
            } else {
                return 0 // finished final work
            }
        } else {
            switch currentPhase {
            case .work:
                return max(0, intervalConfig.workTimeSeconds - timeInCurrentCycle)
            case .rest:
                return max(0, singleCycleTime - timeInCurrentCycle)
            case .completed:
                return 0
            case .getReady:
                return 5
            }
        }
    }

    var totalTimeRemaining: Int {
        guard let config = configuration else { return 0 }

        if let totalTime = config.totalTimeSeconds {
            return max(0, totalTime - totalElapsedTime)
        }

        // intervals path
        let totalIntervalTime = config.intervals.reduce(0) { sum, interval in
            sum + interval.totalTimeSeconds
        }
        let repeats = config.isRepeating ? (config.repeatCount ?? 1) : 1
        var total = totalIntervalTime * repeats

        // add rest between sequences (sets)
        if config.isRepeating,
           let restBetween = config.restTimeBetweenIntervals, restBetween > 0 {
            total += max(0, repeats - 1) * restBetween
        }

        return max(0, total - totalElapsedTime)
    }

    var progressPercentage: Double {
        guard let config = configuration else { return 0 }
        let total: Int
        if let t = config.totalTimeSeconds {
            total = t
        } else {
            let intervalTime = config.intervals.reduce(0) { $0 + $1.totalTimeSeconds }
            let repeats = config.isRepeating ? (config.repeatCount ?? 1) : 1
            var calc = intervalTime * repeats
            if config.isRepeating, let restBetween = config.restTimeBetweenIntervals, restBetween > 0 {
                calc += max(0, repeats - 1) * restBetween
            }
            total = calc
        }
        guard total > 0 else { return 0 }
        let raw = Double(totalElapsedTime) / Double(total)
        if raw.isNaN || raw.isInfinite { return 0 }
        return min(1.0, max(0.0, raw))
    }

    // MARK: - Configuration Management
    func loadConfiguration(_ configuration: TimerConfiguration) {
        self.configuration = configuration

        // Reset timer state (preview mode – shows config without starting)
        state = .stopped
        currentTime = 0
        totalElapsedTime = 0
        currentInterval = 0
        currentRepetition = 0
        currentSequenceRepeat = 0
        currentPhase = configuration.hasIntervals ? .work : .work
        laps = []
        lastLapTime = 0

        // Clear session and timers
        session = nil
        stopTimer()
        startTime = nil
        pausedTime = nil
        lastBeepTime = -1
        isInBetweenIntervalRest = false
        betweenIntervalRestStartTime = 0
        wasPausedDuringGetReady = false
    }

    // MARK: - Timer Control
    func start(with configuration: TimerConfiguration, session: TimerSession? = nil) {
        self.configuration = configuration
        self.session = session

        // Always start with Get Ready 5s
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
        wasPausedDuringGetReady = false

        startTime = Date()
        startTimer()
        // playSound(.start) // optional; omitted because get-ready has its own cadence
    }

    private func handleGetReadyPhase() {
        let getReadyRemaining = 5 - currentTime

        // Beep for all 5 seconds in get-ready (you had this behavior before)
        if getReadyRemaining >= 1 && getReadyRemaining <= 5 && lastBeepTime != getReadyRemaining {
            lastBeepTime = getReadyRemaining
            DispatchQueue.main.async { [weak self] in
                self?.playCountdownBeep()
            }
        }

        if currentTime >= 5 {
            // Transition to running
            state = .running
            currentTime = 0
            totalElapsedTime = 0
            startTime = Date() // reset for actual timer accounting

            if let config = configuration, config.hasIntervals, !config.intervals.isEmpty {
                let first = config.intervals[0]
                currentPhase = (first.workTimeSeconds > 0) ? .work : .rest
            } else {
                currentPhase = .work
            }

            playSound(.restToWork) // signal start of real timer
            lastBeepTime = -1
        }
    }

    func pause() {
        // Allow pausing during running **and** get-ready
        guard state == .running || state == .getReady else { return }

        wasPausedDuringGetReady = (state == .getReady)
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

        // If we paused during get-ready, resume in get-ready; otherwise resume running
        state = wasPausedDuringGetReady ? .getReady : .running
        startTimer()
        playSound(.resume)
    }

    func stop() {
        state = .stopped
        stopTimer()

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
        currentPhase = .completed
        stopTimer()

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
        session?.laps.append(lap)

        if let config = configuration, config.hasTotalTime && !config.hasIntervals {
            lastLapTime = totalElapsedTime
            playSound(.lap)
        }
    }

    // Restart but keep configuration
    func restart() {
        guard configuration != nil else { return }
        stopTimer()

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
        session = nil
        wasPausedDuringGetReady = false

        state = .stopped
        playSound(.stop)
    }

    // MARK: - Timer wiring
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTime()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Tick
    private func updateTime() {
        guard let startTime = startTime else { return }

        let preciseElapsed = Date().timeIntervalSince(startTime)
        let elapsed = Int(preciseElapsed)

        // Only on whole-second change
        guard elapsed != currentTime else { return }

        currentTime = elapsed

        // get-ready has its own accounting & sounds
        if state == .getReady {
            handleGetReadyPhase()
            return
        }

        // Once running/paused/resumed beyond get-ready, totalElapsedTime tracks the program
        totalElapsedTime = elapsed

        if let config = configuration, config.hasIntervals {
            updateIntervalProgress()
        } else if let total = configuration?.totalTimeSeconds {
            // total-time path: also do 3-2-1 beeps (this was missing)
            let remaining = max(0, total - totalElapsedTime)
            checkCountdownBeeps(timeRemaining: remaining)
        }

        checkForCompletion()
    }

    // MARK: - Interval engine
    internal func updateIntervalProgress() {
        guard let config = configuration, config.hasIntervals else { return }
        guard currentInterval < config.intervals.count else { return }

        if isInBetweenIntervalRest {
            handleBetweenIntervalRest()
            return
        }

        let interval = config.intervals[currentInterval]
        let timeInCurrentInterval = calculateTimeInCurrentInterval()

        let singleCycleTime = interval.workTimeSeconds + interval.restTimeSeconds
        let currentCycle = singleCycleTime == 0 ? 0 : timeInCurrentInterval / singleCycleTime
        let timeInCurrentCycle = singleCycleTime == 0 ? 0 : timeInCurrentInterval % singleCycleTime

        // Determine new phase & time remaining
        let (newPhase, timeRemainingInPhase): (IntervalPhase, Int)

        if currentCycle >= interval.repetitions {
            newPhase = .completed
            timeRemainingInPhase = 0
        } else if currentCycle == interval.repetitions - 1 {
            // Last repetition (no trailing rest)
            if timeInCurrentCycle < interval.workTimeSeconds {
                newPhase = .work
                timeRemainingInPhase = interval.workTimeSeconds - timeInCurrentCycle
            } else {
                newPhase = .completed
                timeRemainingInPhase = 0
            }
        } else {
            if timeInCurrentCycle < interval.workTimeSeconds {
                newPhase = .work
                timeRemainingInPhase = interval.workTimeSeconds - timeInCurrentCycle
            } else {
                newPhase = .rest
                timeRemainingInPhase = singleCycleTime - timeInCurrentCycle
            }
        }

        // Phase change sounds: rest → work chime
        if currentPhase != newPhase {
            if currentPhase == .rest && newPhase == .work {
                playSound(.restToWork)
            } else if currentPhase == .work && newPhase == .rest {
                playSound(.workToRest)
            } else if newPhase == .completed {
                playSound(.intervalToInterval) // finishing an interval
            }
            lastBeepTime = -1 // reset countdown beeps when phase flips
        }

        currentPhase = newPhase

        // Countdown beeps in last 3 seconds of a phase (work/rest)
        checkCountdownBeeps(timeRemaining: timeRemainingInPhase)

        // Move to next interval as needed
        if newPhase == .completed {
            moveToNextInterval()
        }
    }

    private func calculateTimeInCurrentInterval() -> Int {
        guard let config = configuration else { return 0 }

        var totalPreviousTime = 0

        // previous full sequences (interval sums + rest between sequences)
        if currentSequenceRepeat > 0 {
            let timePerSequence = config.intervals.reduce(0) { $0 + $1.totalTimeSeconds }
            totalPreviousTime += currentSequenceRepeat * timePerSequence

            if let restBetween = config.restTimeBetweenIntervals, restBetween > 0 {
                totalPreviousTime += currentSequenceRepeat * restBetween
            }
        }

        // previous intervals in the current sequence
        if currentInterval > 0 {
            for i in 0..<currentInterval {
                totalPreviousTime += config.intervals[i].totalTimeSeconds
            }
        }

        // time within current interval = total program elapsed - previous program segments
        return currentTime - totalPreviousTime
    }

    private func handleBetweenIntervalRest() {
        guard let config = configuration,
              let restBetween = config.restTimeBetweenIntervals else { return }

        let restElapsed = currentTime - betweenIntervalRestStartTime
        let restRemaining = restBetween - restElapsed

        checkCountdownBeeps(timeRemaining: restRemaining)

        if restElapsed >= restBetween {
            isInBetweenIntervalRest = false
            currentPhase = .work
            lastBeepTime = -1
            playSound(.restToWork)
            // next sequence continues from interval index 0
        }
    }

    private func moveToNextInterval() {
        guard let config = configuration else { return }
        let next = currentInterval + 1

        if next >= config.intervals.count {
            // finished the intervals list; check sequence repeats in checkForCompletion()
            currentInterval = next
        } else {
            completeIntervalTransition()
        }
    }

    private func completeIntervalTransition() {
        isInBetweenIntervalRest = false
        // increment interval
        currentInterval += 1
        currentRepetition = 0

        if currentInterval < (configuration?.intervals.count ?? 0) {
            currentPhase = .work
            lastBeepTime = -1
            // NEW: sound when new interval starts (rest→work feel)
            playSound(.restToWork)
        }
    }

    // MARK: - Sounds (countdown & phase)
    private func checkCountdownBeeps(timeRemaining: Int) {
        // Beep at 3,2,1 remaining once per logical second
        if timeRemaining >= 1 && timeRemaining <= 3 && lastBeepTime != timeRemaining {
            lastBeepTime = timeRemaining
            DispatchQueue.main.async { [weak self] in
                self?.playCountdownBeep()
            }
        }
    }

    private func playCountdownBeep() {
        // Keep your existing “countdown” sound mapping here
        playSound(.countdown)
    }

    // MARK: - Completion
    internal func checkForCompletion() {
        guard let config = configuration else { return }

        // total-time completion
        if let totalTime = config.totalTimeSeconds, totalElapsedTime >= totalTime {
            complete()
            return
        }

        // interval completion path
        if config.hasIntervals {
            let totalIntervals = config.intervals.count
            let repeatCount = config.isRepeating ? (config.repeatCount ?? 1) : 1

            if isInBetweenIntervalRest { return } // rest between sequences still in progress

            if currentInterval >= totalIntervals {
                // finished one full sequence
                currentSequenceRepeat += 1

                if currentSequenceRepeat >= repeatCount {
                    complete()
                    return
                } else {
                    // another sequence to go
                    if let restBetween = config.restTimeBetweenIntervals, restBetween > 0 {
                        isInBetweenIntervalRest = true
                        betweenIntervalRestStartTime = currentTime
                        currentPhase = .rest
                        currentInterval = 0
                        currentRepetition = 0
                        playSound(.intervalToInterval)
                        lastBeepTime = -1
                    } else {
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
        currentSequenceRepeat = 0
        currentPhase = .work
        isInBetweenIntervalRest = false
        betweenIntervalRestStartTime = 0
        lastLapTime = 0
        startTime = nil
        pausedTime = nil
        configuration = nil
        session = nil
        laps.removeAll()
        lastBeepTime = -1
        wasPausedDuringGetReady = false
        state = .reseted
    }

    // MARK: - Formatting helpers (used by views)
    func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remMinutes = minutes % 60
            return String(format: "%d:%02d:%02d", hours, remMinutes, remainingSeconds)
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

    // MARK: - Background handling
    private func setupBackgroundHandling() {
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
        guard state == .running || state == .getReady else { return }
        backgroundTime = Date()
        wasInBackground = true
        // Timer continues to run logically; we recompute on foreground via startTime
    }

    private func handleAppWillEnterForeground() {
        guard wasInBackground else { return }
        wasInBackground = false

        // nothing special; our updateTime computes from startTime, so we “catch up”
        // If you ever want to auto-pause after long background, you could check duration here.
    }

    // MARK: - Sound routing
    private enum SoundType {
        case start, pause, resume, stop, complete, lap, phaseChange, intervalChange, workToRest, restToWork, intervalToInterval, countdown
    }

    private func playSound(_ type: SoundType) {
        switch type {
        case .start, .resume:
            AudioServicesPlaySystemSound(1104) // Begin record
        case .pause, .stop:
            AudioServicesPlaySystemSound(1105) // End record
        case .complete:
            AudioServicesPlaySystemSound(1016) // Tock
        case .lap:
            AudioServicesPlaySystemSound(1057) // Tink
        case .phaseChange, .intervalChange:
            AudioServicesPlaySystemSound(1054) // Timer
        case .workToRest:
            AudioServicesPlaySystemSound(1053) // Chime
        case .restToWork:
            AudioServicesPlaySystemSound(1052) // Bell
        case .intervalToInterval:
            AudioServicesPlaySystemSound(1051) // Tri-tone
        case .countdown:
            AudioServicesPlaySystemSound(1156) // Short beep; adjust if you prefer your previous ID
        }
    }
}
