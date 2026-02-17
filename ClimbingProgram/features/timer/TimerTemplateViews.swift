//
//  TimerTemplateViews.swift
//  Klettrack
//  Created by Shahar Noy on 25.08.25.
//

import SwiftUI
import SwiftData

// MARK: - Timer Template Selector
struct TimerTemplateSelector: View {
    private enum SheetRoute: String, Identifiable {
        case newTemplate
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(
        filter: #Predicate<TimerTemplate> { !$0.isSoftDeleted },
        sort: [SortDescriptor(\TimerTemplate.lastUsedDate, order: .reverse)]
    ) private var templates: [TimerTemplate]
    
    let onTemplateSelected: (TimerTemplate) -> Void
    
    @State private var sheetRoute: SheetRoute?
    @State private var editingTemplate: TimerTemplate? = nil
    
    var body: some View {
        NavigationStack {
            List {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "No Timer Templates",
                        systemImage: "timer",
                        description: Text("Create your first timer template to get started")
                    )
                } else {
                    ForEach(templates) { template in
                        TimerTemplateRow(template: template) {
                            onTemplateSelected(template)
                            dismiss()
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(template)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                editingTemplate = template
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Timer Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New") {
                        sheetRoute = .newTemplate
                    }
                }
            }
            .sheet(item: $sheetRoute) { route in
                switch route {
                case .newTemplate:
                    TimerTemplateEditor()
                }
            }
            .sheet(item: $editingTemplate) { template in
                TimerTemplateEditor(existingTemplate: template)
            }

        }
    }
    
    private func delete(_ template: TimerTemplate) {
        SyncLocalMutation.softDelete(template)
        try? context.save()
    }
}

// MARK: - Timer Template Row
struct TimerTemplateRow: View {
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
                    // number of reps in a set
                    if !template.intervals.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "repeat")
                            Text("\(template.intervals.first?.repetitions ?? 0)")
                        }
                    }
                    //rest time
                    if let restBetween = template.restTimeBetweenIntervals, restBetween > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "pause.circle")
                            Text(formatTime(restBetween))
                        }
                    }
                    // total time
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

// MARK: - Custom Timer Setup
struct CustomTimerSetup: View {
    @Environment(\.dismiss) private var dismiss
    
    let onConfigurationReady: (TimerConfiguration) -> Void
    
    @State private var timerType: TimerType = .totalTime
    @State private var totalTimeMinutes = 3
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
        
        var title: String {
            switch self {
            case .totalTime: return "Total Time"
            case .intervals: return "Intervals"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Timer Type") {
                    Picker("Type", selection: $timerType) {
                        ForEach(TimerType.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                if timerType == .totalTime  {
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
            .navigationTitle("Custom Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Start") {
                        createTimer()
                    }
                    .disabled(!isValidConfiguration)
                }
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
        let hasTotalTime = (timerType == .totalTime ) &&
                          (totalTimeMinutes > 0 || totalTimeSeconds > 0)
        
        let hasValidIntervals = (timerType == .intervals ) &&
                               intervals.allSatisfy { $0.isValid }
        
        return hasTotalTime || hasValidIntervals
    }
    
    // MARK: - Actions
    private func createTimer() {
        let totalTime: Int? = (timerType == .totalTime ) ?
                             (totalTimeMinutes * 60 + totalTimeSeconds) : nil
        
        let intervalConfigs: [IntervalConfiguration] = (timerType == .intervals ) ?
            intervals.compactMap { $0.toConfiguration() } : []
        
        let configuration = TimerConfiguration(
            totalTimeSeconds: totalTime,
            intervals: intervalConfigs,
            isRepeating: isRepeating,
            repeatCount: isRepeating ? repeatCount : nil,
            restTimeBetweenIntervals: nil
        )
        
        // Fix: Save as template if requested with proper context access
        if saveAsTemplate && !templateName.isEmpty {
            saveAsTemplateAction(config: configuration)
        }
        
        onConfigurationReady(configuration)
        dismiss()
    }
    
    private func saveAsTemplateAction(config: TimerConfiguration) {
        // Create the template and save it properly
        let template = TimerTemplate(
            name: templateName,
            templateDescription: templateDescription.isEmpty ? nil : templateDescription,
            totalTimeSeconds: config.totalTimeSeconds,
            isRepeating: config.isRepeating,
            repeatCount: config.repeatCount
        )
        
        // Add intervals properly
        for (index, intervalConfig) in config.intervals.enumerated() {
            let interval = TimerInterval(
                name: intervalConfig.name,
                workTimeSeconds: intervalConfig.workTimeSeconds,
                restTimeSeconds: intervalConfig.restTimeSeconds,
                repetitions: intervalConfig.repetitions,
                order: index
            )
            template.intervals.append(interval)
        }
        
        // Insert into context and save
        // Note: This requires ModelContext access which needs to be passed in
        // For now, we'll handle this in the CustomTimerSetup view
    }
}

// MARK: - Custom Timer Setup with Context
struct CustomTimerSetupWithContext: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    let onConfigurationReady: (TimerConfiguration) -> Void
    
    @State private var timerType: TimerType = .totalTime
    @State private var totalTimeMinutes = 3
    @State private var totalTimeSeconds = 0
    @State private var intervals: [IntervalInput] = []
    @State private var isRepeating = false
    @State private var repeatCount = 1
    @State private var saveAsTemplate = false
    @State private var templateName = ""
    @State private var templateDescription = ""
    @State private var restBetweenIntervalsMinutes = 0
    @State private var restBetweenIntervalsSeconds = 0
    
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
        NavigationStack {
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
                    restBetweenIntervalsSection
                }
                
                if timerType == .intervals  {
                    repeatSection
                }
                
                if saveAsTemplate {
                    templateSection
                }
                
                Section {
                    Toggle("Save as template", isOn: $saveAsTemplate)
                }
            }
            .navigationTitle("Custom Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Start") {
                        createTimer()
                    }
                    .disabled(!isValidConfiguration)
                }
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
    
