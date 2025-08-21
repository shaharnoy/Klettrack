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
    // Sessions
    @Query(sort: \Session.date) private var allSessions: [Session]

    // Plan filter
    @Query(sort: \Plan.startDate) private var plansForFilter: [Plan]
    @State private var selectedPlanID: UUID? = nil

    // Metric + Exercise pickers
    enum Metric: String, CaseIterable, Identifiable { case reps = "Reps", sets = "Sets", weight = "Weight (kg)"; var id: String { rawValue } }
    @State private var selectedMetric: Metric = .reps
    @State private var selectedExercise: String = ""  // empty = all exercises

    // Filter sessions by plan’s date window
    var filteredSessions: [Session] {
        guard let pid = selectedPlanID,
              let plan = plansForFilter.first(where: { $0.id == pid }) else { return allSessions }
        let dates = plan.days.map { $0.date }
        guard let minD = dates.min(), let maxD = dates.max() else { return allSessions }
        return allSessions.filter { $0.date >= minD && $0.date <= maxD }
    }

    var totalExercises: Int { filteredSessions.flatMap { $0.items }.count }

    // Unique exercise names present in logs (for picker)
    var loggedExerciseNames: [String] {
        let names = filteredSessions.flatMap { $0.items.map { $0.exerciseName } }
        return Array(Set(names)).sorted()
    }

    // Data points for chart based on selection
    struct DataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let label: String
    }

    var points: [DataPoint] {
        filteredSessions.flatMap { s in
            s.items.compactMap { item -> DataPoint? in
                // filter by chosen exercise (if selected)
                if !selectedExercise.isEmpty, item.exerciseName != selectedExercise { return nil }
                switch selectedMetric {
                case .reps:
                    guard let v = item.reps else { return nil }
                    return DataPoint(date: s.date, value: Double(v), label: item.exerciseName)
                case .sets:
                    guard let v = item.sets else { return nil }
                    return DataPoint(date: s.date, value: Double(v), label: item.exerciseName)
                case .weight:
                    guard let v = item.weightKg else { return nil }
                    return DataPoint(date: s.date, value: v, label: item.exerciseName)
                }
            }
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                // Filters
                Section("Filter") {
                    Picker("Plan", selection: $selectedPlanID) {
                        Text("All sessions").tag(UUID?.none)
                        ForEach(plansForFilter) { p in
                            Text(p.name).tag(UUID?.some(p.id))
                        }
                    }
                    Picker("Metric", selection: $selectedMetric) {
                        ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Exercise", selection: $selectedExercise) {
                        Text("All exercises").tag("")
                        ForEach(loggedExerciseNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }

                // Totals
                Section("Totals") {
                    HStack { Text("Sessions"); Spacer(); Text("\(filteredSessions.count)") }
                    HStack { Text("Total exercises"); Spacer(); Text("\(totalExercises)") }
                }

                // Chart
                Section("Progress over time") {
                    if points.isEmpty {
                        Text("No data for the chosen filter yet. Log some sets!")
                            .foregroundStyle(.secondary)
                    } else {
                        Chart(points) { p in
                            LineMark(
                                x: .value("Date", p.date),
                                y: .value(selectedMetric.rawValue, p.value)
                            )
                            PointMark(
                                x: .value("Date", p.date),
                                y: .value(selectedMetric.rawValue, p.value)
                            )
                        }
                        .frame(minHeight: 240)
                    }
                }
            }
            .navigationTitle("Progress")
        }
    }
}
