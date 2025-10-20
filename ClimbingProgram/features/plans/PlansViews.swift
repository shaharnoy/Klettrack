//
//  PlansViews.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

import UIKit

struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

// Shared exercise hit type for catalog search results (file-scope, internal)
struct ExerciseHit: Identifiable {
    let id: UUID
    let name: String
    let subtitle: String?
    let tint: Color

    init(ex: Exercise, tint: Color) {
        self.id = ex.id
        self.name = ex.name
        self.subtitle = ex.exerciseDescription?.isEmpty == false ? ex.exerciseDescription : ex.notes
        self.tint = tint
    }
}

// Date formatting helpers
private extension Date {
    var shortFormat: String {
        formatted(date: .abbreviated, time: .omitted)
    }
    
    var monthYearFormat: String {
        formatted(.dateTime.year().month())
    }
    
    var dayMonthFormat: String {
        formatted(.dateTime.weekday(.abbreviated).month().day())
    }
}

// MARK: Plans list
struct PlansListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.isDataReady) private var isDataReady
    @EnvironmentObject private var timerAppState: TimerAppState
    // Be explicit with SortDescriptor to help the type checker
    @Query(sort: [SortDescriptor<Plan>(\Plan.startDate, order: .reverse)]) private var plans: [Plan]

    @State private var showingNew = false

    // Export / Import / Share state
    @State private var showExporter = false
    @State private var exportDoc: LogCSVDocument? = nil

    @State private var showImporter = false
    @State private var importResultMessage: String? = nil
    @State private var sharePayload: SharePayload? = nil


    var body: some View {
        NavigationStack {
            List {
                ForEach(plans) { plan in
                    Button {
                        // Use programmatic navigation with Hashable wrapper
                        timerAppState.plansNavigationPath.append(PlanNavigationItem(plan: plan))
                    } label: {
                        PlanRow(plan: plan)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { idx in
                    guard isDataReady else { return }
                    idx.map { plans[$0] }.forEach(context.delete)
                    try? context.save()
                }
            }
            .listStyle(.insetGrouped)
            .navigationDestination(for: PlanNavigationItem.self) { planItem in
                // Find the plan by ID and pass it to PlanDetailView
                if let plan = plans.first(where: { $0.id == planItem.planId }) {
                    PlanDetailView(plan: plan)
                        .environmentObject(timerAppState)
                } else {
                    Text("Plan not found")
                }
            }
            .navigationDestination(for: PlanDayNavigationItem.self) { dayItem in
                // Find the plan day by ID across all plans
                let allDays = plans.flatMap { $0.days }
                if let day = allDays.first(where: { $0.id == dayItem.planDayId }) {
                    PlanDayEditor(day: day)
                        .environmentObject(timerAppState)
                } else {
                    Text("Plan day not found")
                }
            }
            .navigationTitle("TRAIN")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                // Overflow menu: export / share / import
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Export (save to Files)
                        Button {
                            guard isDataReady else { return }
                            exportDoc = LogCSV.makeExportCSV(context: context)
                            showExporter = true
                        } label: {
                            Label("Export logs to CSV", systemImage: "square.and.arrow.up")
                        }

                        // Share (Mail / Messages / Files…)
                        Button {
                            guard isDataReady else { return }
                            let doc = LogCSV.makeExportCSV(context: context)
                            let fn = "klettrack-log-\(Date().formatted(.dateTime.year().month().day())).csv"
                            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fn)

                            do {
                                try doc.csv.write(to: url, atomically: true, encoding: .utf8)
                                guard FileManager.default.fileExists(atPath: url.path) else {
                                    importResultMessage = "Share failed: file not found."
                                    return
                                }
                                // triggers the share sheet
                                sharePayload = SharePayload(url: url)
                            } catch {
                                importResultMessage = "Share prep failed: \(error.localizedDescription)"
                            }
                        } label: {
                            Label("Share logs (CSV)…", systemImage: "square.and.arrow.up.on.square")
                        }

                        // Import (from Files / cloud storage)
                        Button {
                            guard isDataReady else { return }
                            showImporter = true
                        } label: {
                            Label("Import logs from CSV", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(!isDataReady)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard isDataReady else { return }
                        showingNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!isDataReady)
                }
            }
            .sheet(isPresented: $showingNew) { NewPlanSheet() }
            // Exporter
            .fileExporter(isPresented: $showExporter,
                          document: exportDoc,
                          contentType: .commaSeparatedText,
                          defaultFilename: "klettrack-log-\(Date().formatted(.dateTime.year().month().day()))") { result in
                switch result {
                case .success:
                    importResultMessage = "CSV exported."
                case .failure(let err):
                    importResultMessage = "Export failed: \(err.localizedDescription)"
                }
            }
            // Importer
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.commaSeparatedText],
                          allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let df = ISO8601DateFormatter(); df.formatOptions = [.withFullDate]
                    let tag = "import:\(df.string(from: Date()))"
                    let inserted = try LogCSV.importCSV(from: url, into: context, tag: tag, dedupe: true)
                    importResultMessage = "Imported\(inserted) log item(s)."
                } catch {
                    importResultMessage = "Import failed: \(error.localizedDescription)"
                }
            }
            // Share
              .sheet(item: $sharePayload) { payload in
                  ShareSheet(items: [payload.url]) {
                      try? FileManager.default.removeItem(at: payload.url)
                  }
                  .presentationDetents([.medium])
              }
            // Result alert
            .alert(importResultMessage ?? "", isPresented: Binding(
                get: { importResultMessage != nil },
                set: { if !$0 { importResultMessage = nil } }
            )) { Button("OK", role: .cancel) {} }
        }
    }
}

// Small, explicit row view reduces type inference work
private struct PlanRow: View {
    let plan: Plan

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        "\(plan.kind?.name ?? "Custom") • starts \(format(plan.startDate))"
    }

    private func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: New plan sheet
struct NewPlanSheet: View {
    enum CreationMode { case template, customDates }
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    // SwiftData: keep sort descriptors simple
    @Query(sort: [SortDescriptor(\PlanKindModel.order)]) private var kinds: [PlanKindModel]

    @State private var name = ""
    @State private var selectedKind: PlanKindModel? = nil
    @State private var start = Date()
    @State private var creationMode: CreationMode = .template
    @State private var end = Calendar.current.date(byAdding: .day, value: 27, to: Date()) ?? Date()
    
    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $creationMode) {
                    Text("Template").tag(CreationMode.template)
                    Text("Custom").tag(CreationMode.customDates)
                }
                .pickerStyle(.segmented)
                
                TextField("Plan name", text: $name)
                
                if creationMode == .template {
                    Picker("Template", selection: $selectedKind) {
                        ForEach(kinds) { k in
                            // Make tag type explicit to avoid inference bugs
                            Text(k.name).tag(k as PlanKindModel?)
                        }
                    }
                    DatePicker("Start date", selection: $start, displayedComponents: .date)
                } else {
                    DatePicker("Start date", selection: $start, displayedComponents: .date)
                    DatePicker("End date", selection: $end, in: start..., displayedComponents: .date)

                    if end < start {
                        Text("End date must be on or after start date.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let planName = finalName.isEmpty ? (selectedKind?.name ?? "Plan") : finalName
                        switch creationMode {
                        case .template:
                            guard let kind = selectedKind else { return }
                            _ = PlanFactory.create(name: planName, kind: kind, start: start, in: context)
                            dismiss()
                        case .customDates:
                            guard end >= start else { return }
                            createPlanFromDates(context: context, name: planName, start: start, end: end)
                            dismiss()
                        }
                    }
                    .disabled((creationMode == .template && selectedKind == nil) ||
                              (creationMode == .customDates && end < start))
                }
            }
        }
    }

    private func createPlanFromDates(context: ModelContext, name: String, start: Date, end: Date) {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: start)
        let endDay = cal.startOfDay(for: end)

        let plan = Plan(name: name, kind:nil, startDate: startDay)
        context.insert(plan)

        var d = startDay
        while d <= endDay {
            let day = PlanDay(date: d)
            plan.days.append(day)
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d.addingTimeInterval(86_400)
        }

        try? context.save()
    }
}


