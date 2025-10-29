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
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    // Use ObservedObject to observe the existing shared instance
    @ObservedObject private var sharedTimerManager = SharedTimerManager.shared
    
    @State private var showingTemplateSelector = false
    @State private var showingCustomTimer = false
    @State private var showingAllTemplates = false
    @State private var showingTimerSetup = false
    
    let planDay: PlanDay?
    
    // Computed property to access the timer manager
    private var timerManager: TimerManager {
        sharedTimerManager.timerManager
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Timer Display
                timerDisplaySection
                
                // Progress Indicators
                if timerManager.configuration != nil {
                    progressSection
                }
                
                // Control Buttons (without Stop & Reset)
                controlButtonsSection
                
                // Laps Section - only show for total time timers, not interval timers
                if !timerManager.laps.isEmpty && timerManager.configuration?.hasIntervals == false {
                    lapsSection
                }
                
                Spacer()
            }
            //.navigationTitle("TIMER")
            .navigationBarTitleDisplayMode(.large)
            .padding(.horizontal, 20)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                   
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        // Main menu
                        Menu {
                            Section("Timer Setup") {
                                Button("Select Template", systemImage: "bolt.fill") {
                                    showingTemplateSelector = true
                                }
                                Button("Custom Timer", systemImage: "gearshape.fill") {
                                    showingCustomTimer = true
                                }
                            }
                            
                            Section("Template Management") {
                                Button("All Templates", systemImage: "folder") {
                                    showingAllTemplates = true
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingTemplateSelector) {
                TimerTemplateSelector { template in
                    loadTemplate(template)
                }
            }
            .sheet(isPresented: $showingAllTemplates) {
                TimerTemplatesListView()
            }
            .sheet(isPresented: $showingCustomTimer) {
                CustomTimerSetupWithContext { config in
                    startTimer(with: config)
                }
            }
            .sheet(isPresented: $showingTimerSetup) {
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
        .onAppear {
            // Keep screen on when timer view appears
            updateScreenIdleTimer()
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
                            .foregroundColor(.blue)
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
                            .foregroundColor(getPhaseColor())
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
            
            // Secondary information: total elapsed and remaining time (smaller, less prominent)
            HStack(spacing: 20) {
                // Total elapsed time
                VStack(spacing: 2) {
                    Text("Elapsed")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                    Text(timerManager.formatTime(timerManager.totalElapsedTime))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
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
                            .foregroundColor(.secondary)
                        Text(timerManager.formatTime(remaining))
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                            .contentTransition(.numericText())
                    }
                    .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Progress Section
    private var progressSection: some View {
        VStack(spacing: 16) {
            // Overall Progress with enhanced design
            VStack(spacing: 8) {
                HStack {
                    Text("Overall Progress")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(timerManager.progressPercentage * 100))%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
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
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
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
        .cornerRadius(12)
    }
    
    // MARK: - Control Buttons Section
    private var controlButtonsSection: some View {
        VStack(spacing: 16) {
            // Primary control button
            if timerManager.isStopped {
                Button("Start") {
                    if timerManager.configuration == nil {
                        showingTimerSetup = true
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
                                showingTimerSetup = true
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
            showingCustomTimer = true
            return
        }
        
        let session = TimerSession(planDayId: planDay?.id)
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
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
            planDayId: planDay?.id
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
        let session = TimerSession(planDayId: planDay?.id)
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
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .leading)
            
            Text(formatTime(lap.elapsedSeconds))
                .font(.caption.monospaced())
            
            Spacer()
            
            if let notes = lap.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Text(lap.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Button Styles
struct PrimaryTimerButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.weight(.semibold))
            .foregroundColor(.white)
            .frame(width: 120, height: 50)
            .background(color)
            .cornerRadius(25)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryTimerButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundColor(color)
            .frame(width: 80, height: 36)
            .background(color.opacity(0.1))
            .cornerRadius(18)
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
            .foregroundColor(.white)
            .frame(height: 60)
            .background(color)
            .cornerRadius(30)
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
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(color)
            .cornerRadius(25)
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
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(color)
            .cornerRadius(25)
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
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(color)
            .cornerRadius(22)
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
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if template.useCount > 0 {
                        Text("Used \(template.useCount) times")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let description = template.templateDescription {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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
                .foregroundColor(.secondary)
                
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
            ForEach(intervals.indices, id: \.self) { index in
                IntervalInputRow(
                    interval: $intervals[index],
                    onDelete: {
                        intervals.remove(at: index)
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
                    .foregroundColor(color)
                    .font(.title2)
                
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(current) / \(total)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
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

