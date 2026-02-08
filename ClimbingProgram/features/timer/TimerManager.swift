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
import ActivityKit

// MARK: - TimerManager
@MainActor
@Observable
class TimerManager {
    // MARK: Published state (used by the UI)
    var state: TimerState = .stopped
    var currentTime: Int = 0                 // whole seconds since engine start (includes get-ready)
    var totalElapsedTime: Int = 0            // whole seconds excluding get-ready
    var currentInterval: Int = 0             // index in configuration.intervals
    var currentRepetition: Int = 0           // repetition index within the current interval
    var currentSequenceRepeat: Int = 0       // set index (0-based)
    var currentPhase: IntervalPhase = .work
    var laps: [TimerLap] = []
    private(set) var isInBetweenIntervalRest: Bool = false

    // MARK: Data
    var configuration: TimerConfiguration?
    var session: TimerSession?

    // MARK: Internals
    private var lastLapTime: Int = 0

    // New engine + ticker
    private var engine: TimerEngine?
    private var ticker: Ticker? = DispatchTicker(interval: 0.25)
    private var lastSnapshot: Snapshot? = nil

    // Segment → interval mapping (for multi-interval sets)
    private var segIntervalIndex: [Int] = []            // per segment → interval idx (−1 when N/A)
    private var segRepWithinInterval: [Int] = []        // per segment → rep idx for that interval (−1 when N/A)

    // Sounds
    private var lastBeepSecondForSegment: [Int: Int] = [:] // segIndex → last whole remaining second we beeped for

    // Pause bookkeeping
    private var pausedAtDuringGetReady: Bool = false

    // Background handling
    private var backgroundTime: Date?
    private var wasInBackground: Bool = false
    private var notificationCenter = NotificationCenter.default

    // MARK: Init / Deinit
    init() { setupBackgroundHandling() }

    // MARK: Flags
    var isRunning: Bool   { state == .running }
    var isPaused: Bool    { state == .paused }
    var isStopped: Bool   { state == .stopped }
    var isCompleted: Bool { state == .completed }
    var isReset: Bool     { state == .reseted }
    var isGetReady: Bool  { state == .getReady }

    private func refreshDerivedFlags() { isInBetweenIntervalRest = (currentPhase == .betweenSets) }

    var currentIntervalConfig: IntervalConfiguration? {
        guard let config = configuration, currentInterval >= 0, currentInterval < config.intervals.count else { return nil }
        return config.intervals[currentInterval]
    }

    // Primary display used by UI
    var displayTime: Int {
        guard let config = configuration else { return 0 }
        if state == .getReady { return max(0, 5 - currentTime) }
        if config.hasTotalTime && !config.hasIntervals {
            return totalElapsedTime - lastLapTime
        } else {
            return currentPhaseTimeRemaining
        }
    }

    // Remaining in the active phase (interval mode). For total timer we don’t use this.
    var currentPhaseTimeRemaining: Int {
        if currentPhase == .betweenSets {
            // engine snapshot already gives the remaining time in between-sets segment
            if let s = lastSnapshot { return max(0, Int(ceil(s.segmentRemaining))) }
            return 0
        }
        if state == .getReady { return max(0, 5 - currentTime) }
        if let s = lastSnapshot {
            return max(0, Int(ceil(s.segmentRemaining)))
        }
        return 0
    }

    var totalTimeRemaining: Int {
        guard let config = configuration else { return 0 }
        if let totalTime = config.totalTimeSeconds {
            return max(0, totalTime - totalElapsedTime)
        }
        let totalIntervalTime = config.intervals.reduce(0) { sum, interval in sum + interval.totalTimeSeconds }
        let repeats = config.isRepeating ? (config.repeatCount ?? 1) : 1
        var total = totalIntervalTime * repeats
        if config.isRepeating, let restBetween = config.restTimeBetweenIntervals, restBetween > 0 {
            total += max(0, repeats - 1) * restBetween
        }
        return max(0, total - totalElapsedTime)
    }