// MARK: Plan detail - weekly/monthly views

struct PlanDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var timerAppState: TimerAppState
    @State var plan: Plan

    private enum ViewMode: Int {
        case weekly = 0
        case monthly = 1
    }
    @State private var viewMode: ViewMode = .weekly
    
    @State private var showingDupPrompt = false
    @State private var weeksToAdd: String = ""

    private let cal = Calendar.current

    // Helper to check if a day is today
    private func isToday(_ date: Date) -> Bool {
        cal.isDate(date, inSameDayAs: Date())
    }
    
    // Helper to find the current day in the plan
    private var currentDayId: UUID? {
        plan.days.first { isToday($0.date) }?.id
    }

    // Query for all session items that belong to this plan
    private var planSessionItems: [SessionItem] {
        let descriptor = FetchDescriptor<SessionItem>(
            sortBy: [SortDescriptor(\.exerciseName)]
        )
        let allItems = (try? context.fetch(descriptor)) ?? []
        return allItems.filter { $0.planSourceId == plan.id }
    }

    // Break down complex computed property into smaller functions
    private func getWeekStart(for date: Date) -> Date {
        cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    private func groupDaysByWeek(_ days: [PlanDay]) -> [(weekStart: Date, days: [PlanDay])] {
        guard !days.isEmpty else { return [] }
        
        let sortedDays = days.sorted { $0.date < $1.date }
        var result: [(Date, [PlanDay])] = []
        var currentWeekStart = getWeekStart(for: sortedDays[0].date)
        var bucket: [PlanDay] = []
        
        for day in sortedDays {
            let weekStart = getWeekStart(for: day.date)
            if weekStart != currentWeekStart {
                result.append((currentWeekStart, bucket))
                currentWeekStart = weekStart
                bucket = [day]
            } else {
                bucket.append(day)
            }
        }
        
        if !bucket.isEmpty {
            result.append((currentWeekStart, bucket))
        }
        
        return result
    }

    private var groupedByWeek: [(weekStart: Date, days: [PlanDay])] {
        groupDaysByWeek(plan.days)
    }

    private func getMonthComponents(for date: Date) -> DateComponents {
        cal.dateComponents([.year, .month], from: date)
    }

    private func groupDaysByMonth(_ days: [PlanDay], calendar: Calendar) -> [(components: DateComponents, days: [PlanDay])] {
        // Group days by year and month
        let grouped = Dictionary(grouping: days) { getMonthComponents(for: $0.date) }
        
        // Convert to array and sort by date
        return grouped.map { ($0.key, $0.value.sorted { $0.date < $1.date }) }
            .sorted { pair1, pair2 in
                let date1 = calendar.date(from: pair1.components) ?? .distantPast
                let date2 = calendar.date(from: pair2.components) ?? .distantPast
                return date1 < date2
            }
    }
    
    // Helper: resolve a safe color for a plan day by refetching its day type
    private func dayTypeColor(for day: PlanDay) -> Color {
        guard let typeId = day.type?.id else { return .gray }
        let fetch = FetchDescriptor<DayTypeModel>(predicate: #Predicate { $0.id == typeId })
        if let fresh = (try? context.fetch(fetch))?.first {
            return fresh.color
        } else {
            return .gray
        }
    }
    
    // Break down toolbar into smaller components
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add more week") {
                        weeksToAdd = ""
                        showingDupPrompt = true
                    }
                } label: {
                    Label("Duplicate weeks", systemImage: "plus.square.on.square")
                }
            }
    }
    
    // Break down the main content into smaller views
    @ViewBuilder
    private var weeklyContent: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(groupedByWeek, id: \.weekStart) { group in
                    Section(header: Text("Week of \(group.weekStart.formatted(date: .abbreviated, time: .omitted))")) {
                        ForEach(group.days) { day in
                            Button {
                                // Use programmatic navigation with Hashable wrapper
                                timerAppState.plansNavigationPath.append(PlanDayNavigationItem(planDay: day))
                            } label: {
                                HStack {
                                    Circle().fill(dayTypeColor(for: day)).frame(width: 10, height: 10)
                                    Text(day.date, format: .dateTime.weekday(.abbreviated).month().day())
                                    Spacer()
                                    Text(day.type?.name ?? "Unknown").foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isToday(day.date) ? Color.yellow.opacity(0.1) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isToday(day.date) ? Color.black : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .id(day.id) // For ScrollViewReader
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .onAppear {
                // Scroll to current day when view appears
                if let currentId = currentDayId {
                    DispatchQueue.main.asyncAfter(deadline: .now()) {
                        proxy.scrollTo(currentId, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var monthlyContent: some View {
        ScrollView {
            let monthGroups = groupDaysByMonth(plan.days, calendar: cal)
            MonthlyGridView(groups: monthGroups, calendar: cal)
                .environmentObject(timerAppState)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // View mode switch
            Picker("View", selection: $viewMode) {
                Text("Weekly").tag(ViewMode.weekly)
                Text("Monthly").tag(ViewMode.monthly)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if viewMode == .weekly {
                weeklyContent
            } else {
                monthlyContent
            }
        }
        .navigationTitle(plan.name)
        .toolbar { toolbarContent }
        .alert("Add weeks", isPresented: $showingDupPrompt) {
            TextField("Number of weeks", text: $weeksToAdd)
                .keyboardType(.numberPad)
            Button("Add") {
                if let n = Int(weeksToAdd), n > 0 {
                    PlanFactory.appendWeeks(to: plan, count: n, in: context)
                    try? context.save()
                }
                weeksToAdd = ""
            }
            Button("Cancel", role: .cancel) { weeksToAdd = "" }
        } message: {
            Text("Enter how many weeks to add")
        }
    }
}

private struct ExerciseSelection: Identifiable, Equatable {
    let name: String
    var id: String { name }
}

// MARK: Day editor

struct PlanDayEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.isDataReady) private var isDataReady
    @Environment(\.editMode) private var editMode
    @EnvironmentObject private var timerAppState: TimerAppState
    @State private var didReorder = false
    @State var day: PlanDay
    
    @Query(
        filter: #Predicate<DayTypeModel> { $0.isHidden == false },
        sort: [SortDescriptor<DayTypeModel>(\DayTypeModel.order)]
    ) private var dayTypes: [DayTypeModel]

    // Catalog picker
    @State private var showingPicker = false

    // Quick Log
    @State private var loggingExercise: ExerciseSelection? = nil
    @State private var inputReps: String = ""
    @State private var inputSets: String = ""
    @State private var inputWeight: String = ""
    @State private var inputGrade: String = ""
    @State private var inputNotes: String = ""
    @State private var saveTick = false
    
    // Quick Progress
    @State private var progressExercise: ExerciseSelection? = nil
    
    // Climb logging for bouldering exercises
    @State private var showingClimbLog = false
    @State private var climbLoggingExercise: ExerciseSelection? = nil
    
    // State for daily notes to handle the optional binding
    @State private var dailyNotesText: String = ""
    
    // New: Picker selection by identifier (prevents invalidated object binding)
    @State private var selectedDayTypeId: UUID? = nil
    
    // Helper function to check if an exercise belongs to the Bouldering activity
    private func isBoulderingExercise(name: String) -> Bool {
        let activityDescriptor = FetchDescriptor<Activity>()
        let allActivities = (try? context.fetch(activityDescriptor)) ?? []
        
        // Find if this exercise belongs to an activity with "boulder" in the name
        for activity in allActivities {
            if activity.name.lowercased().contains("boulder") {
                for trainingType in activity.types {
                    // Check direct exercises
                    if trainingType.exercises.contains(where: { $0.name == name }) {
                        return true
                    }
                    // Check combination exercises
                    for combination in trainingType.combinations {
                        if combination.exercises.contains(where: { $0.name == name }) {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }
    
    // Query for logged exercises on this day that belong to this plan
    private var loggedExercisesForDay: [SessionItem] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day.date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        
        let sessionDescriptor = FetchDescriptor<Session>(predicate: #Predicate<Session> {
            $0.date >= dayStart && $0.date < dayEnd
        })
        let sessions = (try? context.fetch(sessionDescriptor)) ?? []
        
        // Find the plan that contains this day
        let planDescriptor = FetchDescriptor<Plan>()
        let plans = (try? context.fetch(planDescriptor)) ?? []
        let parentPlan = plans.first { plan in
            plan.days.contains { $0.id == day.id }
        }
        
        // Return session items for this day that belong to this plan
        return sessions.flatMap { session in
            session.items.filter { item in
                item.planSourceId == parentPlan?.id
            }
        }
    }
    
    // Helper to get exercises sorted by their catalog order
    private func sortedChosenExercises() -> [String] {
        // Get all exercises from the catalog
        let descriptor = FetchDescriptor<Exercise>()
        let allExercises = (try? context.fetch(descriptor)) ?? []
        
        // Create a map of exercise names to their order values, handling duplicates
        var exerciseOrderMap: [String: Int] = [:]
        for exercise in allExercises {
            // If we encounter a duplicate name, keep the lower order value
            if let existingOrder = exerciseOrderMap[exercise.name] {
                exerciseOrderMap[exercise.name] = min(existingOrder, exercise.order)
            } else {
                exerciseOrderMap[exercise.name] = exercise.order
            }
        }
        
        // Sort chosen exercises: not quick-logged first (by catalog order), then quick-logged at bottom
        return day.chosenExercises.sorted { name1, name2 in
            let isLogged1 = isExerciseQuickLogged(name: name1)
            let isLogged2 = isExerciseQuickLogged(name: name2)
            
            // If one is logged and the other isn't, put the unlogged one first
            if isLogged1 != isLogged2 {
                return !isLogged1 // not logged (false) comes before logged (true)
            }
            
            // If both have the same logged status, sort by catalog order
            let order1 = exerciseOrderMap[name1] ?? Int.max
            let order2 = exerciseOrderMap[name2] ?? Int.max
            return order1 < order2
        }
    }

    // Helper to get exercises grouped by activity type
    private func groupedChosenExercises() -> [(activityName: String, activityColor: Color, exercises: [String])] {
        // Get all catalog data
        let activityDescriptor = FetchDescriptor<Activity>()
        let allActivities = (try? context.fetch(activityDescriptor)) ?? []
        
        // Create a map of exercise names to their parent activity and order
        var exerciseToActivityMap: [String: (activity: Activity, order: Int)] = [:]
        
        for activity in allActivities {
            for trainingType in activity.types {
                // Handle direct exercises
                for exercise in trainingType.exercises {
                    if let existing = exerciseToActivityMap[exercise.name] {
                        // Keep the one with lower order if duplicate names exist
                        if exercise.order < existing.order {
                            exerciseToActivityMap[exercise.name] = (activity, exercise.order)
                        }
                    } else {
                        exerciseToActivityMap[exercise.name] = (activity, exercise.order)
                    }
                }
                
                // Handle combination exercises
                for combination in trainingType.combinations {
                    for exercise in combination.exercises {
                        if let existing = exerciseToActivityMap[exercise.name] {
                            // Keep the one with lower order if duplicate names exist
                            if exercise.order < existing.order {
                                exerciseToActivityMap[exercise.name] = (activity, exercise.order)
                            }
                        } else {
                            exerciseToActivityMap[exercise.name] = (activity, exercise.order)
                        }
                    }
                }
            }
        }
        
        // Group chosen exercises by activity
        let groupedByActivity = Dictionary(grouping: day.chosenExercises) { exerciseName in
                exerciseToActivityMap[exerciseName]?.activity.name ?? "Unknown"
            }

            var result: [(String, Color, [String])] = []
            for (activityName, exerciseNames) in groupedByActivity {
                let activity = allActivities.first { $0.name == activityName }
                let activityColor = activity?.hue.color ?? .gray

                let sortedExercises = exerciseNames.sorted { name1, name2 in
                    // 1) Override with per-day manual order if available
                    let o1 = day.exerciseOrder[name1]
                    let o2 = day.exerciseOrder[name2]
                    if let o1, let o2, o1 != o2 { return o1 < o2 }

                    // 2) Fallback: unlogged first
                    let isLogged1 = isExerciseQuickLogged(name: name1)
                    let isLogged2 = isExerciseQuickLogged(name: name2)
                    if isLogged1 != isLogged2 { return !isLogged1 }

                    // 3) Fallback: catalog order
                    let c1 = exerciseToActivityMap[name1]?.order ?? Int.max
                    let c2 = exerciseToActivityMap[name2]?.order ?? Int.max
                    return c1 < c2
                }
                result.append((activityName, activityColor, sortedExercises))
            }
            result.sort { $0.0 < $1.0 }
            return result
        }
    
    // Break down exercise row into its own view builder
    @ViewBuilder
    private func exerciseRow(name: String) -> some View {
        let isQuickLogged = isExerciseQuickLogged(name: name)
        let exerciseInfo = getExerciseInfo(name: name)
        let isBouldering = isBoulderingExercise(name: name)
        
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(name)
                    .lineLimit(2)
                Spacer()
                
                // Quick Tick (log without details)
                Button {
                    quickLogExercise(name: name)
                } label: {
                    Image(systemName: isQuickLogged ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .labelStyle(.iconOnly)
                .controlSize(.small)
                .buttonStyle(.bordered)
                .foregroundColor(isQuickLogged ? .gray : .green)
                .disabled(isQuickLogged)
                .accessibilityLabel(isQuickLogged ? "\(name) already logged" : "Quick log \(name)")
                
                // Quick Progress (icon-only)
                Button {
                    progressExercise = ExerciseSelection(name: name)
                } label: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                }
                .labelStyle(.iconOnly)
                .controlSize(.small)
                .buttonStyle(.bordered)
                .accessibilityLabel("Show progress for \(name)")

                // Conditional logging button based on exercise type
                if isBouldering {
                    // Climb Log button for bouldering exercises
                    Button {
                        climbLoggingExercise = ExerciseSelection(name: name)
                        inputGrade = ""; inputReps = ""
                    } label: {
                        Image(systemName: "mountain.2")
                    }
                    .labelStyle(.iconOnly)
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .foregroundColor(.pink) // Use bouldering color
                    .accessibilityLabel("Log climb for \(name)")
                } else {
                    // Regular exercise log button for non-bouldering exercises
                    Button {
                        loggingExercise = ExerciseSelection(name: name)
                        inputReps = ""; inputSets = ""; inputWeight = ""; inputGrade = ""; inputNotes = ""
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .labelStyle(.iconOnly)
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Log exercise details for \(name)")
                }
            }
            
            // Exercise guidance information
            if exerciseInfo.hasGuidance {
                HStack(spacing: 12) {
                    if let reps = exerciseInfo.repsText {
                        HStack(spacing: 4) {
                            Text("Reps").bold().foregroundStyle(.primary)
                            Text(reps)
                        }
                    }
                    if let sets = exerciseInfo.setsText {
                        HStack(spacing: 4) {
                            Text("Sets").bold().foregroundStyle(.primary)
                            Text(sets)
                        }
                    }
                    if let rest = exerciseInfo.restText {
                        HStack(spacing: 4) {
                            Text("Rest").bold().foregroundStyle(.primary)
                            Text(rest)
                        }
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)
            }
        }
    }
    
    // Helper to get exercise information from catalog
    private func getExerciseInfo(name: String) -> (repsText: String?, setsText: String?, restText: String?, hasGuidance: Bool) {
        let exerciseDescriptor = FetchDescriptor<Exercise>()
        let allExercises = (try? context.fetch(exerciseDescriptor)) ?? []
        
        // Find the exercise by name
        let exercise = allExercises.first { $0.name == name }
        
        let reps = exercise?.repsText
        let sets = exercise?.setsText
        let rest = exercise?.restText
        let hasGuidance = (reps != nil && !reps!.isEmpty) ||
                         (sets != nil && !sets!.isEmpty) ||
                         (rest != nil && !rest!.isEmpty)
        
        return (reps, sets, rest, hasGuidance)
    }
    
    // Helper function to check if an exercise has been quick-logged today
    private func isExerciseQuickLogged(name: String) -> Bool {
        return loggedExercisesForDay.contains { item in
            item.exerciseName == name && item.notes == "Quick logged"
        }
    }
    
    // Row for logged exercises
    @ViewBuilder
    private func loggedExerciseRow(item: SessionItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.exerciseName)
                    .lineLimit(2)
                
                // Check if this is a climb log or regular exercise log
                if isClimbLog(item: item) {
                    ClimbLogMetricRow(item: item)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LogMetricRow(
                        reps: item.reps.map{ String(format: "%.1f", $0) },
                        sets: item.sets.map{ String(format: "%.1f", $0) },
                        weight: item.weightKg.map { String(format: "%.1f", $0) },
                        grade: item.grade
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.small)
        }
    }
    
    // Helper to determine if a session item is a climb log
    private func isClimbLog(item: SessionItem) -> Bool {
        // Check if the notes contain climb log indicators or if it's a bouldering exercise
        return item.notes?.contains("Plan climb log") == true ||
               item.notes?.contains("Attempts:") == true ||
               isBoulderingExercise(name: item.exerciseName)
    }

    // Break down the chosen activities section into its own component
    @ViewBuilder
    private var chosenActivitiesSection: some View {
        Section("Chosen activities") {
            if day.chosenExercises.isEmpty {
                Text("No activities yet").foregroundStyle(.secondary)
            } else {
                let groupedExercises = groupedChosenExercises()
                ForEach(groupedExercises, id: \.activityName) { group in
                    ActivityGroupView(
                        group: group,
                        day: $day,
                        context: context,
                        exerciseRowBuilder: exerciseRow,
                        onReorder: { didReorder = true }
                    )
                }
            }
            
            Button {
                editMode?.wrappedValue = .inactive
                showingPicker = true
            } label: {
                Label("Add from Catalog", systemImage: "plus")
            }
            .textCase(nil)
        }
    }
    
    // Break down the logged exercises section
    @ViewBuilder
    private var loggedExercisesSection: some View {
        Section("Logged exercises") {
            if loggedExercisesForDay.isEmpty {
                Text("No logs yet for this day").foregroundStyle(.secondary)
            } else {
                ForEach(loggedExercisesForDay) { item in
                    loggedExerciseRow(item: item)
                }
            }
        }
    }
    
    // Break down daily notes section
    @ViewBuilder
    private var dailyNotesSection: some View {
        Section ("Daily Notes") {
            TextEditor(text: $dailyNotesText)
                .frame(minHeight: 100)
                .onAppear {
                    // Initialize with the current value from the model
                    dailyNotesText = day.dailyNotes ?? ""
                }
                .onChange(of: dailyNotesText) {
                    // Save the notes to the model
                    let trimmed = dailyNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
                    day.dailyNotes = trimmed.isEmpty ? nil : trimmed
                    try? context.save()
                }
        }
    }

    var body: some View {
        Form {
            // Day type picker – bind to ID to avoid invalidated object crashes
            Picker("Day type", selection: $selectedDayTypeId) {
                ForEach(dayTypes) { t in
                    Text(t.name).tag(Optional(t.id))
                }
            }
            .onAppear {
                // Initialize selection from current model relation (safe if missing)
                selectedDayTypeId = day.type?.id
            }
            .onChange(of: selectedDayTypeId) { _, newId in
                // Resolve selected id to model instance; assign (or nil) safely
                let resolved = dayTypes.first(where: { $0.id == newId })
                day.type = resolved
                try? context.save()
            }
            
            chosenActivitiesSection
            loggedExercisesSection
            dailyNotesSection
        }
        .navigationTitle(day.date.formatted(date: .abbreviated, time: .omitted))
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 10) {
                    // Timer button
                    Button {
                        timerAppState.switchToTimer(with: day)
                    } label: {
                        Image(systemName: "timer")
                    }

                    // Vertical separator
                    Rectangle()
                        .frame(width: 1, height: 18)
                        .foregroundStyle(.secondary.opacity(0.5))
                        .padding(.horizontal, 2)

                    // Reorder toggle button
                    Button {
                        withAnimation {
                            editMode?.wrappedValue = (editMode?.wrappedValue == .active) ? .inactive : .active
                        }
                    } label: {
                        Image(systemName: editMode?.wrappedValue == .active ? "checkmark" : "line.3.horizontal")
                    }
                }
            }
        }
        .onChange(of: editMode?.wrappedValue) { _, newValue in
                    if newValue == .inactive, didReorder {
                        didReorder = false
                        try? context.save() // single save after drag session
                    }
                }
                .onDisappear {
                    if didReorder {
                        didReorder = false
                        try? context.save()
                    }
                }
        .sheet(isPresented: $showingPicker) {
            CatalogExercisePicker(selected: $day.chosenExercises)
                .environment(\.isDataReady, isDataReady)
        }
        // Quick Log sheet
        .sheet(item: $loggingExercise) { sel in
            NavigationStack {
                logForm(exerciseName: sel.name)
                    .listStyle(.insetGrouped)
                    .navigationTitle("Quick Log")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                saveLogEntry(exerciseName: sel.name)
                            }
                        }
                    }
                    .sensoryFeedback(.success, trigger: saveTick)
            }
        }
        // Quick Progress sheet
        .sheet(item: $progressExercise) { sel in
            QuickExerciseProgress(exerciseName: sel.name)
        }
        // Climb Log sheet for bouldering exercises
        .sheet(item: $climbLoggingExercise) { sel in
            PlanClimbLogView(
                exerciseName: sel.name,
                planDay: day,
                onSave: {
                    // Refresh any state if needed
                }
            )
        }
    }
    
    private func saveLogEntry(exerciseName: String) {
        let reps = Double(inputReps.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        let sets = Double(inputSets.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        let weight = Double(inputWeight.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        let grade = inputGrade.trimmingCharacters(in: .whitespaces).isEmpty ? nil : inputGrade.trimmingCharacters(in: .whitespaces)

        let session = findOrCreateSession(for: day.date, in: context)
        
        // Using a date range predicate instead of relationship query
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day.date)
        let _ = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        
        let planDescriptor = FetchDescriptor<Plan>()
        let plans = (try? context.fetch(planDescriptor)) ?? []
        let parentPlan = plans.first { plan in
            plan.days.contains { $0.id == day.id }
        }
        
        session.items.append(SessionItem(
            exerciseName: exerciseName,
            planSourceId: parentPlan?.id,
            planName: parentPlan?.name,
            reps: reps,
            sets: sets,
            weightKg: weight,
            grade: grade,
            notes: inputNotes.isEmpty ? nil : inputNotes
        ))
        try? context.save()
        saveTick.toggle()
        loggingExercise = nil
    }
    
    // Quick log function for tick button - logs exercise without details
    private func quickLogExercise(name: String) {
        let session = findOrCreateSession(for: day.date, in: context)
        
        let planDescriptor = FetchDescriptor<Plan>()
        let plans = (try? context.fetch(planDescriptor)) ?? []
        let parentPlan = plans.first { plan in
            plan.days.contains { $0.id == day.id }
        }
        
        // Create a simple log entry without metrics - just capture that it was done
        session.items.append(SessionItem(
            exerciseName: name,
            planSourceId: parentPlan?.id,
            planName: parentPlan?.name,
            reps: nil,
            sets: nil,
            weightKg: nil,
            grade: nil,
            notes: "Quick logged"
        ))
        try? context.save()
        saveTick.toggle()
    }
    
    // Break down log form into its own view builder
    @ViewBuilder
    private func logForm(exerciseName: String) -> some View {
        Form {
            Section { Text(exerciseName).font(.headline) }

            Section {
                LabeledContent {
                    TextField("e.g. 10", text: $inputReps)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Label("Reps", systemImage: "repeat")
                }

                LabeledContent {
                    TextField("e.g. 3", text: $inputSets)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Label("Sets", systemImage: "square.grid.3x3")
                }

                LabeledContent {
                    TextField("e.g. 12.5", text: $inputWeight)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Label("Weight (kg)", systemImage: "scalemass")
                }

                LabeledContent {
                    TextField("e.g. 6a+", text: $inputGrade)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Label("Grade", systemImage: "star")
                }
            } header: {
                Text("LOG FIELDS").textCase(nil)
            } footer: {
                Text("Leave a field empty if it doesn't apply.")
            }

            Section("Preview") {
                LogMetricRow(
                    reps: inputReps.isEmpty ? nil : inputReps,
                    sets: inputSets.isEmpty ? nil : inputSets,
                    weight: inputWeight.isEmpty ? nil : inputWeight,
                    grade: inputGrade.isEmpty ? nil : inputGrade
                )
            }

            Section("Notes") {
                TextField("Notes (optional)", text: $inputNotes, axis: .vertical)
                    .lineLimit(1...3)
            }
        }
    }
}

// MARK: Plan Climb Log View for Bouldering Exercises

struct PlanClimbLogView: View {
    @Environment(\.modelContext) private var context
    
    let exerciseName: String
    let planDay: PlanDay
    let onSave: () -> Void
    
    var body: some View {
        ClimbLogForm(
            title: "Climb Log for \(exerciseName)",
            initialDate: planDay.date
        ) { climbEntry in
            // Custom save logic for plan integration
            handlePlanClimbSave(climbEntry: climbEntry)
        }
    }
    
    private func handlePlanClimbSave(climbEntry: ClimbEntry) {
        // Find the parent plan
        let planDescriptor = FetchDescriptor<Plan>()
        let plans = (try? context.fetch(planDescriptor)) ?? []
        let parentPlan = plans.first { plan in
            plan.days.contains { $0.id == planDay.id }
        }
        
        // Create SessionItem for plan tracking
        let session = findOrCreateSession(for: planDay.date, in: context)
        
        // Convert attempts to Double for consistency
        let attemptsDouble = climbEntry.attempts != nil ? Double(climbEntry.attempts!) : nil
        
        session.items.append(SessionItem(
            exerciseName: exerciseName,
            planSourceId: parentPlan?.id,
            planName: parentPlan?.name,
            reps: attemptsDouble, // Store attempts as reps for consistency
            sets: nil,
            weightKg: nil,
            grade: climbEntry.grade != "Unknown" ? climbEntry.grade : nil,
            notes: buildSessionNotes(from: climbEntry)
        ))
        
        try? context.save()
        onSave()
    }
    
    private func buildSessionNotes(from climbEntry: ClimbEntry) -> String {
        var noteParts: [String] = []
        
        if climbEntry.style != "Unknown" {
            noteParts.append("Style: \(climbEntry.style)")
        }
        
        if climbEntry.gym != "Unknown" {
            noteParts.append("Gym: \(climbEntry.gym)")
        }
        
        return noteParts.joined(separator: " • ")
    }
}

// MARK: Quick progress

private struct QuickExerciseProgress: View {
    let exerciseName: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var pointsReps: [DataPoint] = []
    @State private var pointsSets: [DataPoint] = []
    @State private var pointsWeight: [DataPoint] = []

    struct DataPoint: Identifiable { let id = UUID(); let date: Date; let value: Double }

    enum Metric: String, CaseIterable, Identifiable { case reps = "Reps", sets = "Sets", weight = "Weight (kg)"; var id: String { rawValue } }
    @State private var metric: Metric = .reps
    
    // Break down complex view hierarchy into smaller components
    @ViewBuilder
    private func recentLogsSection(recent: [(date: Date, reps: Double?, sets: Double?, weight: Double?, notes: String?)]) -> some View {
        Section {
            if recent.isEmpty {
                Text("No logs yet for this exercise").foregroundStyle(.secondary)
            } else {
                ForEach(recent.reversed(), id: \.date) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(r.date.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            let repsTxt   = r.reps.map   { String(format: "%.1f", $0) }
                            let setsTxt   = r.sets.map   { String(format: "%.1f", $0) }
                            let weightTxt = r.weight.map { String(format: "%.1f", $0) }

                            Text([
                                repsTxt.map { "\($0)x reps" },
                                setsTxt.map { "\($0) sets" },
                                weightTxt.map { "\($0) kg" }
                            ].compactMap { $0 }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                        }
                        if let notes = r.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
            }
        } header: {
            Text("Recent logs")
        }
    }

    @ViewBuilder
    private func chartSection(pts: [DataPoint]) -> some View {
        Section("Chart") {
            Picker("Metric", selection: $metric) {
                ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if pts.isEmpty {
                Text("No numeric data for \(metric.rawValue) yet.")
                    .foregroundStyle(.secondary)
            } else {
                Chart(pts) { p in
                    LineMark(
                        x: .value("Date", p.date),
                        y: .value(metric.rawValue, p.value)
                    )
                    PointMark(
                        x: .value("Date", p.date),
                        y: .value(metric.rawValue, p.value)
                    )
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3))
                }
                .frame(minHeight: 220)
                .accessibilityLabel("Progress chart")
                .accessibilityValue("\(metric.rawValue) over time")
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(exerciseName).font(.headline)
                }
                
                // Use extracted view components
                let recent = rows().suffix(10)
                recentLogsSection(recent: Array(recent))
                chartSection(pts: series(for: metric))
            }
            .navigationTitle("Progress")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
    }

    // Build recent rows quickly from all sessions
    private func rows() -> [(date: Date, reps: Double?, sets: Double?, weight: Double?, notes: String?)] {
        let descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor<Session>(\.date, order: .reverse)]
        )
        let sessions = (try? context.fetch(descriptor)) ?? []
        
        return sessions.flatMap { session in
            session.items
                .filter { $0.exerciseName == exerciseName }
                .map {
                    (date: session.date,
                     reps: $0.reps,
                     sets: $0.sets,
                     weight: $0.weightKg,
                     notes: $0.notes) // <- add notes
                }
        }.sorted { $0.date < $1.date }
    }



    private func series(for metric: Metric) -> [DataPoint] {
        switch metric {
        case .reps:   return pointsReps
        case .sets:   return pointsSets
        case .weight: return pointsWeight
        }
    }

    private func loadSeries(from rows: [(Date, Double?, Double?, Double?, String?)]) {
        pointsReps   = rows.compactMap { (d, r, _, _, _) in r.map { DataPoint(date: d, value: $0) } }
        pointsSets   = rows.compactMap { (d, _, s, _, _) in s.map { DataPoint(date: d, value: $0) } }
        pointsWeight = rows.compactMap { (d, _, _, w, _) in w.map { DataPoint(date: d, value: $0) } }
    }



    private func load() async {
        let r = rows()
        loadSeries(from: r)
    }
}

// MARK: Catalog picker (Activity → TrainingType → [Combinations] → Exercises)

struct CatalogExercisePicker: View {
    @Binding var selected: [String]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Activity.name) private var activities: [Activity]
    @State private var searchText: String = ""
    @State private var isSearchPresented: Bool = false
    
    // Instead of relying on isDataReady environment, check if we have data directly
    private var hasData: Bool {
        !activities.isEmpty
    }
    
    // Flatten all exercises (including combos) with their activity tint
    private var allExerciseHits: [ExerciseHit] {
        var hits: [ExerciseHit] = []
        for activity in activities {
            let tint = activity.hue.color
            for t in activity.types {
                // direct exercises
                for ex in t.exercises { hits.append(ExerciseHit(ex: ex, tint: tint)) }
                // combo exercises
                for combo in t.combinations {
                    for ex in combo.exercises { hits.append(ExerciseHit(ex: ex, tint: tint)) }
                }
            }
        }
        // de-dup by exercise id in case an exercise appears multiple places
        var seen: Set<UUID> = []
        return hits.filter { seen.insert($0.id).inserted }
    }
    
    // Filter by search text across exercise name + subtitle
    private var filteredExerciseHits: [ExerciseHit] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return allExerciseHits.filter {
            $0.name.localizedCaseInsensitiveContains(q)
            || ($0.subtitle?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }
    
    // Provide a reusable section builder for search results to reuse in subviews
    @ViewBuilder
    private func resultsSection(doneAction: @escaping () -> Void) -> some View {
        if !searchText.isEmpty {
            if filteredExerciseHits.isEmpty {
                ContentUnavailableView(
                    "No matches",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search term.")
                )
            } else {
                Section {
                    ForEach(filteredExerciseHits) { hit in
                        ExercisePickRow(
                            name: hit.name,
                            subtitle: hit.subtitle,
                            reps: nil, sets: nil, rest: nil,
                            tint: hit.tint,
                            isSelected: selected.contains(hit.name)
                        ) {
                            toggleSelection(hit.name)
                        }
                    }
                } header: {
                    HStack {
                        Text("Results")
                        Spacer()
                        Button("Done") {
                            isSearchPresented = false // collapse search UI
                            doneAction()              // allow caller to dismiss if desired
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            if !hasData {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading catalog...")
                        .foregroundStyle(.secondary)
                    // Debug info
                    Text("Debug: activities.count = \(activities.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    print("🔴 CatalogExercisePicker: activities.count = \(activities.count)")
                }
                // Add a refresh mechanism
                .task {
                    // Small delay to allow SwiftData to initialize
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
            } else {
                List {
                    // While searching: show only results, hide navigation content
                    if !searchText.isEmpty {
                        resultsSection(doneAction: { dismiss() })
                    } else {
                        // Normal content (root: activities)
                        ForEach(activities) { activity in
                            NavigationLink {
                                TypesList(
                                    activity: activity,
                                    selected: $selected,
                                    tint: activity.hue.color,
                                    onDone: { dismiss() },     // close from any level
                                    searchText: $searchText,
                                    isSearchPresented: $isSearchPresented,
                                    allHitsProvider: { (activities) in
                                        // Reuse the same flattening logic
                                        var hits: [ExerciseHit] = []
                                        for activity in activities {
                                            let tint = activity.hue.color
                                            for t in activity.types {
                                                for ex in t.exercises { hits.append(ExerciseHit(ex: ex, tint: tint)) }
                                                for combo in t.combinations {
                                                    for ex in combo.exercises { hits.append(ExerciseHit(ex: ex, tint: tint)) }
                                                }
                                            }
                                        }
                                        // de-dup by ID
                                        var seen: Set<UUID> = []
                                        return hits.filter { seen.insert($0.id).inserted }
                                    }
                                )
                            } label: {
                                HStack(spacing: 10) {
                                    Circle().fill(activity.hue.color).frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(activity.name).font(.headline)
                                        Text("\(activity.types.count) types")
                                            .font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .onAppear {
                    print("🟢 CatalogExercisePicker: activities.count = \(activities.count)")
                }
                .searchable(text: $searchText, isPresented: $isSearchPresented, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            }
        }
        .navigationTitle("Catalog")
        .toolbar {
            // Existing Done to close the picker
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }

            // Extra Done that *exits search* (only visible while searching)
            ToolbarItem(placement: .topBarTrailing) {
                if isSearchPresented {
                    Button("Done") {
                        isSearchPresented = false        // collapses search, dismisses keyboard
                        dismiss()
                    }
                }
            }
        }
    }
    private func toggleSelection(_ name: String) {
        if let idx = selected.firstIndex(of: name) {
            selected.remove(at: idx)
        } else {
            selected.append(name)
        }
    }
}

// TypesList now receives search bindings and a provider closure to compute all hits,
// then shows the same unified Results section at the top while searching.
struct TypesList: View {
    @Bindable var activity: Activity
    @Binding var selected: [String]
    let tint: Color
    let onDone: () -> Void
    @Binding var searchText: String
    @Binding var isSearchPresented: Bool
    // Provider to compute flattened hits for the whole catalog (same as root)
    let allHitsProvider: ([Activity]) -> [ExerciseHit]
    @Query(sort: \Activity.name) private var activities: [Activity]
    
    private var allHits: [ExerciseHit] {
        allHitsProvider(activities)
    }
    private var filteredHits: [ExerciseHit] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return allHits.filter {
            $0.name.localizedCaseInsensitiveContains(q)
            || ($0.subtitle?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }
    
    var body: some View {
        List {
            // While searching: show only results, hide navigation content
            if !searchText.isEmpty {
                if filteredHits.isEmpty {
                    ContentUnavailableView(
                        "No matches",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search term.")
                    )
                } else {
                    Section {
                        ForEach(filteredHits) { hit in
                            ExercisePickRow(
                                name: hit.name,
                                subtitle: hit.subtitle,
                                reps: nil, sets: nil, rest: nil,
                                tint: hit.tint,
                                isSelected: selected.contains(hit.name)
                            ) {
                                toggle(hit.name)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Results")
                            Spacer()
                            Button("Done") {
                                isSearchPresented = false
                                onDone()
                            }
                            .font(.subheadline)
                        }
                    }
                }
            } else {
                // Normal content
                ForEach(activity.types) { t in
                    NavigationLink {
                        if !t.combinations.isEmpty {
                            CombosList(
                                trainingType: t,
                                selected: $selected,
                                tint: tint,
                                onDone: onDone,
                                searchText: $searchText,
                                isSearchPresented: $isSearchPresented,
                                allHitsProvider: allHitsProvider
                            )
                        } else {
                            ExercisesList(
                                trainingType: t,
                                selected: $selected,
                                tint: tint,
                                onDone: onDone,
                                searchText: $searchText,
                                isSearchPresented: $isSearchPresented,
                                allHitsProvider: allHitsProvider
                            )
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name).font(.headline)
                            if let d = t.typeDescription, !d.isEmpty {
                                Text(d).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(activity.name)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", action: onDone) } }
        .searchable(text: $searchText, isPresented: $isSearchPresented, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }
    
    private func toggle(_ name: String) {
        if let idx = selected.firstIndex(of: name) {
            selected.remove(at: idx)
        } else {
            selected.append(name)
        }
    }
}

struct CombosList: View {
    @Bindable var trainingType: TrainingType
    @Binding var selected: [String]
    let tint: Color
    let onDone: () -> Void
    @Binding var searchText: String
    @Binding var isSearchPresented: Bool
    let allHitsProvider: ([Activity]) -> [ExerciseHit]
    @Query(sort: \Activity.name) private var activities: [Activity]
    
    private var allHits: [ExerciseHit] {
        allHitsProvider(activities)
    }
    private var filteredHits: [ExerciseHit] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return allHits.filter {
            $0.name.localizedCaseInsensitiveContains(q)
            || ($0.subtitle?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var body: some View {
        List {
            // While searching: show only results, hide navigation content
            if !searchText.isEmpty {
                if filteredHits.isEmpty {
                    ContentUnavailableView(
                        "No matches",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search term.")
                    )
                } else {
                    Section {
                        ForEach(filteredHits) { hit in
                            ExercisePickRow(
                                name: hit.name,
                                subtitle: hit.subtitle,
                                reps: nil, sets: nil, rest: nil,
                                tint: hit.tint,
                                isSelected: selected.contains(hit.name)
                            ) {
                                toggle(hit.name)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Results")
                            Spacer()
                            Button("Done") {
                                isSearchPresented = false
                                onDone()
                            }
                            .font(.subheadline)
                        }
                    }
                }
            } else {
                // Normal content (combinations)
                ForEach(trainingType.combinations) { combo in
                    NavigationLink {
                        ComboExercisesList(
                            combo: combo,
                            selected: $selected,
                            tint: tint,
                            onDone: onDone,
                            searchText: $searchText,
                            isSearchPresented: $isSearchPresented,
                            allHitsProvider: allHitsProvider
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(combo.name).font(.headline)
                            if let d = combo.comboDescription, !d.isEmpty {
                                Text(d).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(trainingType.name)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", action: onDone) } }
        .searchable(text: $searchText, isPresented: $isSearchPresented, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }
    
    private func toggle(_ name: String) {
        if let idx = selected.firstIndex(of: name) {
            selected.remove(at: idx)
        } else {
            selected.append(name)
        }
    }
}

struct ComboExercisesList: View {
    @Bindable var combo: BoulderCombination
    @Binding var selected: [String]
    let tint: Color
    let onDone: () -> Void
    @Binding var searchText: String
    @Binding var isSearchPresented: Bool
    let allHitsProvider: ([Activity]) -> [ExerciseHit]
    @Query(sort: \Activity.name) private var activities: [Activity]
    
    private var allHits: [ExerciseHit] {
        allHitsProvider(activities)
    }
    private var filteredHits: [ExerciseHit] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return allHits.filter {
            $0.name.localizedCaseInsensitiveContains(q)
            || ($0.subtitle?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var body: some View {
        List {
            // While searching: show only results, hide navigation content
            if !searchText.isEmpty {
                if filteredHits.isEmpty {
                    ContentUnavailableView(
                        "No matches",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search term.")
                    )
                } else {
                    Section {
                        ForEach(filteredHits) { hit in
                            ExercisePickRow(
                                name: hit.name,
                                subtitle: hit.subtitle,
                                reps: nil, sets: nil, rest: nil,
                                tint: hit.tint,
                                isSelected: selected.contains(hit.name)
                            ) {
                                toggle(hit.name)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Results")
                            Spacer()
                            Button("Done") {
                                isSearchPresented = false
                                onDone()
                            }
                            .font(.subheadline)
                        }
                    }
                }
            } else {
                // Normal content (combo’s exercises)
                ForEach(combo.exercises.sorted { $0.order < $1.order }) { ex in
                    ExercisePickRow(
                        name: ex.name,
                        subtitle: ex.exerciseDescription?.isEmpty == false ? ex.exerciseDescription : ex.notes,
                        reps: ex.repsText, sets: ex.setsText, rest: ex.restText,
                        tint: tint,
                        isSelected: selected.contains(ex.name)
                    ) {
                        toggle(ex.name)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(combo.name)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", action: onDone) } }
        .searchable(text: $searchText, isPresented: $isSearchPresented, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }

    private func toggle(_ name: String) {
        if let idx = selected.firstIndex(of: name) {
            selected.remove(at: idx)
        } else {
            selected.append(name)
        }
    }
}

struct ExercisesList: View {
    let trainingType: TrainingType
    @Binding var selected: [String]
    let tint: Color
    let onDone: () -> Void
    @Binding var searchText: String
    @Binding var isSearchPresented: Bool
    let allHitsProvider: ([Activity]) -> [ExerciseHit]
    @Query(sort: \Activity.name) private var activities: [Activity]
    
    private var allHits: [ExerciseHit] {
        allHitsProvider(activities)
    }
    private var filteredHits: [ExerciseHit] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return allHits.filter {
            $0.name.localizedCaseInsensitiveContains(q)
            || ($0.subtitle?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    // Group exercises by area similar to CatalogView
    private var exercisesByArea: [(String, [Exercise])] {
        let grouped = Dictionary(grouping: trainingType.exercises) { $0.area ?? "" }
        if grouped.keys.contains("Fingers") || grouped.keys.contains("Pull") {
            // For climbing-specific exercises, maintain Fingers/Pull order
            return ["Fingers", "Pull"].compactMap { area in
                if let exercises = grouped[area], !exercises.isEmpty {
                    return (area, exercises.sorted { $0.order < $1.order })
                }
                return nil
            }
        } else {
            // For other types, just group if there are areas
            return grouped
                .filter { !$0.key.isEmpty }
                .map { ($0.key, $0.value.sorted { $0.order < $1.order }) }
                .sorted(by: { $0.0 < $1.0 })
        }
    }

    private var ungroupedExercises: [Exercise] {
        trainingType.exercises.filter { $0.area == nil }.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            // While searching: show only results, hide navigation content
            if !searchText.isEmpty {
                if filteredHits.isEmpty {
                    ContentUnavailableView(
                        "No matches",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search term.")
                    )
                } else {
                    Section {
                        ForEach(filteredHits) { hit in
                            ExercisePickRow(
                                name: hit.name,
                                subtitle: hit.subtitle,
                                reps: nil, sets: nil, rest: nil,
                                tint: hit.tint,
                                isSelected: selected.contains(hit.name)
                            ) {
                                toggle(hit.name)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Results")
                            Spacer()
                            Button("Done") {
                                isSearchPresented = false
                                onDone()
                            }
                            .font(.subheadline)
                        }
                    }
                }
            } else {
                // Normal content
                if !exercisesByArea.isEmpty {
                    ForEach(exercisesByArea, id: \.0) { area, exercises in
                        Section(area) {
                            ForEach(exercises) { ex in
                                ExercisePickRow(
                                    name: ex.name,
                                    subtitle: ex.exerciseDescription?.isEmpty == false ? ex.exerciseDescription : ex.notes,
                                    reps: ex.repsText, sets: ex.setsText, rest: ex.restText,
                                    tint: tint,
                                    isSelected: selected.contains(ex.name)
                                ) {
                                    toggle(ex.name)
                                }
                            }
                        }
                    }
                }
                
                if !ungroupedExercises.isEmpty {
                    Section(exercisesByArea.isEmpty ? "Exercises" : "Other") {
                        ForEach(ungroupedExercises) { ex in
                            ExercisePickRow(
                                name: ex.name,
                                subtitle: ex.exerciseDescription?.isEmpty == false ? ex.exerciseDescription : ex.notes,
                                reps: ex.repsText, sets: ex.setsText, rest: ex.restText,
                                tint: tint,
                                isSelected: selected.contains(ex.name)
                            ) {
                                toggle(ex.name)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(trainingType.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { onDone() } }
        }
        .searchable(text: $searchText, isPresented: $isSearchPresented, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }

    private func toggle(_ name: String) {
        if let idx = selected.firstIndex(of: name) {
            selected.remove(at: idx)
        } else {
            selected.append(name)
        }
    }
}

// MARK: - Compact row + MetricRow

private struct ExercisePickRow: View {
    let name: String
    let subtitle: String?
    let reps: String?
    let sets: String?
    let rest: String?
    let tint: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle().fill(tint).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.subheadline).fontWeight(.semibold)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                MetricRow(reps: reps, sets: sets, rest: rest)
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .imageScale(.large)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .padding(.vertical, 6)
    }
}

private struct MetricRow: View {
    let reps: String?
    let sets: String?
    let rest: String?

    var body: some View {
        HStack(spacing: 12) {
            metric("Reps", reps)
            metric("Sets", sets)
            metric("Rest", rest)
        }
        .font(.caption.monospacedDigit())           // 👈 monospaced digits
    }

    @ViewBuilder
    private func metric(_ label: String, _ value: String?) -> some View {
        HStack(spacing: 4) {
            Text(label).bold().foregroundStyle(.secondary)
            Text(value ?? "—")
        }
    }
}


private struct LogMetricRow: View {
    let reps: String?
    let sets: String?
    let weight: String?
    let grade: String?

    var body: some View {
        HStack(spacing: 12) {
            metric("Reps", reps)
            metric("Sets", sets)
            metric("Weight", weight.map { "\($0) kg" })
            metric("Grade", grade)
        }
        .font(.caption.monospacedDigit())
    }

    @ViewBuilder
    private func metric(_ label: String, _ value: String?) -> some View {
        HStack(spacing: 4) {
            Text(label).bold().foregroundStyle(.secondary)
            Text(value ?? "—")
        }
    }
}

// Helper function to find or create a session for a given date
private func findOrCreateSession(for date: Date, in context: ModelContext) -> Session {
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: date)
    let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
    
    let descriptor = FetchDescriptor<Session>(
        sortBy: [SortDescriptor(\Session.date)]
    )
    let existingSessions = (try? context.fetch(descriptor)) ?? []
    let existing = existingSessions.first { session in
        session.date >= startOfDay && session.date < endOfDay
    }
    
    if let existing = existing {
        return existing
    }
    
    let newSession = Session(date: date)
    context.insert(newSession)
    return newSession
}

private struct MonthlyGridView: View {
    let groups: [(components: DateComponents, days: [PlanDay])]
    let calendar: Calendar
    @EnvironmentObject private var timerAppState: TimerAppState
    @Environment(\.modelContext) private var context

    // Helper to check if a day is today
    private func isToday(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: Date())
    }
    
    // Helper to find the current day in the plan
    private var currentDayId: UUID? {
        groups.flatMap { $0.days }.first { isToday($0.date) }?.id
    }
    
    // Resolve color by refetching the DayTypeModel
    private func dayTypeColor(for day: PlanDay) -> Color {
        guard let typeId = day.type?.id else { return .gray }
        let fetch = FetchDescriptor<DayTypeModel>(predicate: #Predicate { $0.id == typeId })
        if let fresh = (try? context.fetch(fetch))?.first {
            return fresh.color
        } else {
            return .gray
        }
    }

    // Extract day cell into separate view to reduce type checking complexity
    @ViewBuilder
    private func dayCell(for day: PlanDay) -> some View {
        Button {
            timerAppState.plansNavigationPath.append(PlanDayNavigationItem(planDay: day))
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: day.date))")
                    .font(.caption)
                    .fontWeight(isToday(day.date) ? .bold : .regular)
                    .foregroundStyle(isToday(day.date) ? .white : .primary)
                Circle()
                    .fill(dayTypeColor(for: day))
                    .frame(width: 8, height: 8)
            }
            .frame(maxWidth: .infinity)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isToday(day.date) ? Color.accentColor : Color.secondary.opacity(0.01))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isToday(day.date) ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .id(day.id)
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        
        ScrollViewReader { proxy in
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    let monthDate = calendar.date(from: group.components) ?? Date()
                    
                    Section {
                        ForEach(group.days) { day in
                            dayCell(for: day)
                        }
                    } header: {
                        Text(monthDate.formatted(.dateTime.year().month()))
                            .font(.headline)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.horizontal)
            .onAppear {
                // Scroll to current day when view appears
                if let currentId = currentDayId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo(currentId, anchor: .center)
                    }
                }
            }
        }
    }
}

private struct ClimbLogMetricRow: View {
    let item: SessionItem
    
    private var climbTypeColor: Color {
        // Default to boulder color since most plan climbs are bouldering
        // Could be enhanced to detect climb type from notes if needed
        return CatalogHue.bouldering.color
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Top row: Attempts, Grade, WIP status
            HStack(alignment: .center) {
                // Attempts (if available)
                if let attempts = item.reps {
                    Text("\(Int(attempts)) attempts")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                
                // Grade - only show if available
                if let grade = item.grade {
                    if item.reps != nil {
                        Text("•")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    Text("grade \(grade)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            

        }
    }
    
    // Parse climb-specific information from notes
    private func parseClimbNotes(_ notes: String?) -> (style: String?, gym: String?, isWIP: Bool) {
        guard let notes = notes else { return (nil, nil, false) }
        
        var style: String?
        var gym: String?
        var isWIP = false
        
        // Split notes by separator
        let parts = notes.components(separatedBy: " • ")
        
        for part in parts {
            if part.hasPrefix("Style: ") {
                style = String(part.dropFirst(7)) // Remove "Style: "
            } else if part.hasPrefix("Gym: ") {
                gym = String(part.dropFirst(5)) // Remove "Gym: "
            } else if part == "WIP" {
                isWIP = true
            }
        }
        
        return (style, gym, isWIP)
    }
}

// MARK: Activity Group View Component
private struct ActivityGroupView: View {
    let group: (activityName: String, activityColor: Color, exercises: [String])
    @Binding var day: PlanDay
    let context: ModelContext
    let exerciseRowBuilder: (String) -> AnyView
    let onReorder: () -> Void

    @Environment(\.editMode) private var editMode
    @State private var localOrder: [String] = []   // ✅ decouple UI from model while dragging

    init(group: (activityName: String, activityColor: Color, exercises: [String]),
         day: Binding<PlanDay>,
         context: ModelContext,
         exerciseRowBuilder: @escaping (String) -> some View,
         onReorder: @escaping () -> Void) {
        self.group = group
        self._day = day
        self.context = context
        self.exerciseRowBuilder = { name in AnyView(exerciseRowBuilder(name)) }
        self.onReorder = onReorder
        self._localOrder = State(initialValue: group.exercises) // seed
    }

    var body: some View {
        Section {
            ForEach(localOrder, id: \.self) { name in
                exerciseRowBuilder(name)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            delete(names: [name])
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            .onMove { source, destination in
                var tx = Transaction(); tx.disablesAnimations = true
                withTransaction(tx) {
                    var arr = localOrder
                    arr.move(fromOffsets: source, toOffset: destination)
                    localOrder = arr
                }
            }
            .moveDisabled(false)
        } header: {
            HStack(spacing: 8) {
                Circle().fill(group.activityColor).frame(width: 12, height: 12)
                Text(group.activityName).font(.subheadline).fontWeight(.medium).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .onChange(of: editMode?.wrappedValue) { _, newValue in
            // Commit once when leaving edit mode -> minimal work, no lag during drag
            if newValue == .inactive {
                for (idx, name) in localOrder.enumerated() { day.exerciseOrder[name] = idx }
                onReorder()
            }
        }
        .onChange(of: group.exercises) { _, newValue in
            // Keep localOrder in sync when data changes from outside edit sessions
            if editMode?.wrappedValue != .active {
                localOrder = newValue
            }
        }
        .onAppear {
            if localOrder.isEmpty { localOrder = group.exercises }
        }
    }
    private func delete(names: [String]) {
        //Update local UI list
        localOrder.removeAll { names.contains($0) }
        //Remove from chosenExercises
        day.chosenExercises.removeAll { names.contains($0) }
        //Clean up per-day order map
        for n in names { day.exerciseOrder.removeValue(forKey: n) }
        //Reindex remaining names in this group to keep contiguous order
        for (idx, name) in localOrder.enumerated() {
            day.exerciseOrder[name] = idx
        }
        // Persist and notify
        onReorder()
        try? context.save()
    }
}




