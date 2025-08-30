//
//  ProgressViewScreen.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//

import SwiftUI
import SwiftData
import Charts

struct ProgressViewScreen: View {
    // Data queries
    @Query(sort: \Session.date) private var allSessions: [Session]
    @Query(sort: \ClimbEntry.dateLogged) private var allClimbEntries: [ClimbEntry]
    @Query(sort: \Plan.startDate) private var plansForFilter: [Plan]
    
    // Filter states
    @State private var selectedType: LogType = .climb
    @State private var selectedStyle: String = ""
    @State private var selectedGrade: String = ""
    @State private var selectedAngle: String = ""
    @State private var selectedGym: String = ""
    @State private var selectedClimbType: String = ""
    @State private var selectedMetric: Metric = .count
    @State private var selectedPlanID: UUID? = nil
    
    // Chart selection states
    @State private var selectedDistributionAxis: DistributionAxis = .style
    
    // Date range filter
    @State private var dateRange: DateRange = .all
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    
    // Enums for filters and metrics
    enum LogType: String, CaseIterable, Identifiable {
        case exercise = "Exercise"
        case climb = "Climb"
        var id: String { rawValue }
    }
    
    enum Metric: String, CaseIterable, Identifiable {
        case count = "Count"
        case reps = "Reps"
        case weight = "Weight (kg)"
        case grade = "Grade"
        var id: String { rawValue }
    }
    
    enum DistributionAxis: String, CaseIterable, Identifiable {
        case style = "Style"
        case grade = "Grade"
        case angle = "Angle"
        var id: String { rawValue }
        
        // Dynamic display name based on selected type
        func displayName(for logType: LogType) -> String {
            switch self {
            case .style:
                return logType == .exercise ? "Exercise" : "Style"
            case .grade:
                return "Grade"
            case .angle:
                return "Angle"
            }
        }
    }
    private func parseAttempts(_ s: String?) -> Int {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else {
            // empty or nil → count as 1
            return 1
        }
        let digits = s.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Int(digits) ?? 1   // if parsing fails, fall back to 1
    }
    
    private var totalAttempts: Int {
        dateFilteredClimbEntries
            .filter(applyFiltersToClimb)
            .map { parseAttempts($0.attempts) }
            .reduce(0, +)
    }
    
    private var totalexercises: Int {
        dateFilteredSessions
            .map { session in
                session.items.filter { applyFiltersToExercise($0) }.count
            }
            .reduce(0, +)
    }
    enum DateRange: String, CaseIterable, Identifiable {
        case all = "All Time"
        case last7Days = "Last 7 Days"
        case last30Days = "Last 30 Days"
        case last3Months = "Last 3 Months"
        case custom = "Custom Range"
        var id: String { rawValue }
    }
    
    // Data processing
    var dateFilteredSessions: [Session] {
        let filtered = filterSessionsByDateRange(allSessions)
        return filterByPlan(filtered)
    }
    
    var dateFilteredClimbEntries: [ClimbEntry] {
        filterClimbsByDateRange(allClimbEntries)
    }
    
    
    private func filterSessionsByDateRange(_ sessions: [Session]) -> [Session] {
        let now = Date()
        let calendar = Calendar.current
        
        let startDate: Date
        switch dateRange {
        case .all:
            return sessions
        case .last7Days:
            startDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .last30Days:
            startDate = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .last3Months:
            startDate = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .custom:
            startDate = customStartDate
        }
        
        let endDate = dateRange == .custom ? customEndDate : now
        return sessions.filter { $0.date >= startDate && $0.date <= endDate }
    }
    
    private func filterClimbsByDateRange(_ climbs: [ClimbEntry]) -> [ClimbEntry] {
        let now = Date()
        let calendar = Calendar.current
        
        let startDate: Date
        switch dateRange {
        case .all:
            return climbs
        case .last7Days:
            startDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .last30Days:
            startDate = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .last3Months:
            startDate = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .custom:
            startDate = customStartDate
        }
        
        let endDate = dateRange == .custom ? customEndDate : now
        return climbs.filter { $0.dateLogged >= startDate && $0.dateLogged <= endDate }
    }
    
    private func filterByPlan(_ sessions: [Session]) -> [Session] {
        guard let pid = selectedPlanID,
              let plan = plansForFilter.first(where: { $0.id == pid }) else { return sessions }
        let dates = plan.days.map { $0.date }
        guard let minD = dates.min(), let maxD = dates.max() else { return sessions }
        return sessions.filter { $0.date >= minD && $0.date <= maxD }
    }
    
    // Get unique values for filter dropdowns
    var availableStyles: [String] {
        var styles: [String] = []
        
        if selectedType == .exercise {
            // For exercises, we don't have style directly, but we can use exercise names as styles
            styles.append(contentsOf: dateFilteredSessions.flatMap { $0.items.map { $0.exerciseName } })
        } else {
            styles.append(contentsOf: dateFilteredClimbEntries.map { $0.style })
        }
        
        return Array(Set(styles)).sorted()
    }
    