    var progressPercentage: Double {
        guard let config = configuration else { return 0 }
        let total: Int
        if let t = config.totalTimeSeconds { total = t }
        else {
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

    // MARK: Configuration Management
    func loadConfiguration(_ configuration: TimerConfiguration) {
        self.configuration = configuration
        // Preview-only reset
        state = .stopped
        currentTime = 0
        totalElapsedTime = 0
        currentInterval = 0
        currentRepetition = 0
        currentSequenceRepeat = 0
        currentPhase = configuration.hasIntervals ? .getReady : .work
        refreshDerivedFlags()
        laps = []
        lastLapTime = 0

        // Clear engine & mapping
        ticker?.stop()
        engine = nil
        lastSnapshot = nil
        segIntervalIndex = []
        segRepWithinInterval = []
        lastBeepSecondForSegment = [:]
        pausedAtDuringGetReady = false

        // Session
        session = nil

        // Debug
        if configuration.hasIntervals {
            let reps = configuration.isRepeating ? (configuration.repeatCount ?? 1) : 1
            print("TimerManager.loadConfiguration: intervals loaded; sets=\(reps), restBetween=\(configuration.restTimeBetweenIntervals ?? 0)s")
        } else if let total = configuration.totalTimeSeconds {
            print("TimerManager.loadConfiguration: total-time loaded; total=\(total)s")
        } else {
            print("TimerManager.loadConfiguration: unknown config")
        }
    }

    // MARK: Control
    func start(with configuration: TimerConfiguration, session: TimerSession? = nil) {
        self.configuration = configuration
        self.session = session

        // Build engine timeline
        let build: (timeline: Timeline, segIntervalIndex: [Int], segRepWithinInterval: [Int])
        if configuration.hasTotalTime && !configuration.hasIntervals, let total = configuration.totalTimeSeconds {
            // TOTAL TIMER: getReady + single work segment
            let tl = TimerEngine.buildTotalTimer(work: TimeInterval(total), getReady: 5)
            let count = tl.segments.count
            build = (tl,
                     Array(repeating: -1, count: count), // interval mapping not used in total mode
                     Array(repeating: -1, count: count)) // rep mapping not used in total mode
        } else {
            // INTERVAL TIMER
            build = buildTimelineAndMappings(from: configuration)
        }

        engine = TimerEngine(timeline: build.timeline)
        segIntervalIndex = build.segIntervalIndex
        segRepWithinInterval = build.segRepWithinInterval
        lastSnapshot = nil
        lastBeepSecondForSegment = [:]

        // Initial state → get ready
        state = .getReady
        currentTime = 0
        totalElapsedTime = 0
        currentInterval = 0
        currentRepetition = 0
        currentSequenceRepeat = 0
        currentPhase = .getReady
        pausedAtDuringGetReady = false
        refreshDerivedFlags()
        laps = []

        engine?.start()
        startTicker()
        UIApplication.shared.isIdleTimerDisabled = true

        // Debug dump
        if configuration.hasIntervals {
            let sets = configuration.isRepeating ? (configuration.repeatCount ?? 1) : 1
            print("TimerManager.start: intervals; sets=\(sets), restBetween=\(configuration.restTimeBetweenIntervals ?? 0)s, intervals=\(configuration.intervals.count)")
        } else if let total = configuration.totalTimeSeconds {
            print("TimerManager.start: total-time; total=\(total)s")
        }
    }

    func pause() {
        guard state == .running || state == .getReady else { return }
        pausedAtDuringGetReady = (state == .getReady)
        engine?.pause()
        state = .paused
        UIApplication.shared.isIdleTimerDisabled = false
        print("TimerManager.pause")
        playSound(.pause)
    }

    func resume() {
        guard state == .paused else { return }
        engine?.resume()
        state = pausedAtDuringGetReady ? .getReady : .running
        startTicker()
        UIApplication.shared.isIdleTimerDisabled = true
        print("TimerManager.resume")
        playSound(.resume)
    }

    func stop() {
        state = .stopped
        ticker?.stop()
        engine?.reset()
        UIApplication.shared.isIdleTimerDisabled = false
        if let session = session {
            session.endDate = Date()
            session.totalElapsedSeconds = totalElapsedTime
            session.completedIntervals = currentInterval
            session.wasCompleted = false
        }
        reset()
        print("TimerManager.stop")
        playSound(.stop)
    }

    func complete() {
        state = .completed
        currentPhase = .completed
        refreshDerivedFlags()
        ticker?.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        if let session = session {
            session.endDate = Date()
            session.totalElapsedSeconds = totalElapsedTime
            session.completedIntervals = currentInterval
            session.wasCompleted = true
        }
        print("TimerManager.complete @ totalElapsed=\(totalElapsedTime)")
        playSound(.complete)
    }

    func addLap(notes: String? = nil) {
        let lap = TimerLap(lapNumber: laps.count + 1, elapsedSeconds: totalElapsedTime, notes: notes)
        laps.append(lap)
        session?.laps.append(lap)
        if let config = configuration, config.hasTotalTime && !config.hasIntervals {
            lastLapTime = totalElapsedTime
            playSound(.lap)
            print("TimerManager.addLap #\(lap.lapNumber) @ \(totalElapsedTime)s")
        }
    }

    // Restart but keep configuration
    func restart() {
        guard configuration != nil else { return }
        ticker?.stop()
        engine?.reset()
        currentTime = 0
        totalElapsedTime = 0
        currentInterval = 0
        currentRepetition = 0
        currentSequenceRepeat = 0
        currentPhase = .work
        refreshDerivedFlags()
        laps.removeAll()
        lastBeepSecondForSegment = [:]
        session = nil
        pausedAtDuringGetReady = false
        state = .stopped
        print("TimerManager.restart → stopped (same config)")
        playSound(.stop)
    }

    func reset() {
        ticker?.stop()
        engine?.reset()
        configuration = nil
        session = nil
        currentTime = 0
        totalElapsedTime = 0
        currentInterval = 0
        currentRepetition = 0
        currentSequenceRepeat = 0
        currentPhase = .work
        refreshDerivedFlags()
        laps = []
        lastLapTime = 0
        lastBeepSecondForSegment = [:]
        pausedAtDuringGetReady = false
        state = .reseted
    }

    // MARK: Ticker → Snapshot bridge
    private func startTicker() {
        ticker?.stop()
        ticker?.start { [weak self] in
            Task { @MainActor in self?.onTick() }
        }
    }

    private func onTick() {
        guard let engine else { return }
        let snap = engine.snapshot()

        // Publish basic counters
        currentTime = Int(snap.absoluteElapsed.rounded(.down))
        totalElapsedTime = Int(snap.countedElapsed.rounded(.down))

        // State & phase
        if snap.isCompleted {
            if state != .completed { complete() }
            lastSnapshot = snap
            return
        }

        if engine.isPaused { state = .paused }
        else if let seg = snap.segment, seg.kind == .getReady { state = .getReady }
        else { state = .running }

        // Map to IntervalPhase
        let newPhase: IntervalPhase = {
            guard let seg = snap.segment else { return .completed }
            switch seg.kind {
            case .getReady: return .getReady
            case .work: return .work
            case .rest: return .rest
            case .betweenSets: return .betweenSets
            }
        }()
        if newPhase != currentPhase { currentPhase = newPhase; refreshDerivedFlags() }

        // Map indices
        if let idx = snap.segmentIndex {
            if idx < segIntervalIndex.count {
                let iIdx = segIntervalIndex[idx]
                currentInterval = max(0, iIdx)
            }
            if idx < segRepWithinInterval.count {
                let rIdx = segRepWithinInterval[idx]
                currentRepetition = max(0, rIdx)
            }
            currentSequenceRepeat = max(0, snap.currentSetIndex)
        }

        // Sounds (phase transitions & countdown)
        fireSounds(previous: lastSnapshot, current: snap)


        lastSnapshot = snap
    }

    private func fireSounds(previous: Snapshot?, current: Snapshot) {
        // Suppress sounds when starting timer
        guard previous != nil else { return }
        // Phase changes
        if previous?.segmentIndex != current.segmentIndex {
            // Transition cues
            switch (previous?.segment?.kind, current.segment?.kind) {
            case (.some(.rest), .some(.work)), (.some(.betweenSets), .some(.work)), (.some(.getReady), .some(.work)):
                playSound(.restToWork)
            case (.some(.work), .some(.rest)):
                playSound(.workToRest)
            case (.some(.rest), .some(.betweenSets)):
                playSound(.intervalToInterval)
            default:
                playSound(.phaseChange)
            }
            // Reset per-segment beep cache
            if let idx = current.segmentIndex { lastBeepSecondForSegment[idx] = -1 }
        }

        // 3-2-1 countdown within the active segment
        if let idx = current.segmentIndex {
            let remainingWhole = Int(ceil(current.segmentRemaining))
            if [3,2,1].contains(remainingWhole), lastBeepSecondForSegment[idx] != remainingWhole {
                playSound(.countdown)
                lastBeepSecondForSegment[idx] = remainingWhole
            }
        }
    }

    // MARK: Timeline builder for full configuration
    private func buildTimelineAndMappings(from config: TimerConfiguration) -> (timeline: Timeline, segIntervalIndex: [Int], segRepWithinInterval: [Int]) {
        var segments: [Segment] = []
        var cumulative: [TimeInterval] = []
        var countedCumulative: [TimeInterval] = []
        var setIndex: [Int] = []
        var repIndex: [Int] = []
        var segToInterval: [Int] = []
        var segToRepWithin: [Int] = []

        var running: TimeInterval = 0
        var countedRunning: TimeInterval = 0

        func push(_ s: Segment, set: Int, rep: Int, intervalIdx: Int, repWithinInterval: Int) {
            segments.append(s)
            running += s.duration
            cumulative.append(running)
            if s.countsTowardTotal { countedRunning += s.duration }
            countedCumulative.append(countedRunning)
            setIndex.append(set)
            repIndex.append(rep)
            segToInterval.append(intervalIdx)
            segToRepWithin.append(repWithinInterval)
        }

        // get-ready 5s (not counted)
        push(Segment(kind: .getReady, duration: 5, countsTowardTotal: false), set: -1, rep: -1, intervalIdx: -1, repWithinInterval: -1)

        // Determine sets
        let sets = config.isRepeating ? max(1, (config.repeatCount ?? 1)) : 1
        let restBetween: TimeInterval = TimeInterval(config.restTimeBetweenIntervals ?? 0)

        for set in 0..<sets {
            // Repetition counter across the set (for engine’s repIndex – keep it simple by using repWithinInterval)
            for (intervalIdx, interval) in config.intervals.enumerated() {
                let reps = max(1, interval.repetitions)
                let work = TimeInterval(max(0, interval.workTimeSeconds))
                let rest = TimeInterval(max(0, interval.restTimeSeconds))

                for repWithin in 0..<reps {
                    // Work
                    if work > 0 {
                        push(Segment(kind: .work, duration: work, countsTowardTotal: true),
                             set: set, rep: repWithin, intervalIdx: intervalIdx, repWithinInterval: repWithin)
                    }
                    // Rest only between repetitions of the SAME interval
                    if repWithin < reps - 1, rest > 0 {
                        push(Segment(kind: .rest, duration: rest, countsTowardTotal: true),
                             set: set, rep: repWithin, intervalIdx: intervalIdx, repWithinInterval: repWithin)
                    }
                }
            }
            // Between sets (only if more sets ahead)
            if set < sets - 1, restBetween > 0 {
                push(Segment(kind: .betweenSets, duration: restBetween, countsTowardTotal: true),
                     set: set, rep: -1, intervalIdx: -1, repWithinInterval: -1)
            }
        }

        let timeline = Timeline(
            segments: segments,
            cumulativeEnds: cumulative,
            countedCumulativeEnds: countedCumulative,
            totalSets: sets,
            repsPerSet: 0, // not used for multi-interval; Live Activity reps come from current interval config
            segmentSetIndex: setIndex,
            segmentRepIndex: repIndex
        )
        return (timeline, segToInterval, segToRepWithin)
    }
}

// MARK: - Formatting helpers (used by views)
extension TimerManager {
    func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remMinutes = minutes % 60
            return "\(hours):\(twoDigit(remMinutes)):\(twoDigit(remainingSeconds))"
        } else {
            return "\(minutes):\(twoDigit(remainingSeconds))"
        }
    }

