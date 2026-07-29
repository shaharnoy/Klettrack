//
//  TimerViews.swift
//  Klettrack
//  Created by Shahar Noy on 25.08.25.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Main Timer View
struct TimerView: View {
    private enum SheetRoute: String, Identifiable {
        case templateSelector
        case customTimer
        case allTemplates
        case timerSetup
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(TimerAppState.self) private var timerAppState

    // Keep shared timer manager alive in view state and observe via @Observable tracking
    @State private var sharedTimerManager = SharedTimerManager.shared

    @State private var sheetRoute: SheetRoute?

    /// Exercise context we have already applied, so re-entering the tab doesn't reload it.
    @State private var appliedExercise: ExerciseTimerContext?
    @State private var loggingExercise: ExerciseTimerContext?
    /// A different exercise arrived while a timer was in flight — ask before replacing it.
    @State private var pendingExercise: ExerciseTimerContext?

    let planDay: PlanDay?
    var exercise: ExerciseTimerContext? = nil

    /// The exercise actually loaded, not the one most recently tapped. While a switch is
    /// pending these differ, and showing the incoming name would misrepresent what's running.
    private var exerciseName: String? { appliedExercise?.exerciseName }

    /// A timer that is mid-flight and would be lost by loading something else.
    /// A merely loaded-but-stopped configuration is not busy and can be replaced silently.
    private var timerIsBusy: Bool {
        timerManager.isRunning
            || timerManager.isPaused
            || timerManager.isGetReady
            || timerManager.isAwaitingUser
            || timerManager.hasActiveSetSequence
    }

    // Computed property to access the timer manager
    private var timerManager: TimerManager {
        sharedTimerManager.timerManager
    }

