//
//  PlansViews.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//

import SwiftUI
import SwiftData

// MARK: Plans list

struct PlansListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.startDate, order: .reverse) private var plans: [Plan]
    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(plans) { p in
                    NavigationLink {
                        PlanDetailView(plan: p)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(p.name).bold()
                            Text("\(p.kind.rawValue) • starts \(p.startDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    idx.map { plans[$0] }.forEach(context.delete)
                    try? context.save()
                }
            }
            .navigationTitle("Plans")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingNew) { NewPlanSheet() }
        }
    }
}

// MARK: New plan sheet

struct NewPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var kind: PlanKind = .weekly
    @State private var start = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Plan name", text: $name)
                Picker("Template", selection: $kind) {
                    ForEach(PlanKind.allCases) { Text($0.rawValue).tag($0) }
                }
                DatePicker("Start date", selection: $start, displayedComponents: .date)
            }
            .navigationTitle("New Plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let planName = finalName.isEmpty ? kind.rawValue : finalName
                        _ = PlanFactory.create(name: planName, kind: kind, start: start, in: context)
                        dismiss()
                    }
                }
            }

        }
    }
}

// MARK: Plan detail - calendar-like by week
struct PlanDetailView: View {
    @Environment(\.modelContext) private var context
    @State var plan: Plan

    @State private var viewMode: Int = 0            // 0 = Weekly, 1 = Monthly
    @State private var showingDupPrompt = false
    @State private var weeksToAdd: String = ""

    private let cal = Calendar.current

    private var groupedByWeek: [(weekStart: Date, days: [PlanDay])] {
        let days = plan.days.sorted { $0.date < $1.date }
        guard !days.isEmpty else { return [] }

        var result: [(Date, [PlanDay])] = []
        var currentWeekStart: Date = cal.dateInterval(of: .weekOfYear, for: days[0].date)!.start
        var bucket: [PlanDay] = []

        for d in days {
            let ws = cal.dateInterval(of: .weekOfYear, for: d.date)!.start
            if ws != currentWeekStart {
                result.append((currentWeekStart, bucket))
                currentWeekStart = ws
                bucket = [d]
            } else {
                bucket.append(d)
            }
        }
        if !bucket.isEmpty { result.append((currentWeekStart, bucket)) }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // View mode switch
            Picker("View", selection: $viewMode) {
                Text("Weekly").tag(0)
                Text("Monthly").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Content
            if viewMode == 0 {
                // Weekly LIST grouped by week
                List {
                    ForEach(groupedByWeek, id: \.weekStart) { group in
                        Section(header: Text("Week of \(group.weekStart.formatted(date: .abbreviated, time: .omitted))")) {
                            ForEach(group.days) { day in
                                NavigationLink {
                                    PlanDayEditor(day: day)
                                } label: {
                                    HStack {
                                        Circle().fill(day.type.color).frame(width: 10, height: 10)
                                        Text(day.date, format: .dateTime.weekday(.abbreviated).month().day())
                                        Spacer()
                                        Text(day.type.rawValue).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                // Monthly GRID (simple)
                ScrollView {
                    let days = plan.days.sorted { $0.date < $1.date }
                    let months = Dictionary(grouping: days) { cal.dateComponents([.year, .month], from: $0.date) }

                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(months.keys.sorted(by: { a, b in
                            let da = cal.date(from: a) ?? .distantPast
                            let db = cal.date(from: b) ?? .distantPast
                            return da < db
                        }), id: \.self) { comps in
                            let monthDate = cal.date(from: comps) ?? Date()
                            Text(monthDate.formatted(.dateTime.year().month()))
                                .font(.headline)
                                .padding(.horizontal)

                            let monthDays = (months[comps] ?? []).sorted { $0.date < $1.date }
                            let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

                            LazyVGrid(columns: cols, spacing: 6) {
                                ForEach(monthDays) { day in
                                    NavigationLink {
                                        PlanDayEditor(day: day)
                                    } label: {
                                        VStack(spacing: 4) {
                                            Text("\(cal.component(.day, from: day.date))")
                                                .font(.caption)
                                            Circle().fill(day.type.color).frame(width: 8, height: 8)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(6)
                                        .background(.thinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .navigationTitle(plan.name)
        .toolbar {
            if plan.kind == .weekly {
                Menu {
                    Button("Add 4 more weeks") {
                        PlanFactory.appendWeeks(to: plan, count: 4)
                        try? context.save()
                    }
                    Button("Add 8 more weeks") {
                        PlanFactory.appendWeeks(to: plan, count: 8)
                        try? context.save()
                    }
                    Button("Custom…") {
                        weeksToAdd = ""
                        showingDupPrompt = true
                    }
                } label: {
                    Label("Duplicate weeks", systemImage: "plus.square.on.square")
                }
            }
        }
        .alert("Add weeks", isPresented: $showingDupPrompt) {
            TextField("Number of weeks", text: $weeksToAdd)
                .keyboardType(.numberPad)
            Button("Add") {
                if let n = Int(weeksToAdd), n > 0 {
                    PlanFactory.appendWeeks(to: plan, count: n)
                    try? context.save()
                }
                weeksToAdd = ""
            }
            Button("Cancel", role: .cancel) { weeksToAdd = "" }
        } message: {
            Text("Enter how many weeks to add to this weekly plan.")
        }
    }
}



// MARK: Day editor - pick day type & activities from catalog

// MARK: Catalog picker (drills into your Activity → Type → Exercises)

struct CatalogExercisePicker: View {
    @Binding var selected: [String]
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Activity.name) private var activities: [Activity]

    var body: some View {
        NavigationStack {
            List {
                ForEach(activities) { activity in
                    NavigationLink(activity.name) {
                        TypesList(activity: activity, selected: $selected)
                    }
                }
            }
            .navigationTitle("Catalog")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct TypesList: View {
    let activity: Activity
    @Binding var selected: [String]

    var body: some View {
        List {
            ForEach(activity.types) { t in
                NavigationLink(t.name) {
                    ExercisesList(trainingType: t, selected: $selected)
                }
            }
        }
        .navigationTitle(activity.name)
    }
}

struct ExercisesList: View {
    let trainingType: TrainingType
    @Binding var selected: [String]

    var body: some View {
        List {
            ForEach(trainingType.exercises) { ex in
                Button {
                    if !selected.contains(ex.name) { selected.append(ex.name) }
                } label: {
                    HStack {
                        Text(ex.name)
                        Spacer()
                        if selected.contains(ex.name) { Image(systemName: "checkmark") }
                    }
                }
            }
        }
        .navigationTitle(trainingType.name)
    }
}