    func formatTimeDetailed(_ seconds: Int) -> (hours: Int, minutes: Int, seconds: Int) {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return (h, m, s)
    }

    private func twoDigit(_ value: Int) -> String {
        value.formatted(.number.grouping(.never).precision(.integerLength(2)))
    }
}

// MARK: - Background handling
extension TimerManager {
    private func setupBackgroundHandling() {
        notificationCenter.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleAppDidEnterBackground() }
        }
        notificationCenter.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleAppWillEnterForeground() }
        }
    }

    private func handleAppDidEnterBackground() {
        guard state == .running || state == .getReady else { return }
        backgroundTime = Date()
        wasInBackground = true
        print("TimerManager.didEnterBackground at t=\(currentTime), phase=\(currentPhase)")
    }

    private func handleAppWillEnterForeground() {
        guard wasInBackground else { return }
        wasInBackground = false
        print("TimerManager.willEnterForeground at t=\(currentTime), phase=\(currentPhase)")
    }
}

// MARK: - Sound routing
extension TimerManager {
    private enum SoundType { case start, pause, resume, stop, complete, lap, phaseChange, intervalChange, workToRest, restToWork, intervalToInterval, countdown }
    private func playSound(_ type: SoundType) {
        switch type {
        case .start, .resume: AudioServicesPlaySystemSound(1104) // Begin record
        case .pause, .stop:   AudioServicesPlaySystemSound(1105) // End record
        case .complete:       AudioServicesPlaySystemSound(1016) // Tock
        case .lap:            AudioServicesPlaySystemSound(1057) // Tink
        case .phaseChange, .intervalChange: AudioServicesPlaySystemSound(1054) // Timer
        case .workToRest:     AudioServicesPlaySystemSound(1053) // Chime
        case .restToWork:     AudioServicesPlaySystemSound(1052) // Bell
        case .intervalToInterval: AudioServicesPlaySystemSound(1051) // Tri-tone
        case .countdown:      AudioServicesPlaySystemSound(1156) // Short beep
        }
    }
}