    var body: some View {
        NavigationStack {
            // Scrolls because the content genuinely doesn't fit: with the set log panel
            // open, a fixed VStack pushed the Pause/Reset row off the bottom of the
            // screen, so a running rest couldn't be paused at all. Also what keeps the
            // controls reachable at larger Dynamic Type sizes.
            ScrollView {
                VStack(spacing: 20) {
                    // Exercise context (when launched from a plan day exercise)
                    if let exerciseName {
                        VStack(spacing: 4) {
                            Label(exerciseName, systemImage: "figure.climbing")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            // Technique cue from the catalog, most useful mid-set.
                            if let blurb = appliedExercise?.exerciseDescription {
                                Text(blurb)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if let sequence = timerManager.setSequence {
                        // Rep-based exercise. Waiting on a set shows no clock — nothing is
                        // being counted. Resting shows the countdown above the same panel,
                        // so a weight can still be corrected mid-rest.
                        if timerManager.isAwaitingUser {
                            // On the same card the clock uses, in its place — the set
                            // prompt is what the countdown becomes, not a lesser state.
                            SetNavigationRow(
                                timerManager: timerManager,
                                sequence: sequence,
                                label: "\(sequence.shape.unitLabel) \(sequence.currentSet) OF \(sequence.totalSets)",
                                labelColor: .primary
                            )
                            .timerCard()
                        } else {
                            timerDisplaySection
                            restSkipSection(sequence)
                        }

                        SetLogPanel(timerManager: timerManager, sequence: sequence)
                    } else {
                        timerDisplaySection
                    }

                    // Progress Indicators
                    if timerManager.configuration != nil && !timerManager.isAwaitingUser {
                        progressSection
                    }

                    // Control Buttons (without Stop & Reset)
                    controlButtonsSection

                    // Laps Section - only show for total time timers, not interval timers
                    if !timerManager.laps.isEmpty && timerManager.configuration?.hasIntervals == false {
                        lapsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
            // Only scroll when there is something to scroll to, so a short timer screen
            // still feels fixed rather than rubber-banding.
            .scrollBounceBehavior(.basedOnSize)
            //.navigationTitle("TIMER")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // The timer is a tab, not a pushed view, so there is no back button
                    // of its own — you arrive from a plan day and get stranded. Switching
                    // back is enough: the Plans tab keeps its navigation path, so this
                    // lands on the very day you left, and the timer keeps running.
                    //
                    // ponytail: tab 2 hardcoded because both switchToTimer call sites are
                    // in PlansViews. Record an origin tab on TimerAppState if a third
                    // entry point ever appears.
                    if planDay != nil {
                        Button("Plan", systemImage: "chevron.left") {
                            timerAppState.selectedTab = 2
                        }
                        .accessibilityLabel("Back to the plan day")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        // Main menu
                        Menu {
                            Section("Timer Setup") {
                                Button("Select Template", systemImage: "bolt.fill") {
                                    sheetRoute = .templateSelector
                                }
                                Button("Custom Timer", systemImage: "gearshape.fill") {
                                    sheetRoute = .customTimer
                                }
                            }

                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                        }
                    }
                }
            }
            .sheet(item: $sheetRoute) { route in
                switch route {
                case .templateSelector:
                    TimerTemplateSelector { template in
                        loadTemplate(template)
                    }
                case .allTemplates:
                    TimerTemplatesListView()
                case .customTimer:
                    CustomTimerSetupWithContext { config in
                        startTimer(with: config)
                    }
                case .timerSetup:
                    TimerSetupView(planDay: planDay) { config, template in
                        // Load the configuration immediately to display on screen
                        timerManager.loadConfiguration(config)

                        // Update template usage but don't start the timer
                        if let template = template {
                            template.lastUsedDate = Date()
                            template.useCount += 1
                            try? context.save()
                        }
                    }
                }
            }
        }
        .onAppear {
            // Keep screen on when timer view appears
            updateScreenIdleTimer()
            applyExerciseIfNeeded()
        }
        .onChange(of: exercise) { _, _ in
            applyExerciseIfNeeded()
        }
        .onChange(of: timerManager.isCompleted) { _, completed in
            // Offer the log form when an exercise-launched timer finishes.
            guard completed, let exercise, exercise == appliedExercise else { return }
            loggingExercise = exercise
        }
        .confirmationDialog(
            "Timer in progress",
            isPresented: Binding(
                get: { pendingExercise != nil },
                set: { if !$0 { pendingExercise = nil } }
            ),
            presenting: pendingExercise
        ) { next in
            Button("Start \(next.exerciseName)", role: .destructive) {
                timerManager.stop()
                apply(next)
                pendingExercise = nil
            }
            Button("Keep \(exerciseName ?? "current timer")", role: .cancel) {
                // Put the running exercise back so the label matches what's actually timing.
                timerAppState.exerciseContext = appliedExercise
                pendingExercise = nil
            }
        } message: { next in
            Text("\(exerciseName ?? "A timer") is still going. Starting \(next.exerciseName) will discard it.")
        }
        .sheet(item: $loggingExercise) { context in
            // Wall work logs as a climb — grade, angle, style — which is what the plan
            // row already opens for it. Anything else logs as a session item.
            if context.shape == .attempts {
                // Presented bare: ClimbLogForm brings its own NavigationStack, as every
                // other call site relies on. The title matches the plan row's wording.
                ClimbLogForm(
                    title: "Climb Log for \(context.exerciseName)",
                    initialDate: context.planDayDate,
                    initialAttempts: timerManager.setLogs.count
                )
            } else {
                ExerciseLogSheet(
                    exerciseName: context.exerciseName,
                    date: context.planDayDate,
                    planId: context.planId,
                    planName: context.planName,
                    prefill: logPrefill(for: context),
                    onSaved: {}
                )
            }
        }
        .onDisappear {
            // Allow screen to sleep when timer view disappears
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: timerManager.isRunning) { _, isRunning in
            // Update screen idle timer when timer state changes
            updateScreenIdleTimer()
        }
        .onChange(of: timerManager.isPaused) { _, isPaused in
            // Update screen idle timer when pause state changes
            updateScreenIdleTimer()
        }
    }
    
    // MARK: - Rest between sets
    private func restSkipSection(_ sequence: TimerManager.SetSequence) -> some View {
        let nextSet = min(sequence.currentSet + 1, sequence.totalSets)

        // The total-timer display has no phase label of its own, so the nav row
        // carries it. Forward here ends the rest early, which is what Skip rest did.
        return VStack(spacing: 6) {
            SetNavigationRow(
                timerManager: timerManager,
                sequence: sequence,
                label: "REST",
                labelColor: .orange
            )

            Text("Next up: set \(nextSet) of \(sequence.totalSets)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Exercise plan application

    /// Load the exercise's timer once. If one is already in flight, ask first
    /// rather than silently discarding it.
    private func applyExerciseIfNeeded() {
        guard let exercise, exercise != appliedExercise else { return }
        guard !timerIsBusy else {
            pendingExercise = exercise
            return
        }
        apply(exercise)
    }

    private func apply(_ exercise: ExerciseTimerContext) {
        appliedExercise = exercise

        switch exercise.plan {
        case .repBased(let reps, let sets, let restSeconds, let templateId):
            let session = TimerSession(
                templateId: templateId,
                planDayId: planDay?.id,
                exerciseName: exercise.exerciseName
            )
            context.insert(session)
            try? context.save()
            timerManager.startSetSequence(
                reps: reps,
                sets: sets,
                restSeconds: restSeconds,
                // Start every set where you left off last time rather than at zero —
                // but only where load is part of the exercise at all.
                seedWeightKg: exercise.shape.takesLoad
                    ? lastLoggedWeight(for: exercise.exerciseName, in: context)
                    : nil,
                shape: exercise.shape,
                session: session
            )

        case .durationBased(let config, _):
            timerManager.loadConfiguration(config)

        case nil:
            break
        }
    }

    /// What the timer knows that the plan row doesn't: how long it actually ran,
    /// and how many sets were planned. Weight/grade/notes stay blank on purpose.
    ///
    /// A rep-based sequence knows more than that — it has a record of each set — so
    /// it prefills from actuals rather than from the plan's counts.
    private func logPrefill(for exercise: ExerciseTimerContext) -> ExerciseLogSheet.Prefill {
        let elapsed = timerManager.session?.totalElapsedSeconds
        if !timerManager.setLogs.isEmpty {
            return .init(loggedSets: timerManager.setLogs, durationSeconds: elapsed)
        }
        switch exercise.plan {
        case .repBased(let reps, let sets, _, _):
            return .init(reps: reps, sets: sets, durationSeconds: elapsed)
        case .durationBased(let config, _):
            return .init(
                reps: config.intervals.first?.repetitions,
                sets: config.repeatCount,
                durationSeconds: elapsed
            )
        case nil:
            return .init(reps: nil, sets: nil, durationSeconds: elapsed)
        }
    }

    // MARK: - Screen Management
    private func updateScreenIdleTimer() {
        // Keep screen on when timer is running or paused (but not stopped)
        UIApplication.shared.isIdleTimerDisabled = timerManager.isRunning || timerManager.isPaused
    }
    
    // MARK: - Timer Display Section
    private var timerDisplaySection: some View {
        VStack(spacing: 16) {
            // Main phase display - this is what users care about most
            if timerManager.isGetReady {
                // Get Ready phase display
                VStack(spacing: 8) {
                    // Get Ready countdown (main focus - biggest)
                    Text(timerManager.formatTime(timerManager.displayTime))
                        .font(.system(size: 72, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .contentTransition(.numericText())
                    
                    // Get Ready label below
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(.blue.opacity(0.2))
                                .frame(width: 16, height: 16)
                            Circle()
                                .fill(.blue)
                                .frame(width: 10, height: 10)
                        }
                        
                        Text("Get Ready")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.blue)
                            .frame(minWidth: 240, alignment: .center)
                            .multilineTextAlignment(.center)
                    }
                }
            } else if timerManager.configuration?.hasIntervals == true {
                VStack(spacing: 8) {
                    // Phase time remaining (main focus - biggest)
                    if timerManager.currentPhaseTimeRemaining > 0 {
                        Text(timerManager.formatTime(timerManager.currentPhaseTimeRemaining))
                            .font(.system(size: 72, weight: .ultraLight, design: .monospaced))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: timerManager.isRunning ? [getPhaseColor(), getPhaseColor().opacity(0.7)] : [.secondary, .secondary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .contentTransition(.numericText())
                    }
                    
                    // Phase name below (prominent but smaller)
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(getPhaseColor().opacity(0.2))
                                .frame(width: 16, height: 16)
                            Circle()
                                .fill(getPhaseColor())
                                .frame(width: 10, height: 10)
                        }
                        
                        Text(getPhaseText())
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(getPhaseColor())
                            .frame(minWidth: 240, alignment: .center) // Fixed width to accommodate "Rest Between Iterations"
                            .multilineTextAlignment(.center)
                    }
                }
            } else {
                // Fallback to total time if no intervals
                // Total time mode: show countdown timer
                Text(timerManager.formatTime(timerManager.displayTime))
                    .font(.system(size: 72, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(
                        LinearGradient(
                            colors: timerManager.isRunning ? [.primary, .white] : [.secondary, .secondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .contentTransition(.numericText())
            }
            
            // Secondary information: total elapsed and remaining time (smaller, less
            // prominent). Omitted during a rest between sets: there the big countdown
            // already *is* the remaining time, so "Remaining" just repeats it and
            // "Elapsed" counts up through a rest nobody is trying to fill.
            if timerManager.setSequence == nil {
                HStack(spacing: 20) {
                    // Total elapsed time
                    VStack(spacing: 2) {
                        Text("Elapsed")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(timerManager.formatTime(timerManager.totalElapsedTime))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                    }

                    // Separator
                    Rectangle()
                        .fill(.secondary.opacity(0.3))
                        .frame(width: 1, height: 30)

                    // Total time remaining
                    let remaining = timerManager.totalTimeRemaining
                    if remaining > 0 {
                        VStack(spacing: 2) {
                            Text("Remaining")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(timerManager.formatTime(remaining))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                        }
                        .transition(.opacity.combined(with: .scale))
                    }
                }
            }
        }
        .timerCard()
    }

    // MARK: - Progress Section
    private var progressSection: some View {
        VStack(spacing: 16) {
            // Overall Progress with enhanced design
            VStack(spacing: 8) {
                HStack {
                    Text("Overall Progress")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(timerManager.progressPercentage * 100))%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                
                ProgressView(value: timerManager.progressPercentage)
                    .progressViewStyle(.linear)
                    .scaleEffect(y: 2.0)
                    .tint(.blue)
            }
            
            // Enhanced interval progress display
            if let config = timerManager.configuration, config.hasIntervals {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    // Iteration Card
                    if config.isRepeating, let repeatCount = config.repeatCount, repeatCount > 1 {
                        // Clamp current ≤ total and ensure total ≥ 1
                        let setsTotal = max(1, repeatCount)
                        let setsCurrent = min(timerManager.currentSequenceRepeat + 1, setsTotal)
                        ProgressCard(
                        title: "Sets",
                        current: setsCurrent,
                        total: setsTotal,
                        color: .purple,
                        icon: "arrow.clockwise"
                        )
                    }
                    // Rep Card
                    if timerManager.currentInterval < config.intervals.count {
                        let repTotal = max(1, config.intervals[timerManager.currentInterval].repetitions)
                        let repCurrent = min(timerManager.currentRepetition + 1, repTotal)
                        ProgressCard(
                            title: "Reps",
                            current: repCurrent,
                            total: repTotal,
                            color: .green,
                            icon: "repeat"
                        )
                    }
                }
            }
        }
        .timerCard(padding: 12)
    }
    
    // MARK: - Current Interval Section
    private func currentIntervalSection(_ config: IntervalConfiguration) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Work: \(timerManager.formatTime(config.workTimeSeconds))")
                Text("Rest: \(timerManager.formatTime(config.restTimeSeconds))")
            }
            .font(.subheadline)
            
            Spacer()
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(.rect(cornerRadius: 12))
    }
    
    // MARK: - Control Buttons Section
    private var controlButtonsSection: some View {
        VStack(spacing: 16) {
            // Primary control button
            if timerManager.isStopped {
                Button("Start") {
                    if timerManager.configuration == nil {
                        sheetRoute = .timerSetup
                    } else {
                        startTimerWithExistingConfig()
                    }
                }
                .buttonStyle(PrimaryTimerButtonStyle(color: .green))
            } else if timerManager.isCompleted {
                // Show both Restart and Reset options when timer is completed
                VStack(spacing: 16) {
                    Button("Restart") {
                        restartTimer()
                    }
                    .buttonStyle(PrimaryTimerButtonStyle(color: .green))
                    Button("Reset") {
                        timerManager.reset()
                    }
                    .buttonStyle(WideTimerButtonStyle(color: .red))
                }
            } else if timerManager.isRunning {
                // Enhanced: Wider buttons with equal distribution
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        Button("Pause") {
                            timerManager.pause()
                        }
                        .buttonStyle(WideTimerButtonStyle(color: .orange))
                        
                        // Only show Lap button for total time timers, not interval timers
                        if timerManager.configuration?.hasIntervals == false {
                            Button("Lap") {
                                timerManager.addLap()
                            }
                            .buttonStyle(WideTimerButtonStyle(color: .blue))
                        }
                        Button("Reset") {
                            timerManager.reset()
                        }
                        .buttonStyle(WideTimerButtonStyle(color: .red))
                    }
                    
                }
            } else if timerManager.isPaused {
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        Button("Resume") {
                            timerManager.resume()
                        }
                        .buttonStyle(WideTimerButtonStyle(color: .green))
                        
                        // Only show Lap button for total time timers, not interval timers
                        if timerManager.configuration?.hasIntervals == false {
                            Button("Lap") {
                                timerManager.addLap()
                            }
                            .buttonStyle(WideTimerButtonStyle(color: .blue))
                        }
                            Button("Reset") {
                                timerManager.reset()
                            }
                            .buttonStyle(WideTimerButtonStyle(color: .red))
                    }
                }
            }
            else if timerManager.isReset {
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        Button("Start") {
                            if timerManager.configuration == nil {
                                sheetRoute = .timerSetup
                            } else {
                                startTimerWithExistingConfig()
                            }
                        }
                        .buttonStyle(PrimaryTimerButtonStyle(color: .green))
                    }
                }
                }
            
        }
    }
    
    // Bug Fix 5: New method to handle starting timer with existing config
    private func startTimerWithExistingConfig() {
        guard let config = timerManager.configuration else {
            sheetRoute = .customTimer
            return
        }
        
        let session = TimerSession(planDayId: planDay?.id, exerciseName: exerciseName)
        context.insert(session)
        try? context.save()

        timerManager.start(with: config, session: session)
    }
    
    // MARK: - Laps Section
    private var lapsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Laps (\(timerManager.laps.count))")
                .font(.headline)
            
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(timerManager.laps, id: \.id) { lap in
                        LapRowView(lap: lap)
                    }
                }
            }
            .frame(maxHeight: 150)
        }
        .timerCard(padding: 16)
    }
    
    // MARK: - Helper Methods
    private func getPhaseColor() -> Color {
        if timerManager.isCompleted {
            return .gray
        } else if timerManager.isInBetweenIntervalRest {
            return .purple
        } else {
            switch timerManager.currentPhase {
            case .work: return .green
            case .rest: return .orange
            case .getReady: return .blue
            case .completed: return .gray
            case .betweenSets: return .purple
            }
        }
    }
    
    private func getPhaseText() -> String {
        if timerManager.isCompleted {
            return "Completed"
        } else if timerManager.isInBetweenIntervalRest {
            return "Rest Between Sets"
        } else {
            switch timerManager.currentPhase {
            case .work: return "Work"
            case .rest: return "Rest"
            case .getReady: return "Get Ready"
            case .completed: return "Completed"
            case .betweenSets: return "Rest Between Sets"
            }
        }
    }
    
    private func loadTemplate(_ template: TimerTemplate) {
        let intervals = template.intervals
            .sorted { $0.order < $1.order }
            .map { IntervalConfiguration(
                name: $0.name,
                workTimeSeconds: $0.workTimeSeconds,
                restTimeSeconds: $0.restTimeSeconds,
                repetitions: $0.repetitions
            )}
        
        let config = TimerConfiguration(
            totalTimeSeconds: template.totalTimeSeconds,
            intervals: intervals,
            isRepeating: template.isRepeating,
            repeatCount: template.repeatCount,
            restTimeBetweenIntervals: template.restTimeBetweenIntervals // Fix: Include rest between intervals
        )
        
        startTimer(with: config, template: template)
    }
    
    private func startTimer(with config: TimerConfiguration, template: TimerTemplate? = nil) {
        let session = TimerSession(
            templateId: template?.id,
            templateName: template?.name,
            planDayId: planDay?.id,
            exerciseName: exerciseName
        )
        
        context.insert(session)
        try? context.save()
        
        timerManager.start(with: config, session: session)
        
        // Update template usage
        if let template = template {
            template.lastUsedDate = Date()
            template.useCount += 1
            try? context.save()
        }
    }
    
    private func resumeTimer() {
        guard let config = timerManager.configuration else { return }
        let session = TimerSession(planDayId: planDay?.id, exerciseName: exerciseName)
        context.insert(session)
        timerManager.start(with: config, session: session)
    }
    
    // MARK: - Restart Timer
    private func restartTimer() {
        // Use the new restart method from TimerManager
        timerManager.restart()
    }
}

