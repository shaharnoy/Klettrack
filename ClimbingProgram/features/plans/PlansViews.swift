//
//  PlansViews.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//

import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers
// MARK: Plans list
import UIKit

struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: Plans list
struct PlansListView: View {
    @Environment(\.modelContext) private var context
    // Be explicit with SortDescriptor to help the type checker
    @Query(sort: [SortDescriptor(\Plan.startDate, order: .reverse)]) private var plans: [Plan]

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
                    NavigationLink {
                        PlanDetailView(plan: plan)
                    } label: {
                        PlanRow(plan: plan)              // ← extracted row keeps the builder simple
                    }
                }
                .onDelete { idx in
                    idx.map { plans[$0] }.forEach(context.delete)
                    try? context.save()
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Plans")
            .toolbar {
                // Overflow menu: export / share / import
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Export (save to Files)
                        Button {
                            exportDoc = LogCSV.makeExportCSV(context: context)
                            showExporter = true
                        } label: {
                            Label("Export logs to CSV", systemImage: "square.and.arrow.up")
                        }

                        // Share (Mail / Messages / Files…)
                        Button {
                            let doc = LogCSV.makeExportCSV(context: context)
                            let fn = "climbing-log-\(Date().formatted(.dateTime.year().month().day())).csv"
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

                        // Import
                        Button {
                            showImporter = true
                        } label: {
                            Label("Import logs from CSV", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }

                // Keep your + button (unchanged)
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                }
            }

            .sheet(isPresented: $showingNew) { NewPlanSheet() }
            // Exporter
            .fileExporter(isPresented: $showExporter,
                          document: exportDoc,
                          contentType: .commaSeparatedText,
                          defaultFilename: "climbing-log-\(Date().formatted(.dateTime.year().month().day()))") { result in
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
                    importResultMessage = "Imported \(inserted) log item(s)."
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
        "\(plan.kind.rawValue) • starts \(format(plan.startDate))"
    }

    private func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
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
                    ForEach(PlanKind.allCases, id: \.self) { k in
                        Text(k.rawValue).tag(k)
                    }
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

// MARK: Plan detail - weekly/monthly views

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
                .listStyle(.insetGrouped)
            } else {
                // Monthly GRID
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
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add 4 more weeks") {
                            PlanFactory.appendWeeks(to: plan, count: 4); try? context.save()
                        }
                        Button("Add 8 more weeks") {
                            PlanFactory.appendWeeks(to: plan, count: 8); try? context.save()
                        }
                        Button("Custom…") {
                            weeksToAdd = ""; showingDupPrompt = true
                        }
                    } label: {
                        Label("Duplicate weeks", systemImage: "plus.square.on.square")
                    }
                }
            }
        }
        .alert("Add weeks", isPresented: $showingDupPrompt) {
            TextField("Number of weeks", text: $weeksToAdd)
                .keyboardType(.numberPad)
            Button("Add") {
                if let n = Int(weeksToAdd), n > 0 {
                    PlanFactory.appendWeeks(to: plan, count: n); try? context.save()
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

// MARK: Day editor

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
    @State private var saveTick = false


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
                            .controlSize(.small)                                // 👈 better size
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Show progress for \(name)")

                            // Quick Log (icon-only)
                            Button {
                                loggingExercise = ExerciseSelection(name: name)
                                inputReps = ""; inputSets = ""; inputWeight = ""; inputNotes = ""
                            } label: {
                                Image(systemName: "square.and.pencil")
                            }
                            .labelStyle(.iconOnly)
                            .controlSize(.small)                                // 👈 better size
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Log exercise \(name)")
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
                .textCase(nil)
            }
        }
        .navigationTitle(day.date.formatted(date: .abbreviated, time: .omitted))
        .listStyle(.insetGrouped)
        .onChange(of: day.type) {
            try? context.save()
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
        .sheet(isPresented: $showingPicker) {
            CatalogExercisePicker(selected: $day.chosenExercises)
        }

        // Quick Log sheet (item-based so name is instant)
        .sheet(item: $loggingExercise) { sel in
            NavigationStack {
                Form {
                    Section { Text(sel.name).font(.headline) }

                    // ✅ NICE, LABELED LOG FIELDS (icons + right-aligned)
                    Section {
                        LabeledContent {
                            TextField("e.g. 10", text: $inputReps)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Label("Reps", systemImage: "repeat")
                        }

                        LabeledContent {
                            TextField("e.g. 3", text: $inputSets)
                                .keyboardType(.numberPad)
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
                    } header: {
                        Text("LOG FIELDS").textCase(nil)
                    } footer: {
                        Text("Leave a field empty if it doesn't apply.")
                    }

                    // ✅ Live preview of what you’re about to save
                    Section("Preview") {
                        LogMetricRow(
                            reps: inputReps.isEmpty ? nil : inputReps,
                            sets: inputSets.isEmpty ? nil : inputSets,
                            weight: inputWeight.isEmpty ? nil : inputWeight
                        )
                    }

                    // Notes (kept simple)
                    Section("Notes") {
                        TextField("Notes (optional)", text: $inputNotes, axis: .vertical)
                            .lineLimit(1...3)
                    }
                }
                .listStyle(.insetGrouped)
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
                            saveTick.toggle()
                            loggingExercise = nil
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
                                LogMetricRow(
                                    reps: r.reps.map(String.init),
                                    sets: r.sets.map(String.init),
                                    weight: r.weight.map { String(format: "%.1f", $0) }
                                )
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
                        .accessibilityLabel("Progress chart")
                        .accessibilityValue("\(metric.rawValue) over time")

                    }
                }
            }
            .navigationTitle("Progress")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
    }

    // Build recent rows quickly from all sessions
    private func rows() -> [(date: Date, reps: Int?, sets: Int?, weight: Double?)] {
        let sessions = (try? context.fetch(
            FetchDescriptor<Session>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        )) ?? []

        var out: [(Date, Int?, Int?, Double?)] = []
        for s in sessions {
            for i in s.items where i.exerciseName == exerciseName {
                out.append((s.date, i.reps, i.sets, i.weightKg))
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

    private func loadSeries(from rows: [(Date, Int?, Int?, Double?)]) {
        pointsReps = rows.compactMap { (d, r, _, _) in r.map { DataPoint(date: d, value: Double($0)) } }
        pointsSets = rows.compactMap { (d, _, s, _) in s.map { DataPoint(date: d, value: Double($0)) } }
        pointsWeight = rows.compactMap { (d, _, _, w) in w.map { DataPoint(date: d, value: $0) } }
    }


    private func load() async {
        let r = rows()
        loadSeries(from: r)   // unchanged name, updated type
    }

}

// MARK: Catalog picker (Activity → TrainingType → [Combinations] → Exercises)

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
                            onDone: { dismiss() }     // close from any level
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
            .navigationTitle("Catalog")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct TypesList: View {
    @Bindable var activity: Activity
    @Binding var selected: [String]
    let tint: Color
    let onDone: () -> Void

    var body: some View {
        List {
            ForEach(activity.types) { t in
                NavigationLink {
                    if !t.combinations.isEmpty {
                        CombosList(trainingType: t, selected: $selected, tint: tint, onDone: onDone)
                    } else {
                        ExercisesList(trainingType: t, selected: $selected, tint: tint, onDone: onDone)
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
        .listStyle(.insetGrouped)
        .navigationTitle(activity.name)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", action: onDone) } }
    }
}

struct CombosList: View {
    @Bindable var trainingType: TrainingType
    @Binding var selected: [String]
    let tint: Color
    let onDone: () -> Void

    var body: some View {
        List {
            ForEach(trainingType.combinations) { combo in
                NavigationLink {
                    ComboExercisesList(combo: combo, selected: $selected, tint: tint, onDone: onDone)
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
        .listStyle(.insetGrouped)
        .navigationTitle(trainingType.name)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", action: onDone) } }
    }
}

struct ComboExercisesList: View {
    @Bindable var combo: BoulderCombination
    @Binding var selected: [String]
    let tint: Color
    let onDone: () -> Void

    var body: some View {
        List {
            ForEach(combo.exercises) { ex in
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
        .listStyle(.insetGrouped)
        .navigationTitle(combo.name)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", action: onDone) } }
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

    var body: some View {
        List {
            ForEach(trainingType.exercises) { ex in
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
        .listStyle(.insetGrouped)
        .navigationTitle(trainingType.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onDone() } }
            ToolbarItem(placement: .confirmationAction) { Button("Done") { onDone() } }
        }
    }

    private func toggle(_ name: String) {
        if let idx = selected.firstIndex(of: name) {
            selected.remove(at: idx)
        } else {
            selected.append(name)
        }
    }
}

// MARK: Compact row + MetricRow

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

    var body: some View {
        HStack(spacing: 12) {
            metric("Reps", reps)
            metric("Sets", sets)
            metric("Weight", weight.map { "\($0) kg" })
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



