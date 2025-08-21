//
//  PlansViews.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//

import SwiftUI
import SwiftData
import Charts

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

private struct ExerciseSelection: Identifiable, Equatable {
    let name: String
    var id: String { name }
}

struct PlanDayEditor: View {
    @Environment(\.modelContext) private var context
    @State var day: PlanDay

    // Catalog picker
    @State private var showingPicker = false

    // Quick Log
    @State private var loggingExercise: ExerciseSelection? = nil
    @State private var inputReps: String = ""
    @State private var inputSets: String = ""
    @State private var inputWeight: String = ""
    @State private var inputNotes: String = ""

    // Quick Progress
    @State private var progressExercise: ExerciseSelection? = nil

    var body: some View {
        Form {
            Picker("Day type", selection: $day.type) {
                ForEach(DayType.allCases) { Text($0.rawValue).tag($0) }
            }

            Section("Chosen activities") {
                if day.chosenExercises.isEmpty {
                    Text("No activities yet").foregroundStyle(.secondary)
                } else {
                    ForEach(day.chosenExercises, id: \.self) { name in
                        HStack(spacing: 10) {
                            Text(name)
                                .lineLimit(2)
                            Spacer()
                            // Quick Progress (icon-only)
                            Button {
                                progressExercise = ExerciseSelection(name: name)
                            } label: {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.bordered)
                            // Quick Log (icon-only)
                            Button {
                                loggingExercise = ExerciseSelection(name: name)
                                inputReps = ""; inputSets = ""; inputWeight = ""; inputNotes = ""
                            } label: {
                                Image(systemName: "square.and.pencil")
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.bordered)
                        }
                    }
                    .onMove { indices, newOffset in
                        day.chosenExercises.move(fromOffsets: indices, toOffset: newOffset)
                        try? context.save()
                    }
                    .onDelete { idx in
                        day.chosenExercises.remove(atOffsets: idx)
                        try? context.save()
                    }
                }

                Button {
                    showingPicker = true
                } label: {
                    Label("Add from Catalog", systemImage: "plus")
                }
            }
        }
        .navigationTitle(day.date.formatted(date: .abbreviated, time: .omitted))
        .onChange(of: day.type) { _ in try? context.save() }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
        .sheet(isPresented: $showingPicker) { CatalogExercisePicker(selected: $day.chosenExercises) }

        // Quick Log sheet (item-based so name is instant)
        .sheet(item: $loggingExercise) { sel in
            NavigationStack {
                Form {
                    Section { Text(sel.name).font(.headline) }
                    Section("Details") {
                        TextField("Reps (integer)", text: $inputReps).keyboardType(.numberPad)
                        TextField("Sets (integer)", text: $inputSets).keyboardType(.numberPad)
                        TextField("Weight (kg)", text: $inputWeight).keyboardType(.decimalPad)
                        TextField("Notes", text: $inputNotes)
                    }
                }
                .navigationTitle("Quick Log")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { loggingExercise = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let reps = Int(inputReps.trimmingCharacters(in: .whitespaces))
                            let sets = Int(inputSets.trimmingCharacters(in: .whitespaces))
                            let weight = Double(inputWeight.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))

                            // find/create session for this day
                            let startOfDay = Calendar.current.startOfDay(for: day.date)
                            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
                            let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.date >= startOfDay && $0.date < endOfDay })
                            let existing = (try? context.fetch(descriptor)) ?? []
                            let session = existing.first ?? {
                                let s = Session(date: day.date)
                                context.insert(s)
                                return s
                            }()

                            session.items.append(SessionItem(
                                exerciseName: sel.name,
                                reps: reps,
                                sets: sets,
                                weightKg: weight,
                                notes: inputNotes.isEmpty ? nil : inputNotes
                            ))
                            try? context.save()
                            loggingExercise = nil
                        }
                    }
                }
            }
        }

        // Quick Progress sheet
        .sheet(item: $progressExercise) { sel in
            QuickExerciseProgress(exerciseName: sel.name)
        }
    }
}

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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(exerciseName).font(.headline)
                }
                Section("Recent logs") {
                    let recent = rows().suffix(10)
                    if recent.isEmpty {
                        Text("No logs yet for this exercise").foregroundStyle(.secondary)
                    } else {
                        ForEach(recent.reversed(), id: \.date) { r in
                            HStack {
                                Text(r.date.formatted(date: .abbreviated, time: .omitted))
                                Spacer()
                                Text(r.summary)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Chart") {
                    Picker("Metric", selection: $metric) {
                        ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    let pts = series(for: metric)
                    if pts.isEmpty {
                        Text("No numeric data for \(metric.rawValue) yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        Chart(pts) { p in
                            LineMark(x: .value("Date", p.date), y: .value(metric.rawValue, p.value))
                            PointMark(x: .value("Date", p.date), y: .value(metric.rawValue, p.value))
                        }
                        .frame(minHeight: 220)
                    }
                }
            }
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    // Build recent rows quickly from all sessions
    private func rows() -> [(date: Date, summary: String, reps: Int?, sets: Int?, weight: Double?)] {
        let sessions = (try? context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        var out: [(Date, String, Int?, Int?, Double?)] = []
        for s in sessions {
            for i in s.items where i.exerciseName == exerciseName {
                let summary = [
                    i.reps.map { "R:\($0)" },
                    i.sets.map { "S:\($0)" },
                    i.weightKg.map { String(format: "W:%.1fkg", $0) }
                ].compactMap { $0 }.joined(separator: " · ")
                out.append((s.date, summary, i.reps, i.sets, i.weightKg))
            }
        }
        return out.sorted { $0.0 < $1.0 }
    }

    private func series(for metric: Metric) -> [DataPoint] {
        switch metric {
        case .reps:   return pointsReps
        case .sets:   return pointsSets
        case .weight: return pointsWeight
        }
    }

    private func loadSeries(from rows: [(Date, String, Int?, Int?, Double?)]) {
        pointsReps = rows.compactMap { (d, _, r, _, _) in
            r.map { DataPoint(date: d, value: Double($0)) }
        }
        pointsSets = rows.compactMap { (d, _, _, s, _) in
            s.map { DataPoint(date: d, value: Double($0)) }
        }
        pointsWeight = rows.compactMap { (d, _, _, _, w) in
            w.map { DataPoint(date: d, value: $0) }   // <- use $0 (unwrapped Double)
        }
    }


    private func load() async {
        let r = rows()
        loadSeries(from: r)
    }
}

// MARK: Catalog picker (Activity → TrainingType → Exercises)
// Done anywhere closes the whole sheet (calls the root dismiss via onDone).

struct CatalogExercisePicker: View {
    @Binding var selected: [String]
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Activity.name) private var activities: [Activity]

    var body: some View {
        NavigationStack {
            List {
                ForEach(activities) { activity in
                    NavigationLink {
                        TypesList(
                            activity: activity,
                            selected: $selected,
                            tint: activity.hue.color,
                            onDone: { dismiss() }     // ✅ root dismiss captured here
                        )
                    } label: {
                        CatalogMiniCard(
                            title: activity.name,
                            subtitle: "\(activity.types.count) types",
                            tint: activity.hue.color
                        ) {
                            Text("Choose a type")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Catalog")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }   // ✅ closes entire sheet
                }
            }
        }
    }
}

struct TypesList: View {
    let activity: Activity
    @Binding var selected: [String]
    let tint: Color
    let onDone: () -> Void

    var body: some View {
        List {
            ForEach(activity.types) { t in
                NavigationLink {
                    ExercisesList(
                        trainingType: t,
                        selected: $selected,
                        tint: tint,
                        onDone: onDone            // ✅ same root dismiss closure
                    )
                } label: {
                    CatalogMiniCard(
                        title: t.name,
                        subtitle: t.area,
                        tint: tint
                    ) {
                        Text("Pick exercises")
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(activity.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onDone() }     // ✅ closes sheet from here
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onDone() }       // ✅ closes sheet from here
            }
        }
    }
}

struct ExercisesList: View {
    let trainingType: TrainingType
    @Binding var selected: [String]
    let tint: Color
    let onDone: () -> Void

    var body: some View {
        List {
            ForEach(trainingType.exercises) { ex in
                Button {
                    if !selected.contains(ex.name) { selected.append(ex.name) }
                } label: {
                    HStack(spacing: 10) {
                        CatalogMiniCard(
                            title: ex.name,
                            subtitle: ex.repsText ?? ex.restText,
                            tint: tint
                        ) {
                            if let s = ex.setsText, !s.isEmpty {
                                Text("Sets: \(s)")
                            }
                        }
                        Spacer(minLength: 4)
                        if selected.contains(ex.name) {
                            Image(systemName: "checkmark.circle.fill")
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(trainingType.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onDone() }     // ✅ closes sheet from here
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onDone() }       // ✅ closes sheet from here
            }
        }
    }
}