// MARK: - Lap Row View
struct LapRowView: View {
    let lap: TimerLap
    
    var body: some View {
        HStack {
            Text("#\(lap.lapNumber)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
            
            Text(formatTime(lap.elapsedSeconds))
                .font(.caption.monospaced())
            
            Spacer()
            
            if let notes = lap.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Text(lap.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        let paddedSeconds = remainingSeconds.formatted(.number.grouping(.never).precision(.integerLength(2)))
        return "\(minutes):\(paddedSeconds)"
    }
}

// MARK: - Card Chrome

/// The timer's one card surface: material, rounded, softly shadowed.
///
/// Every panel on this screen wore its own chrome — the clock on `.regularMaterial`
/// at radius 20, the set log and laps on flat `systemGray6` at 16 and 12. Waiting on
/// a set therefore looked like a different screen from resting between them, which is
/// what a plan-launched timer spends most of its time doing. One modifier instead, so
/// the shading the clock has is the shading everything has.
struct TimerCard: ViewModifier {
    var padding: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .padding(padding)
            // Full width for every card, so the surface doesn't resize underneath you
            // when a rest ends and the clock gives way to the set prompt.
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            )
    }
}

extension View {
    func timerCard(padding: CGFloat = 24) -> some View {
        modifier(TimerCard(padding: padding))
    }
}

// MARK: - Button Styles
struct PrimaryTimerButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 120, height: 50)
            .background(color)
            .clipShape(.rect(cornerRadius: 25))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryTimerButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
            .frame(width: 80, height: 36)
            .background(color.opacity(0.1))
            .clipShape(.rect(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Big Button Style (for Pause/Resume and Lap)
struct BigTimerButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(height: 60)
            .background(color)
            .clipShape(.rect(cornerRadius: 30))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Wide Button Style (for equal distribution)
struct WideTimerButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(color)
            .clipShape(.rect(cornerRadius: 25))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Full Width Button Style (for Stop & Reset)
struct FullWidthTimerButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(color)
            .clipShape(.rect(cornerRadius: 25))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Load Config Button Style (for Load Configuration button)
struct LoadConfigButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(color)
            .clipShape(.rect(cornerRadius: 22))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Timer Setup View with Tabs
struct TimerSetupView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    let planDay: PlanDay?
    let onConfigurationReady: (TimerConfiguration, TimerTemplate?) -> Void
    
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            VStack {
                // Tab Selection
                Picker("Setup Type", selection: $selectedTab) {
                    Text("Templates").tag(0)
                    Text("Custom").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Tab Content
                TabView(selection: $selectedTab) {
                    // Templates Tab
                    TimerTemplateSelectionTab(onTemplateSelected: { template in
                        let intervals = template.intervals
                            .sorted { $0.order < $1.order }
                            .map { IntervalConfiguration(
                                name: $0.name,
                                workTimeSeconds: $0.workTimeSeconds,
                                restTimeSeconds: $0.restTimeSeconds,
                                repetitions: $0.repetitions
                            )}
                        
                        let config = TimerConfiguration(
                            totalTimeSeconds: template.totalTimeSeconds,
                            intervals: intervals,
                            isRepeating: template.isRepeating,
                            repeatCount: template.repeatCount,
                            restTimeBetweenIntervals: template.restTimeBetweenIntervals
                        )
                        
                        onConfigurationReady(config, template)
                        dismiss()
                    })
                    .tag(0)
                    
                    // Custom Tab
                    CustomTimerSetupTab(planDay: planDay, onConfigurationReady: { config in
                        onConfigurationReady(config, nil)
                        dismiss()
                    })
                    .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Timer Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Timer Template Selection Tab
struct TimerTemplateSelectionTab: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\TimerTemplate.lastUsedDate, order: .reverse)]) private var templates: [TimerTemplate]
    
    let onTemplateSelected: (TimerTemplate) -> Void
    
    var body: some View {
        List {
            if templates.isEmpty {
                ContentUnavailableView(
                    "No Timer Templates",
                    systemImage: "timer",
                    description: Text("Create your first timer template to get started")
                )
            } else {
                ForEach(templates) { template in
                    TimerTemplateRowForSelection(template: template) {
                        onTemplateSelected(template)
                    }
                }
            }
        }
    }
}

// MARK: - Timer Template Row for Selection
struct TimerTemplateRowForSelection: View {
    let template: TimerTemplate
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(template.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    if template.useCount > 0 {
                        Text("Used \(template.useCount) times")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let description = template.templateDescription {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 36) {
                    // number of sets
                    if template.isRepeating {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise")
                            Text("\(template.repeatCount ?? 1)x")
                        }
                    }
                    // number of reps within a set
                    if !template.intervals.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "repeat")
                            Text("\(template.intervals.first?.repetitions ?? 0)")
                        }
                    }
                       
                    if let restBetween = template.restTimeBetweenIntervals, restBetween > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "pause.circle")
                            Text(formatTime(restBetween))
                        }
                    }
                    
                    if let totalTime = template.effectiveTotalTimeSeconds {
                        HStack(spacing: 3) {
                            Image(systemName: "clock.badge.checkmark")
                            Text(formatTime(totalTime))
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                
                if let lastUsed = template.lastUsedDate {
                    Text("Last used: \(lastUsed.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        } else {
            return "\(minutes)m \(remainingSeconds)s"
        }
    }
}

// MARK: - Custom Timer Setup Tab
struct CustomTimerSetupTab: View {
    @Environment(\.modelContext) private var context
    
    let planDay: PlanDay?
    let onConfigurationReady: (TimerConfiguration) -> Void
    
    @State private var timerType: TimerType = .totalTime
    @State private var totalTimeMinutes = 0
    @State private var totalTimeSeconds = 0
    @State private var intervals: [IntervalInput] = []
    @State private var isRepeating = false
    @State private var repeatCount = 2
    @State private var restBetweenIterationsMinutes = 0
    @State private var restBetweenIterationsSeconds = 0
    @State private var saveAsTemplate = false
    @State private var templateName = ""
    @State private var templateDescription = ""
    
    private enum TimerType: CaseIterable {
        case totalTime
        case intervals
        
        var title: String {
            switch self {
            case .totalTime: return "Total Time"
            case .intervals: return "Intervals"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Timer Type") {
                    Picker("Type", selection: $timerType) {
                        ForEach(TimerType.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                if timerType == .totalTime {
                    totalTimeSection
                }
                
                if timerType == .intervals {
                    intervalsSection
                }
                
                if timerType == .intervals {
                    repeatSection
                }
                
                if saveAsTemplate {
                    templateSection
                }
                
                Section {
                    Toggle("Save as template", isOn: $saveAsTemplate)
                }
            }
            
            // Standalone Load Configuration Button
            VStack(spacing: 16) {
                Divider()
                
                Button("Load") {
                    createTimer()
                }
                .buttonStyle(LoadConfigButtonStyle(color: isValidConfiguration ? .blue : .gray))
                .disabled(!isValidConfiguration)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
        }
        .onAppear {
            if intervals.isEmpty {
                intervals = [IntervalInput()]
            }
        }
    }
    
    // MARK: - Sections
    private var totalTimeSection: some View {
        Section("Total Time") {
            HStack {
                Picker("Minutes", selection: $totalTimeMinutes) {
                    ForEach(0...120, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .frame(maxWidth: .infinity)
                
                Picker("Seconds", selection: $totalTimeSeconds) {
                    ForEach(0...59, id: \.self) { seconds in
                        Text("\(seconds) sec").tag(seconds)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var intervalsSection: some View {
        Section("Intervals") {
            ForEach(Array(intervals.enumerated()), id: \.element.id) { index, item in
                IntervalInputRow(
                    interval: $intervals[index],
                    onDelete: {
                        intervals.removeAll { $0.id == item.id }
                    }
                )
            }

            Button("Add Interval") {
                intervals.append(IntervalInput())
            }
        }
    }
    
    private var repeatSection: some View {
        Section("Repeat") {
            Toggle("Repeat sets", isOn: $isRepeating)
            
            if isRepeating {
                Stepper("Repeat \(repeatCount) times", value: $repeatCount, in: 1...20)
                
                // Add rest between iterations setting
                Section("Rest Between Sets") {
                    HStack {
                        Picker("Minutes", selection: $restBetweenIterationsMinutes) {
                            ForEach(0...10, id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        
                        Picker("Seconds", selection: $restBetweenIterationsSeconds) {
                            ForEach(0...59, id: \.self) { seconds in
                                Text("\(seconds) sec").tag(seconds)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
    
    private var templateSection: some View {
        Section("Template Details") {
            TextField("Template name", text: $templateName)
            TextField("Description (optional)", text: $templateDescription, axis: .vertical)
                .lineLimit(2...4)
        }
    }
    
    // MARK: - Helper Properties
    private var isValidConfiguration: Bool {
        let hasTotalTime = (timerType == .totalTime) &&
                          (totalTimeMinutes > 0 || totalTimeSeconds > 0)
        
        let hasValidIntervals = (timerType == .intervals) &&
                               intervals.allSatisfy { $0.isValid }
        
        return hasTotalTime || hasValidIntervals
    }
    
    // MARK: - Actions
    private func createTimer() {
        let totalTime: Int? = (timerType == .totalTime) ?
                             (totalTimeMinutes * 60 + totalTimeSeconds) : nil
        
        let intervalConfigs: [IntervalConfiguration] = (timerType == .intervals) ?
            intervals.compactMap { $0.toConfiguration() } : []
        
        let restBetweenTotal = restBetweenIterationsMinutes * 60 + restBetweenIterationsSeconds
        let restBetween: Int? = (isRepeating && restBetweenTotal > 0) ? restBetweenTotal : nil
        
        let configuration = TimerConfiguration(
            totalTimeSeconds: totalTime,
            intervals: intervalConfigs,
            isRepeating: isRepeating,
            repeatCount: isRepeating ? repeatCount : nil,
            restTimeBetweenIntervals: restBetween
        )
        
        // Save as template if requested
        if saveAsTemplate && !templateName.isEmpty {
            saveAsTemplate(config: configuration)
        }
        
        onConfigurationReady(configuration)
    }
    
    private func saveAsTemplate(config: TimerConfiguration) {
        let template = TimerTemplate(
            name: templateName,
            templateDescription: templateDescription.isEmpty ? nil : templateDescription,
            totalTimeSeconds: config.totalTimeSeconds,
            isRepeating: config.isRepeating,
            repeatCount: config.repeatCount,
            restTimeBetweenIntervals: config.restTimeBetweenIntervals
        )
        
        // Add intervals properly with context access
        for (index, intervalConfig) in config.intervals.enumerated() {
            let interval = TimerInterval(
                name: intervalConfig.name,
                workTimeSeconds: intervalConfig.workTimeSeconds,
                restTimeSeconds: intervalConfig.restTimeSeconds,
                repetitions: intervalConfig.repetitions,
                order: index
            )
            template.intervals.append(interval)
            context.insert(interval)
        }
        
        context.insert(template)
        try? context.save()
    }
}

// MARK: - Progress Card View
struct ProgressCard: View {
    let title: String
    let current: Int
    let total: Int
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.title2)
                
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(current) / \(total)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
                let safeTotal = max(1, total)
                let safeCurrent = min(max(0, current), safeTotal)
                ProgressView(value: Double(safeCurrent), total: Double(safeTotal))
                .progressViewStyle(LinearProgressViewStyle(tint: color))
                .scaleEffect(y: 1.5)
        }
        .padding(16)
        .frame(width: 160, height: 80) // Fixed size for consistent appearance
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
}