    var availableGrades: [String] {
        var grades: [String] = []
        
        if selectedType == .exercise {
            grades.append(contentsOf: dateFilteredSessions.flatMap { $0.items.compactMap { $0.grade } })
        } else {
            grades.append(contentsOf: dateFilteredClimbEntries.map { $0.grade })
        }
        
        return Array(Set(grades)).sorted()
    }
    
    var availableAngles: [String] {
        var angles: [String] = []
        
        if selectedType == .climb {
            angles.append(contentsOf: dateFilteredClimbEntries.compactMap { entry in
                entry.angleDegrees.map { "\($0)°" }
            })
        }
        
        return Array(Set(angles)).sorted()
    }
    
    var availableGyms: [String] {
        var gyms: [String] = []
        
        if selectedType == .climb {
            gyms.append(contentsOf: dateFilteredClimbEntries.map { $0.gym })
        }
        
        return Array(Set(gyms)).sorted()
    }
    
    // Data points for charts
    struct TimeSeriesDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let count: Int
    }
    
    struct DistributionDataPoint: Identifiable {
        let id = UUID()
        let category: String
        let count: Int
    }
    
    var timeSeriesData: [TimeSeriesDataPoint] {
        let calendar = Calendar.current
        var dateCountMap: [Date: Int] = [:]
        
        if selectedType == .exercise {
            // Process exercises
            for session in dateFilteredSessions {
                let dayStart = calendar.startOfDay(for: session.date)
                let items = session.items.filter { item in
                    applyFiltersToExercise(item)
                }
                dateCountMap[dayStart, default: 0] += items.count
            }
        } else {
            // Process climbs
            for climb in dateFilteredClimbEntries {
                if applyFiltersToClimb(climb) {
                    let dayStart = calendar.startOfDay(for: climb.dateLogged)
                    dateCountMap[dayStart, default: 0] += 1
                }
            }
        }
        
        return dateCountMap.map { TimeSeriesDataPoint(date: $0.key, count: $0.value) }
            .sorted { $0.date < $1.date }
    }
    
    var distributionData: [DistributionDataPoint] {
        var categoryCountMap: [String: Int] = [:]
        
        if selectedType == .exercise {
            // Process exercises
            for session in dateFilteredSessions {
                for item in session.items {
                    if applyFiltersToExercise(item) {
                        let category = getCategoryValue(for: item, axis: selectedDistributionAxis)
                        categoryCountMap[category, default: 0] += 1
                    }
                }
            }
        } else {
            // Process climbs
            for climb in dateFilteredClimbEntries {
                if applyFiltersToClimb(climb) {
                    let category = getCategoryValue(for: climb, axis: selectedDistributionAxis)
                    categoryCountMap[category, default: 0] += 1
                }
            }
        }
        
        return categoryCountMap.map { DistributionDataPoint(category: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
    
    private func applyFiltersToExercise(_ item: SessionItem) -> Bool {
        if !selectedStyle.isEmpty && item.exerciseName != selectedStyle { return false }
        if !selectedGrade.isEmpty && item.grade != selectedGrade { return false }
        return true
    }
    
    private func applyFiltersToClimb(_ climb: ClimbEntry) -> Bool {
        if !selectedStyle.isEmpty && climb.style != selectedStyle { return false }
        if !selectedGrade.isEmpty && climb.grade != selectedGrade { return false }
        if !selectedAngle.isEmpty {
            let angleStr = climb.angleDegrees.map { "\($0)°" } ?? ""
            if angleStr != selectedAngle { return false }
        }
        if !selectedGym.isEmpty && climb.gym != selectedGym { return false }
        if !selectedClimbType.isEmpty && climb.climbType.rawValue != selectedClimbType { return false }
        return true
    }
    
    private func getCategoryValue(for item: SessionItem, axis: DistributionAxis) -> String {
        switch axis {
        case .style:
            return item.exerciseName
        case .grade:
            return item.grade ?? "No Grade"
        case .angle:
            return "N/A" // Exercises don't have angles
        }
    }
    
    private func getCategoryValue(for climb: ClimbEntry, axis: DistributionAxis) -> String {
        switch axis {
        case .style:
            return climb.style
        case .grade:
            return climb.grade
        case .angle:
            return climb.angleDegrees.map { "\($0)°" } ?? "No Angle"
        }
    }
    
    var totalCount: Int {
        if selectedType == .exercise {
            return dateFilteredSessions.flatMap { $0.items.filter(applyFiltersToExercise) }.count
        } else {
            return dateFilteredClimbEntries.filter(applyFiltersToClimb).count
        }
    }
    
    // Clear all filters function
    private func clearAllFilters() {
        selectedStyle = ""
        selectedGrade = ""
        selectedAngle = ""
        selectedGym = ""
        selectedClimbType = ""
        selectedPlanID = nil
        dateRange = .all
        selectedDistributionAxis = .style
        customEndDate = Date()
        customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Type Toggle Section
                Section {
                    Picker("Type", selection: $selectedType) {
                        ForEach(LogType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Type")
                }
                
                // Filters Section
                Section("Filters") {
                    Picker("Date Range", selection: $dateRange) {
                        ForEach(DateRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    
                    if dateRange == .custom {
                        DatePicker("Start Date", selection: $customStartDate, displayedComponents: .date)
                        DatePicker("End Date", selection: $customEndDate, displayedComponents: .date)
                    }
                    
                    // Exercise-specific filters
                    if selectedType == .exercise {
                        Picker("Plan", selection: $selectedPlanID) {
                            Text("All plans").tag(UUID?.none)
                            ForEach(plansForFilter) { p in
                                Text(p.name).tag(UUID?.some(p.id))
                            }
                        }
                    }
                    
                    // Climb-specific filters
                    if selectedType == .climb {
                        Picker("Climb Type", selection: $selectedClimbType) {
                            Text("All types").tag("")
                            Text("Boulder").tag("Boulder")
                            Text("Lead").tag("Lead")
                        }
                        
                        if !availableAngles.isEmpty {
                            Picker("Angle", selection: $selectedAngle) {
                                Text("All angles").tag("")
                                ForEach(availableAngles, id: \.self) { angle in
                                    Text(angle).tag(angle)
                                }
                            }
                        }
                        
                        if !availableGyms.isEmpty {
                            Picker("Gym", selection: $selectedGym) {
                                Text("All gyms").tag("")
                                ForEach(availableGyms, id: \.self) { gym in
                                    Text(gym).tag(gym)
                                }
                            }
                        }
                    }
                    
                    // Common filters
                    if !availableStyles.isEmpty {
                        Picker(selectedType == .exercise ? "Exercise" : "Style", selection: $selectedStyle) {
                            Text(selectedType == .exercise ? "All exercises" : "All styles").tag("")
                            ForEach(availableStyles, id: \.self) { style in
                                Text(style).tag(style)
                            }
                        }
                    }
                    
                    if !availableGrades.isEmpty {
                        Picker("Grade", selection: $selectedGrade) {
                            Text("All grades").tag("")
                            ForEach(availableGrades, id: \.self) { grade in
                                Text(grade).tag(grade)
                            }
                        }
                    }
                    
                    // Clear Filters Button
                    Button("Clear All Filters") {
                        clearAllFilters()
                    }
                    .foregroundColor(.red)
                }
                
                // Summary Section
                Section("Summary") {
                    if selectedType == .exercise {
                        HStack {
                            Text("#Sessions")
                            Spacer()
                            Text("\(dateFilteredSessions.count)")
                        }
                        HStack {
                            Text("#Exercises")
                            Spacer()
                            Text("\(totalexercises)") //change to total exercises
                        }
                    } else {
                            HStack {
                                Text("#Climbs")
                                Spacer()
                                Text("\(dateFilteredClimbEntries.count)")
                            }
                            HStack {
                                Text("#Attempts")
                                Spacer()
                                Text("\(totalAttempts)")
                            }
                        }
                    }
                
                // Distribution Chart
                Section("Distribution") {
                    Picker("", selection: $selectedDistributionAxis) {
                        ForEach(DistributionAxis.allCases) { axis in
                            Text(axis.displayName(for: selectedType)).tag(axis)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if distributionData.isEmpty {
                        Text("No data available for the selected filters")
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 120)
                    } else {
                        Chart(distributionData.prefix(10)) { point in // Limit to top 10 for readability
                            BarMark(
                                x: .value("Count", point.count),
                                y: .value("Category", point.category)
                            )
                            .foregroundStyle(.green)
                            .annotation(position: .trailing) {
                                    Text(point.count, format: .number)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                        }
                        .frame(minHeight: 300)
                        .chartXAxis {
                            AxisMarks(position: .bottom)
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine()
                                AxisTick()
                                AxisValueLabel() {
                                    if let category = value.as(String.self) {
                                        Text(category)
                                            .font(.caption)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.trailing)
                                    }
                                }
                            }
                        }
                    }
                }
                // Progress Over Time Chart
                Section("Climbs Over Time") {
                    if timeSeriesData.isEmpty {
                        Text("No data available for the selected filters")
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 120)
                    } else {
                        Chart(timeSeriesData) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Count", point.count)
                            )
                            .foregroundStyle(.blue)
                            .annotation(position: .automatic) {
                                    Text(point.count, format: .number)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Count", point.count)
                            )
                            .foregroundStyle(.blue)
                        }
                        .frame(minHeight: 200)
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: max(1, timeSeriesData.count / 5))) { value in
                                AxisGridLine()
                                AxisTick()
                                AxisValueLabel(format: .dateTime.month().day())
                            }
                        }
                    }
                }
            }
            .onAppear {
                // Reset filters when view appears
                selectedStyle = ""
                selectedGrade = ""
                selectedAngle = ""
                selectedGym = ""
                customEndDate = Date()
                customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            }
        }
        .navigationTitle("STATS")
    }
    
        
}
