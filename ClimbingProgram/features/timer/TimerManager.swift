//
//  TimerManager.swift
//  Klettrack
//  Created by Shahar Noy on 25.08.25.
//

import Foundation
import SwiftUI
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

    /// Active rep-based set sequence, if any. See `startSetSequence`.
    private(set) var setSequence: SetSequence?

    /// A rep-based exercise: do N reps, confirm, rest, repeat.
    ///
    /// This lives above the engine rather than inside the timeline. Each rest is an
    /// ordinary total-time timer, so `TimerEngine`'s time math is untouched — a
    /// "wait for the user" segment would have no duration, which breaks its
    /// invariant that position is a pure function of elapsed seconds.
    struct SetSequence: Equatable {
        let repsPerSet: Int?
        /// `var` because `addSet` extends the plan mid-session — an attempts-based
        /// session doesn't know its try count up front.
        var totalSets: Int
        let restSeconds: Int
        /// Decides whether the log panel offers added load, and what one unit of work
        /// is called. Declared before the defaulted fields so it stays a required
        /// memberwise argument — a `let` *with* a default is left out of the
        /// memberwise init entirely, which would make it unsettable.
        let shape: ExerciseShape
        var currentSet: Int = 1          // 1-based
        var accumulatedSeconds: Int = 0  // summed across completed rests

        var isFinalSet: Bool { currentSet >= totalSets }
    }

    // MARK: Per-set log (rep-based sequences)

    /// One entry per planned set, seeded when the sequence starts so that advancing
    /// past a set you never touched still records it at its planned values.
    private(set) var setLogs: [LoggedSet] = []

    /// Which set the log panel is editing, 0-based. Independent of `currentSet`:
    /// reviewing set 1 mid-rest must not move the timer.
    private(set) var editingSetIndex: Int = 0

    /// The weight every set was seeded with, for the panel's "Last: N kg" caption.
    private(set) var seedWeightKg: Double?

    /// How many sets were actually confirmed with Done. High-water mark, so stepping
    /// back to correct set 2 of 4 doesn't retract sets 3 and 4.
    ///
    /// `setLogs` holds a row per *planned* set — that is what lets you skip ahead to a
    /// pre-filled set — so it cannot answer "how much did I do". Ending a 5-set
    /// prescription after 3 must log three sets, not five.
    private(set) var performedSetCount: Int = 0

    /// The sets to write to the log: those confirmed, in order. Empty until the first
    /// Done, so abandoning a sequence immediately logs nothing.
    var performedSetLogs: [LoggedSet] {
        Array(setLogs.prefix(performedSetCount))
    }

    /// How a set reads in the panel, derived rather than stored.
    enum SetStatus: Equatable { case done, current, upcoming }

    func setStatus(at index: Int) -> SetStatus {
        guard let sequence = setSequence else { return .upcoming }
        let setNumber = index + 1
        if setNumber < sequence.currentSet { return .done }
        if setNumber > sequence.currentSet { return .upcoming }
        // The current set counts as done once we've moved on to resting after it.
        return state == .awaitingUser ? .current : .done
    }

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
    var isAwaitingUser: Bool { state == .awaitingUser }

    /// True while a rep-based sequence is in flight — used to avoid clobbering it.
    var hasActiveSetSequence: Bool { setSequence != nil }

    private func refreshDerivedFlags() { isInBetweenIntervalRest = (currentPhase == .betweenSets) }

    var currentIntervalConfig: IntervalConfiguration? {
        guard let config = configuration, currentInterval >= 0, currentInterval < config.intervals.count else { return nil }
        return config.intervals[currentInterval]
    }

    // Primary display used by UI
    var displayTime: Int {
        guard let config = configuration else { return 0 }
        if state == .getReady { return max(0, 5 - currentTime) }
        // A rest between sets is a countdown, not a stopwatch.
        if setSequence != nil, let total = config.totalTimeSeconds {
            return max(0, total - totalElapsedTime)
        }
        if config.hasTotalTime && !config.hasIntervals {
            return max(0, totalElapsedTime - lastLapTime)
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

    /// How far through the whole exercise, 0...1 — not how far through the current phase.
    var progressPercentage: Double {
        if state == .completed { return 1 }

        // A set sequence's configuration describes one rest, so measuring time against
        // it would report the rest's progress instead of the exercise's. Count sets
        // instead: each set plus the rest that follows it is one equal slice, so
        // finishing set 2 of 4 and its rest lands exactly on 50%.
        if let sequence = setSequence {
            let completedSets = Double(sequence.currentSet - 1)
            // Waiting on a set contributes nothing: the work itself isn't timed.
            var restFraction = 0.0
            if !isAwaitingUser, sequence.restSeconds > 0 {
                restFraction = min(1, Double(totalElapsedTime) / Double(sequence.restSeconds))
            }
            let slices = Double(max(1, sequence.totalSets))
            return min(1, max(0, (completedSets + restFraction) / slices))
        }

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
            // TOTAL TIMER: optional getReady + single work segment
            let tl = TimerEngine.buildTotalTimer(
                work: TimeInterval(total),
                getReady: configuration.getReady ? 5 : 0
            )
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

        // Initial state → get ready, unless the timeline skips it (e.g. rests in a set sequence)
        let startsWithGetReady = build.timeline.segments.first?.kind == .getReady
        state = startsWithGetReady ? .getReady : .running
        currentTime = 0
        totalElapsedTime = 0
        currentInterval = 0
        currentRepetition = 0
        currentSequenceRepeat = 0
        currentPhase = startsWithGetReady ? .getReady : (setSequence != nil ? .rest : .work)
        pausedAtDuringGetReady = false
        refreshDerivedFlags()
        laps = []
        // Must be cleared alongside `laps`: displayTime for a total timer is
        // totalElapsedTime - lastLapTime, so a stale lap from a previous run
        // makes the next one start negative.
        lastLapTime = 0

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

    // MARK: Rep-based set sequence

    /// Begin a rep-based exercise. Lands on the Set 1 prompt with nothing counting;
    /// the caller supplies one session that spans the whole sequence.
    ///
    /// `seedWeightKg` pre-fills every set, so skipping ahead needs no special case —
    /// the row for an untouched set already holds its planned reps and weight.
    func startSetSequence(
        reps: Int?,
        sets: Int,
        restSeconds: Int,
        seedWeightKg: Double? = nil,
        shape: ExerciseShape = .weighted,
        session: TimerSession? = nil
    ) {
        ticker?.stop()
        engine = nil
        lastSnapshot = nil
        self.session = session
        self.configuration = TimerConfiguration(totalTimeSeconds: restSeconds)
        let totalSets = max(1, sets)
        setSequence = SetSequence(
            repsPerSet: reps, totalSets: totalSets, restSeconds: restSeconds, shape: shape
        )

        self.seedWeightKg = seedWeightKg
        setLogs = (0..<totalSets).map { _ in
            LoggedSet(reps: reps.map(Double.init), weightKg: seedWeightKg)
        }
        editingSetIndex = 0

        currentTime = 0
        totalElapsedTime = 0
        laps = []
        lastLapTime = 0
        state = .awaitingUser
        UIApplication.shared.isIdleTimerDisabled = true
        print("TimerManager.startSetSequence: sets=\(max(1, sets)), reps=\(reps.map(String.init) ?? "-"), rest=\(restSeconds)s")
    }

    /// The user finished the current set. Starts the rest, or finishes the sequence
    /// after the final set (no trailing rest).
    func confirmSet() {
        guard let sequence = setSequence, state == .awaitingUser else { return }
        // Done is the only thing that makes a set count as performed. Skipping past one
        // with the chevron deliberately doesn't.
        performedSetCount = max(performedSetCount, sequence.currentSet)

        if sequence.isFinalSet {
            finishSetSequence()
            return
        }

        // Rest before the next set, reusing the sequence's single session.
        // No get-ready: you tapped Done because the set is over, so the rest starts now.
        // `start` leaves `setSequence` alone, so our bookkeeping survives it.
        start(
            with: TimerConfiguration(totalTimeSeconds: sequence.restSeconds, getReady: false),
            session: session
        )
    }

    /// End the current rest early and move straight to the next set.
    /// The time actually rested still counts, so cutting a 3 min rest at 2 min logs 2 min.
    func skipRest() {
        guard setSequence != nil, !isAwaitingUser, state != .completed else { return }
        advanceSetSequence()
    }

    /// Called when a rest countdown finishes and more sets remain.
    /// Internal rather than private so tests can drive it without waiting out a real rest.
    func advanceSetSequence() {
        guard let sequence = setSequence else { return }
        goToSet(sequence.currentSet + 1)
    }

    /// Park on `target`'s prompt, 1-based and clamped to the sequence. Used by the
    /// rest completing, by Skip, and by the panel's set arrows.
    ///
    /// Any time already spent resting is banked first, so jumping — forwards or
    /// backwards — never invents or discards rest time.
    func goToSet(_ target: Int) {
        guard var sequence = setSequence, state != .completed else { return }
        let clamped = min(max(1, target), sequence.totalSets)
        // Already parked on that prompt: nothing to tear down.
        guard clamped != sequence.currentSet || state != .awaitingUser else { return }

        sequence.accumulatedSeconds += totalElapsedTime
        sequence.currentSet = clamped
        setSequence = sequence
        // Via `selectSet` rather than assigning the index, so arriving by chevron and
        // arriving by chip tap carry the weight forward the same way.
        selectSet(at: clamped - 1)

        ticker?.stop()
        engine = nil
        lastSnapshot = nil
        currentTime = 0
        totalElapsedTime = 0
        state = .awaitingUser
        print("TimerManager.goToSet → set \(clamped) of \(sequence.totalSets)")
        playSound(.restToWork)
    }

    /// Forward one set. From a set prompt this is the skip: the set keeps the values
    /// it was seeded with and is logged as-is. Mid-rest it cuts the rest short.
    func nextSet() {
        guard let sequence = setSequence, state != .completed else { return }
        guard isAwaitingUser else {
            skipRest()
            return
        }
        if sequence.isFinalSet {
            finishSetSequence()
        } else {
            goToSet(sequence.currentSet + 1)
        }
    }

    /// Back one set, to redo it or correct what was recorded. No-op on set 1's prompt.
    func previousSet() {
        guard let sequence = setSequence else { return }
        goToSet(sequence.currentSet - 1)
    }

    /// Room for one more than planned.
    ///
    /// A limit session's try count isn't knowable in advance — you stop when you stop.
    /// Without this, under-estimating it ends the session on the final `nextSet`
    /// (see `nextSet`), with no way to keep going.
    ///
    /// Doesn't touch the clock or the current set: this only extends the plan.
    func addSet() {
        guard var sequence = setSequence, state != .completed else { return }
        sequence.totalSets += 1
        setSequence = sequence
        setLogs.append(
            LoggedSet(reps: sequence.repsPerSet.map(Double.init), weightKg: seedWeightKg)
        )
    }

    // MARK: Editing the per-set log

    /// Move the panel's editing cursor without touching the clock.
    ///
    /// A set with no weight of its own inherits the last one actually recorded, so
    /// landing on set 2 shows the working weight rather than an empty box.
    /// `startSetSequence` already pre-fills every set from history; this is the same
    /// policy with a fresher source, and the only one available when the exercise has
    /// never been logged.
    func selectSet(at index: Int) {
        guard setLogs.indices.contains(index) else { return }
        editingSetIndex = index
        // Only when unset, which is what makes this safe going backwards: returning to
        // a set to correct it never overwrites what is already there.
        if setLogs[index].weightKg == nil,
           let carried = setLogs[..<index].compactMap(\.weightKg).last {
            setLogs[index].weightKg = carried
        }
    }

    /// Mutate one set's record. One entry point rather than a setter per field, so
    /// "leave unchanged" and "set to nil" never get confused.
    func updateSet(at index: Int, _ mutate: (inout LoggedSet) -> Void) {
        guard setLogs.indices.contains(index) else { return }
        mutate(&setLogs[index])
    }

    /// Only for the abort paths. Finishing a sequence deliberately leaves the log
    /// intact — the log sheet reads it after completion.
    private func clearSetLogs() {
        setLogs = []
        editingSetIndex = 0
        seedWeightKg = nil
        performedSetCount = 0
    }

    /// Abandon any set sequence, for a caller about to run something unrelated.
    ///
    /// `start()` deliberately leaves `setSequence` alone — a sequence runs each of its
    /// rests *through* `start()`, so clearing it there would tear down the thing driving
    /// the call. That leaves loading a template mid-sequence to clear it explicitly;
    /// without this, the set panel and the REST label stayed bolted to a template that
    /// knows nothing about them.
    func clearSetSequence() {
        setSequence = nil
        clearSetLogs()
    }

    /// End the sequence here: write the summed elapsed time and land in the completed
    /// state. Reached by confirming the final set, or by Finish on any earlier one —
    /// a prescription of five sets you answer with three is a normal training day, not
    /// an abort, so it completes and offers the log like any other finish.
    func finishSetSequence() {
        guard let sequence = setSequence else { return }
        ticker?.stop()
        engine = nil
        state = .completed
        currentPhase = .completed
        refreshDerivedFlags()
        UIApplication.shared.isIdleTimerDisabled = false

        if let session {
            session.endDate = Date()
            session.totalElapsedSeconds = sequence.accumulatedSeconds
            // What was done, not what was asked for.
            session.completedIntervals = performedSetCount
            session.wasCompleted = true
        }
        setSequence = nil
        print("TimerManager.finishSetSequence: \(performedSetCount) of \(sequence.totalSets) sets, \(sequence.accumulatedSeconds)s resting")
        playSound(.complete)
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
        // Abort any set sequence first, or a later completion would resurrect it.
        let sequenceElapsed = setSequence?.accumulatedSeconds ?? 0
        setSequence = nil

        state = .stopped
        ticker?.stop()
        engine?.reset()
        UIApplication.shared.isIdleTimerDisabled = false
        if let session = session {
            session.endDate = Date()
            session.totalElapsedSeconds = totalElapsedTime + sequenceElapsed
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
        setSequence = nil
        clearSetLogs()
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
        setSequence = nil
        clearSetLogs()
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
            // A rest inside a set sequence finishes the rest, not the exercise.
            if setSequence != nil {
                advanceSetSequence()
                return
            }
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
            // A set-sequence rest runs on a plain total timer, so its segment is a
            // work block. It is a rest to the user, and must read as one.
            if setSequence != nil, seg.kind == .work { return .rest }
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

        // get-ready 5s (not counted), unless the configuration opts out
        if config.getReady {
            push(Segment(kind: .getReady, duration: 5, countsTowardTotal: false), set: -1, rep: -1, intervalIdx: -1, repWithinInterval: -1)
        }

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
