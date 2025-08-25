//
//  TimerViews.swift
//  ClimbingProgram
//
//  Created by AI Assistant on 25.08.25.
//

import SwiftUI
import SwiftData

// MARK: - Main Timer View
struct TimerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var timerManager = TimerManager()
    @State private var showingTemplateSelector = false
    @State private var showingCustomTimer = false
    @State private var showingAllTemplates = false
    @State private var showingTimerSetup = false
    
    let planDay: PlanDay?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Timer Display
                timerDisplaySection
                
                // Progress Indicators
                if timerManager.configuration != nil {
                    progressSection
                }
                
                // Current Interval Info
                if let config = timerManager.currentIntervalConfig {
                    currentIntervalSection(config)
                }
                
                // Control Buttons (without Stop & Reset)
                controlButtonsSection
                
                // Laps Section
                if !timerManager.laps.isEmpty {
                    lapsSection
                }
                
                Spacer()
                
                // Stop & Reset button at the bottom
                if !timerManager.isStopped {
                    Button("Stop & Reset") {
                        timerManager.stop()
                    }
                    .buttonStyle(FullWidthTimerButtonStyle(color: .red))
                    .padding(.bottom)
                }
            }
            .padding()
            .navigationTitle("Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Load Template") {
                            showingTemplateSelector = true
                        }
                        Button("All Templates") {
                            showingAllTemplates = true
                        }
                        Button("Custom Timer") {
                            showingCustomTimer = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
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
    }
    
    // MARK: - Timer Display Section
    private var timerDisplaySection: some View {
        VStack(spacing: 10) {
            // Main time display
            Text(timerManager.formatTime(timerManager.totalElapsedTime))
                .font(.system(size: 60, weight: .light, design: .monospaced))
                .foregroundColor(timerManager.isRunning ? .primary : .secondary)
            
            // Time remaining (if applicable)
            let remaining = timerManager.totalTimeRemaining
            if remaining > 0 {
                Text("Remaining: \(timerManager.formatTime(remaining))")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            
            // Current phase indicator
            if timerManager.configuration?.hasIntervals == true {
                HStack {
                    Circle()
                        .fill(getPhaseColor())
                        .frame(width: 12, height: 12)
                    Text(getPhaseText())
                        .font(.headline)
                    
                    if timerManager.currentPhaseTimeRemaining > 0 {
                        Text("(\(timerManager.formatTime(timerManager.currentPhaseTimeRemaining)))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    // MARK: - Progress Section
    private var progressSection: some View {
        VStack(spacing: 12) {
            // Overall Progress
            ProgressView(value: timerManager.progressPercentage)
                .progressViewStyle(.linear)
                .tint(.blue)
            
            Text("\(Int(timerManager.progressPercentage * 100))% Complete")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Interval Progress (if applicable) - Bug Fix 4: Make interval counts bigger
            if let config = timerManager.configuration, config.hasIntervals {
                VStack(spacing: 8) {
                    Text("Interval \(timerManager.currentInterval + 1) of \(config.intervals.count)")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.primary)
                    
                    Text("Rep \(timerManager.currentRepetition + 1) of \(timerManager.currentInterval < config.intervals.count ? config.intervals[timerManager.currentInterval].repetitions : 0)")
                        .font(.title3.weight(.medium))
                        .foregroundColor(.blue)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Current Interval Section
    private func currentIntervalSection(_ config: IntervalConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current: \(config.name)")
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Work: \(timerManager.formatTime(config.workTimeSeconds))")
                    Text("Rest: \(timerManager.formatTime(config.restTimeSeconds))")
                }
                .font(.subheadline)
                
                Spacer()
                
                Text("\(config.repetitions) reps")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
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
            } else if timerManager.isRunning {
                // Enhanced: Wider buttons with equal distribution
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        Button("Pause") {
                            timerManager.pause()
                        }
                        .buttonStyle(WideTimerButtonStyle(color: .orange))
                        
                        Button("Lap") {
                            timerManager.addLap()
                        }
                        .buttonStyle(WideTimerButtonStyle(color: .blue))
                    }
                }
            } else if timerManager.isPaused {
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        Button("Resume") {
                            timerManager.resume()
                        }
                        .buttonStyle(WideTimerButtonStyle(color: .green))
                        
                        Button("Lap") {
                            timerManager.addLap()
                        }
                        .buttonStyle(WideTimerButtonStyle(color: .blue))
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
        if timerManager.isInBetweenIntervalRest {
            return .purple // Distinct color for rest between intervals
        } else {
            return timerManager.currentPhase == .work ? .green : .orange
        }
    }
    
    private func getPhaseText() -> String {
        if timerManager.isInBetweenIntervalRest {
            return "Rest Between Intervals"
        } else {
            return timerManager.currentPhase == .work ? "Work" : "Rest"
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
                            restTimeBetweenIntervals: nil
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
                
                HStack {
                    if let totalTime = template.totalTimeSeconds {
                        Label(formatTime(totalTime), systemImage: "clock")
                    }
                    
                    if !template.intervals.isEmpty {
                        Label("\(template.intervals.count) intervals", systemImage: "repeat")
                    }
                    
                    if template.isRepeating {
                        Label("Repeats \(template.repeatCount ?? 1)x", systemImage: "arrow.clockwise")
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
    @State private var totalTimeMinutes = 10
    @State private var totalTimeSeconds = 0
    @State private var intervals: [IntervalInput] = []
    @State private var isRepeating = false
    @State private var repeatCount = 1
    @State private var saveAsTemplate = false
    @State private var templateName = ""
    @State private var templateDescription = ""
    
    private enum TimerType: CaseIterable {
        case totalTime
        case intervals
        case both
        
        var title: String {
            switch self {
            case .totalTime: return "Total Time"
            case .intervals: return "Intervals"
            case .both: return "Both"
            }
        }
    }
    
    var body: some View {
        Form {
            Section("Timer Type") {
                Picker("Type", selection: $timerType) {
                    ForEach(TimerType.allCases, id: \.self) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            if timerType == .totalTime || timerType == .both {
                totalTimeSection
            }
            
            if timerType == .intervals || timerType == .both {
                intervalsSection
            }
            
            if timerType == .intervals || timerType == .both {
                repeatSection
            }
            
            if saveAsTemplate {
                templateSection
            }
            
            Section {
                Toggle("Save as template", isOn: $saveAsTemplate)
                
                Button("Load Configuration") {
                    createTimer()
                }
                .disabled(!isValidConfiguration)
            }
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
            Toggle("Repeat intervals", isOn: $isRepeating)
            
            if isRepeating {
                Stepper("Repeat \(repeatCount) times", value: $repeatCount, in: 1...20)
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
        let hasTotalTime = (timerType == .totalTime || timerType == .both) &&
                          (totalTimeMinutes > 0 || totalTimeSeconds > 0)
        
        let hasValidIntervals = (timerType == .intervals || timerType == .both) &&
                               intervals.allSatisfy { $0.isValid }
        
        return hasTotalTime || hasValidIntervals
    }
    
    // MARK: - Actions
    private func createTimer() {
        let totalTime: Int? = (timerType == .totalTime || timerType == .both) ?
                             (totalTimeMinutes * 60 + totalTimeSeconds) : nil
        
        let intervalConfigs: [IntervalConfiguration] = (timerType == .intervals || timerType == .both) ?
            intervals.compactMap { $0.toConfiguration() } : []
        
        let configuration = TimerConfiguration(
            totalTimeSeconds: totalTime,
            intervals: intervalConfigs,
            isRepeating: isRepeating,
            repeatCount: isRepeating ? repeatCount : nil,
            restTimeBetweenIntervals: nil
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
            repeatCount: config.repeatCount
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