    private var restBetweenIntervalsSection: some View {
        Section("Rest Between Sets") {
            HStack {
                Picker("Minutes", selection: $restBetweenIntervalsMinutes) {
                    ForEach(0...10, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .frame(maxWidth: .infinity)
                
                Picker("Seconds", selection: $restBetweenIntervalsSeconds) {
                    ForEach(0...59, id: \.self) { seconds in
                        Text("\(seconds) sec").tag(seconds)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            
            Text("Time to rest when transitioning between different interval types")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var repeatSection: some View {
        Section("Repeat") {
            Toggle("Repeat sets", isOn: $isRepeating)
            
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
        let hasTotalTime = (timerType == .totalTime) &&
                          (totalTimeMinutes > 0 || totalTimeSeconds > 0)
        
        let hasValidIntervals = (timerType == .intervals) &&
                               intervals.allSatisfy { $0.isValid }
        
        return hasTotalTime || hasValidIntervals
    }
    
    // MARK: - Actions
    private func createTimer() {
        let totalTime: Int? = (timerType == .totalTime ) ?
                             (totalTimeMinutes * 60 + totalTimeSeconds) : nil
        
        let intervalConfigs: [IntervalConfiguration] = (timerType == .intervals ) ?
            intervals.compactMap { $0.toConfiguration() } : []
        
        let restBetween = restBetweenIntervalsMinutes * 60 + restBetweenIntervalsSeconds
        
        let configuration = TimerConfiguration(
            totalTimeSeconds: totalTime,
            intervals: intervalConfigs,
            isRepeating: isRepeating,
            repeatCount: isRepeating ? repeatCount : nil,
            restTimeBetweenIntervals: restBetween > 0 ? restBetween : nil
        )
        
        // Save as template with proper context access
        if saveAsTemplate && !templateName.isEmpty {
            saveAsTemplate(config: configuration)
        }
        
        onConfigurationReady(configuration)
        dismiss()
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
            SyncLocalMutation.touch(interval)
        }
        
        context.insert(template)
        SyncLocalMutation.touch(template)
        try? context.save()
    }
}

// MARK: - Interval Input
struct IntervalInput: Identifiable {
    let id: UUID = .init()
    var workMinutes: Int = 0
    var workSeconds: Int = 0
    var restMinutes: Int = 0
    var restSeconds: Int = 0
    var repetitions: Int = 2
    
    var workTime: TimeInterval {
        TimeInterval(workMinutes * 60 + workSeconds)
    }
    
    var restTime: TimeInterval {
        TimeInterval(restMinutes * 60 + restSeconds)
    }
    
    var isValid: Bool {
        // Allow intervals with work time only, rest time only, or both
        // At least one must be greater than 0, and repetitions must be positive
        (workTime > 0 || restTime > 0) && repetitions > 0
    }
    
    func toConfiguration() -> IntervalConfiguration? {
        guard isValid else { return nil }
        
        return IntervalConfiguration(
            name: "Interval", // Default name since we don't need custom names
            workTimeSeconds: Int(workTime),
            restTimeSeconds: Int(restTime),
            repetitions: repetitions
        )
    }
}

// MARK: - Interval Input Row
struct IntervalInputRow: View {
    @Binding var interval: IntervalInput
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Interval")
                    .font(.headline)
                
                Spacer()
                
                Button("Delete", action: onDelete)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            VStack(spacing: 16) {
                // Work Time with native-style picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Work Time")
                        .font(.subheadline.weight(.medium))
                    
                    HStack {
                        Picker("Minutes", selection: $interval.workMinutes) {
                            ForEach(0...60, id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        
                        Picker("Seconds", selection: $interval.workSeconds) {
                            ForEach(0...59, id: \.self) { seconds in
                                Text("\(seconds) sec").tag(seconds)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 100)
                }
                
                // Rest Time with native-style picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rest Time")
                        .font(.subheadline.weight(.medium))
                    
                    HStack {
                        Picker("Minutes", selection: $interval.restMinutes) {
                            ForEach(0...30, id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        
                        Picker("Seconds", selection: $interval.restSeconds) {
                            ForEach(0...59, id: \.self) { seconds in
                                Text("\(seconds) sec").tag(seconds)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 100)
                }
                
                // Repetitions
                VStack(alignment: .leading, spacing: 4) {
                    Text("Repetitions: \(interval.repetitions)")
                        .font(.subheadline.weight(.medium))
                    
                    Stepper("", value: $interval.repetitions, in: 1...50)
                        .labelsHidden()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(.rect(cornerRadius: 8))
    }
}

// MARK: - Timer Template Editor
struct TimerTemplateEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    let existingTemplate: TimerTemplate?
    
    @State private var templateName = ""
    @State private var templateDescription = ""
    @State private var timerType: TimerType = .intervals
    @State private var totalTimeMinutes = 3
    @State private var totalTimeSeconds = 0
    @State private var intervals: [IntervalInput] = []
    @State private var isRepeating = false
    @State private var repeatCount = 1
    @State private var restBetweenIntervalsMinutes = 0
    @State private var restBetweenIntervalsSeconds = 0
    @State private var showingDeleteConfirmation = false
    
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
    
    init(existingTemplate: TimerTemplate? = nil) {
        self.existingTemplate = existingTemplate
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Template Info") {
                    TextField("Template name", text: $templateName)
                    TextField("Description (optional)", text: $templateDescription, axis: .vertical)
                        .lineLimit(2...4)
                }
                
                Section("Timer Type") {
                    Picker("Type", selection: $timerType) {
                        ForEach(TimerType.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                if timerType == .totalTime  {
                    totalTimeSection
                }
                
                if timerType == .intervals {
                    intervalsSection
                    restBetweenIntervalsSection
                }
                
                if timerType == .intervals  {
                    repeatSection
                }
                
                if existingTemplate != nil {
                    Section {
                        Button("Delete Template") {
                            showingDeleteConfirmation = true
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existingTemplate == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveTemplate()
                    }
                    .disabled(!isValidTemplate)
                }
            }
            .confirmationDialog("Delete Template", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteTemplate()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete this template? This action cannot be undone.")
            }
        }
        .onAppear {
            setupInitialValues()
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
    
    private var restBetweenIntervalsSection: some View {
        Section("Rest Between Sets") {
            HStack {
                Picker("Minutes", selection: $restBetweenIntervalsMinutes) {
                    ForEach(0...10, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .frame(maxWidth: .infinity)
                
                Picker("Seconds", selection: $restBetweenIntervalsSeconds) {
                    ForEach(0...59, id: \.self) { seconds in
                        Text("\(seconds) sec").tag(seconds)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            
            Text("Time to rest when transitioning between different interval types")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var repeatSection: some View {
        Section("Repeat") {
            Toggle("Repeat sets", isOn: $isRepeating)
            
            if isRepeating {
                Stepper("Repeat \(repeatCount) times", value: $repeatCount, in: 1...20)
            }
        }
    }
    
    // MARK: - Helper Properties
    private var isValidTemplate: Bool {
        guard !templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        
        let hasTotalTime = (timerType == .totalTime ) &&
                          (totalTimeMinutes > 0 || totalTimeSeconds > 0)
        
        let hasValidIntervals = (timerType == .intervals) &&
                               !intervals.isEmpty && intervals.allSatisfy { $0.isValid }
        
        return hasTotalTime || hasValidIntervals
    }
    
    private var totalRestBetweenIntervals: Int {
        restBetweenIntervalsMinutes * 60 + restBetweenIntervalsSeconds
    }
    
    // MARK: - Actions
    private func setupInitialValues() {
        if let template = existingTemplate {
            templateName = template.name
            templateDescription = template.templateDescription ?? ""
            
            // Determine timer type
            let hasTotal = template.totalTimeSeconds != nil
            
            if hasTotal {
                timerType = .totalTime
            } else {
                timerType = .intervals
            }
            
            // Set total time
            if let totalTime = template.totalTimeSeconds {
                totalTimeMinutes = totalTime / 60
                self.totalTimeSeconds = totalTime % 60
            }
            
            // Set intervals
            intervals = template.intervals
                .sorted { $0.order < $1.order }
                .map { interval in
                    var input = IntervalInput()
                    input.workMinutes = interval.workTimeSeconds / 60
                    input.workSeconds = interval.workTimeSeconds % 60
                    input.restMinutes = interval.restTimeSeconds / 60
                    input.restSeconds = interval.restTimeSeconds % 60
                    input.repetitions = interval.repetitions
                    return input
                }
            
            // Set repeat settings
            isRepeating = template.isRepeating
            repeatCount = template.repeatCount ?? 1
            
            // Set rest between intervals
            if let restBetween = template.restTimeBetweenIntervals {
                restBetweenIntervalsMinutes = restBetween / 60
                self.restBetweenIntervalsSeconds = restBetween % 60
            }
        } else {
            // Default values for new template
            if intervals.isEmpty {
                intervals = [IntervalInput()]
            }
        }
    }
    
    private func saveTemplate() {
        let template = existingTemplate ?? TimerTemplate(
            name: templateName,
            templateDescription: templateDescription.isEmpty ? nil : templateDescription
        )
        
        // Update template properties
        template.name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        template.templateDescription = templateDescription.isEmpty ? nil : templateDescription
        SyncLocalMutation.touch(template)
        
        // Set total time
        if timerType == .totalTime {
            template.totalTimeSeconds = totalTimeMinutes * 60 + totalTimeSeconds
        } else {
            template.totalTimeSeconds = nil
        }
        
        // Set repeat settings
        template.isRepeating = isRepeating
        template.repeatCount = isRepeating ? repeatCount : nil
        
        // Set rest between intervals
        let restBetween = restBetweenIntervalsMinutes * 60 + restBetweenIntervalsSeconds
        template.restTimeBetweenIntervals = restBetween > 0 ? restBetween : nil
        
        // Handle intervals
        if timerType == .intervals {
            // Remove existing intervals if editing
            if existingTemplate != nil {
                for interval in template.intervals {
                    SyncLocalMutation.softDelete(interval)
                }
                template.intervals.removeAll()
            }
            
            // Add new intervals
            for (index, intervalInput) in intervals.enumerated() {
                guard intervalInput.isValid else { continue }
                
                let interval = TimerInterval(
                    name: "Interval \(index + 1)",
                    workTimeSeconds: intervalInput.workMinutes * 60 + intervalInput.workSeconds,
                    restTimeSeconds: intervalInput.restMinutes * 60 + intervalInput.restSeconds,
                    repetitions: intervalInput.repetitions,
                    order: index
                )
                SyncLocalMutation.touch(interval)
                
                template.intervals.append(interval)
                context.insert(interval)
            }
        } else {
            // Clear intervals if not using interval type
            if existingTemplate != nil {
                for interval in template.intervals {
                    SyncLocalMutation.softDelete(interval)
                }
                template.intervals.removeAll()
            }
        }
        
        // Insert template if new
        if existingTemplate == nil {
            context.insert(template)
            SyncLocalMutation.touch(template)
        }
        
        try? context.save()
        dismiss()
    }
    
    private func deleteTemplate() {
        guard let template = existingTemplate else { return }
        SyncLocalMutation.softDelete(template)
        try? context.save()
        dismiss()
    }
}
