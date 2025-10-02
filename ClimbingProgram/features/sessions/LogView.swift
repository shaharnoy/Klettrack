//
//  LogView.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit // uses ShareSheet from your Plans module (or provide a local one)

// MARK: - Log (list of sessions)

struct LogView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.isDataReady) private var isDataReady
    @Query(sort: [SortDescriptor(\Session.date, order: .reverse)]) private var sessions: [Session]
    @Query(sort: [SortDescriptor(\ClimbEntry.dateLogged, order: .reverse)]) private var climbEntries: [ClimbEntry]

    // New session
    @State private var showingNew = false

    // Export
    @State private var exportDoc: LogCSVDocument? = nil
    @State private var showExporter = false

    // Import (async with progress)
    @State private var showImporter = false
    @State private var importing = false
    @State private var importProgress: Double = 0

    // Share (use Identifiable payload)
    struct SharePayload: Identifiable { let id = UUID(); let url: URL }
    @State private var sharePayload: SharePayload? = nil

    // Alerts
    @State private var resultMessage: String? = nil

    var body: some View {
        NavigationStack {
            CombinedLogList(sessions: sessions, climbEntries: climbEntries) // <- updated to show both
                .toolbar { trailingToolbar }
                .sheet(isPresented: $showingNew) { NewSessionSheet() }
                .navigationTitle("LOG")
                .navigationBarTitleDisplayMode(.large)
        }
        // Exporter
        .fileExporter(
            isPresented: $showExporter,
            document: exportDoc,
            contentType: .commaSeparatedText,
            defaultFilename: "climbing-log-\(Date().formatted(.dateTime.year().month().day()))"
        ) { result in
            switch result {
            case .success: resultMessage = "CSV exported."
            case .failure(let err): resultMessage = "Export failed: \(err.localizedDescription)"
            }
        }
        // Importer (async)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: false
        ) { res in
            handleImportResult(res)
        }
        // Share
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: [payload.url]) {
                try? FileManager.default.removeItem(at: payload.url) // cleanup
            }
            .presentationDetents([.medium])
        }
        // Result alert
        .alert(resultMessage ?? "", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) { Button("OK", role: .cancel) {} }
        // Progress overlay
        .overlay { if importing { ImportProgressOverlay(progress: importProgress) } }
    }

    // MARK: - Toolbar (extracted to keep body small)

    @ToolbarContentBuilder
    private var trailingToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                exportButton
                shareButton
                importButton
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

    private var exportButton: some View {
        Button {
            exportDoc = LogCSV.makeExportCSV(context: context)
            showExporter = true
        } label: {
            Label("Export logs to CSV", systemImage: "square.and.arrow.up")
        }
    }

    private var shareButton: some View {
        Button { prepareShare() } label: {
            Label("Share logs (CSV)…", systemImage: "square.and.arrow.up.on.square")
        }
    }

    private var importButton: some View {
        Button { showImporter = true } label: {
            Label("Import logs from CSV", systemImage: "square.and.arrow.down")
        }
    }

    // MARK: - Actions

    private func prepareShare() {
        let doc = LogCSV.makeExportCSV(context: context)
        let fn = "climbing-log-\(Date().formatted(.dateTime.year().month().day())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fn)
        do {
            try doc.csv.write(to: url, atomically: true, encoding: .utf8)
            guard FileManager.default.fileExists(atPath: url.path) else {
                resultMessage = "Share failed: file not found."
                return
            }
            sharePayload = SharePayload(url: url)
        } catch {
            resultMessage = "Share prep failed: \(error.localizedDescription)"
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let df = ISO8601DateFormatter(); df.formatOptions = [.withFullDate]
            let tag = "import:\(df.string(from: Date()))"

            importing = true
            importProgress = 0

            Task {
                do {
                    let count = try await LogCSV.importCSVAsync(
                        from: url,
                        into: context,
                        tag: tag,
                        dedupe: true,
                        progress: { p in
                            Task { @MainActor in
                                importProgress = p
                            }
                        }
                    )
                    await MainActor.run {
                        importing = false
                        resultMessage = "Imported \(count) log item(s)."
                    }
                } catch {
                    await MainActor.run {
                        importing = false
                        resultMessage = "Import failed: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            resultMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Subviews kept tiny (helps the type-checker)

private struct SessionsList: View {
    @Environment(\.modelContext) private var context
    let sessions: [Session]

    var body: some View {
        List {
            ForEach(sessions) { s in
                NavigationLink { SessionDetailView(session: s) } label: {
                    SessionRow(session: s)
                }
            }
            .onDelete(perform: delete)
        }
        .listStyle(.insetGrouped)
    }

    private func delete(_ offsets: IndexSet) {
        for i in offsets { context.delete(sessions[i]) }
        try? context.save()
    }
}

private struct SessionRow: View {
    let session: Session
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.date.formatted(date: .abbreviated, time: .omitted))
                .font(.headline)
            Text("\(session.items.count) exercise\(session.items.count == 1 ? "" : "s")")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Session item row
struct SessionItemRow: View {
    @Bindable var item: SessionItem
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.exerciseName).font(.headline)
                if let planName = item.planName {
                    Spacer()
                    Text("Plan: \(planName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 16) {
                if let r = item.reps { Text(String(format: "reps: %.1f", r)) }
                if let s = item.sets { Text(String(format: "sets: %.1f", s)) }
                if let w = item.weightKg { Text(String(format: "Wt: %.1f kg", w)) }
                if let g = item.grade { Text("Grade: \(g)") }
            }
            .font(.footnote.monospacedDigit())
            if let n = item.notes, !n.isEmpty {
                Text(n).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Add item to a session
struct AddSessionItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var session: Session

    @Query(sort: [SortDescriptor(\Exercise.name)]) private var allExercises: [Exercise]
    @Query(sort: [SortDescriptor(\Plan.startDate)]) private var plans: [Plan]

    @State private var showingCatalogPicker = false
    @State private var selectedCatalogName: String? = nil
    @State private var selectedPlan: Plan? = nil
    @State private var inputReps: String = ""
    @State private var inputSets: String = ""
    @State private var inputWeight: String = ""
    @State private var inputNotes: String = ""
    @State private var inputGrade: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Button {
                    showingCatalogPicker = true
                } label: {
                    HStack {
                        Text("Exercise")
                        Spacer()
                        if let name = selectedCatalogName, !name.isEmpty {
                            Text(name).foregroundStyle(.secondary)
                        } else {
                            Text("Choose…").foregroundStyle(.secondary)
                        }
                    }
                }
                .sheet(isPresented: $showingCatalogPicker) {
                    SingleCatalogExercisePicker(selected: $selectedCatalogName)
                }
                
                // Plan selection
                Picker("Plan (optional)", selection: $selectedPlan) {
                    Text("No Plan").tag(Optional<Plan>.none)
                    ForEach(plans) { plan in
                        Text(plan.name).tag(Optional(plan))
                    }
                }
                
                Section("Details") {
                    TextField("Reps", text: $inputReps).keyboardType(.decimalPad)
                    TextField("Sets", text: $inputSets).keyboardType(.decimalPad)
                    TextField("Weight (kg)", text: $inputWeight).keyboardType(.decimalPad)
                    TextField("Grade (e.g., 6a+)", text: $inputGrade)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Notes", text: $inputNotes)
                }
            }
            .navigationTitle("Add Exercise")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let selectedName = selectedCatalogName, !selectedName.isEmpty else { return }
                        let reps = Double(inputReps.replacingOccurrences(of: ",", with: ".")
                            .trimmingCharacters(in: .whitespaces))
                        let sets = Double(inputSets.replacingOccurrences(of: ",", with: ".")
                            .trimmingCharacters(in: .whitespaces))
                        let weight = Double(inputWeight.replacingOccurrences(of: ",", with: ".")
                            .trimmingCharacters(in: .whitespaces))
                        let grade = inputGrade.trimmingCharacters(in: .whitespaces).isEmpty ? nil : inputGrade.trimmingCharacters(in: .whitespaces)
                        let item = SessionItem(
                            exerciseName: selectedName,
                            planSourceId: selectedPlan?.id,
                            planName: selectedPlan?.name,
                            reps: reps,
                            sets: sets,
                            weightKg: weight,
                            grade: grade,
                            notes: inputNotes.isEmpty ? nil : inputNotes
                        )
                        session.items.append(item)
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Progress overlay

private struct ImportProgressOverlay: View {
    let progress: Double
    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 220)
            Text("Importing… \(Int(progress * 100))%")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - New session

struct NewSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            .navigationTitle("New Session")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        context.insert(Session(date: date))
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Session detail

struct SessionDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.isDataReady) private var isDataReady
    @Bindable var session: Session
    @State private var showingAddItem = false
    @State private var editingItem: SessionItem? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("Exercises") {
                    ForEach(session.items) { item in
                        SessionItemRow(item: item)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    guard isDataReady else { return }
                                    if let index = session.items.firstIndex(where: { $0.id == item.id }) {
                                        session.items.remove(at: index)
                                        try? context.save()
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                
                                NavigationLink {
                                    EditSessionItemView(item: item)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard isDataReady else { return }
                        showingAddItem = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!isDataReady)
                }
            }
            .sheet(isPresented: $showingAddItem) {
                AddSessionItemSheet(session: session)
            }
        }
    }
}

// Replace sheet-based editing with NavigationLink-based editing
struct EditSessionItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.isDataReady) private var isDataReady
    @Bindable var item: SessionItem

    @Query(sort: [SortDescriptor(\Plan.startDate)]) private var plans: [Plan]
    @State private var showingCatalogPicker = false
    @State private var selectedCatalogName: String? = nil
    @State private var selectedPlan: Plan? = nil
    @State private var inputReps: String = ""
    @State private var inputSets: String = ""
    @State private var inputWeight: String = ""
    @State private var inputNotes: String = ""
    @State private var inputGrade: String = ""
    @State private var isInitialized = false

    var body: some View {
        if !isDataReady || !isInitialized {
            VStack(spacing: 16) {
                ProgressView()
                Text("Loading...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await initializeView()
            }
        } else {
            Form {
                Button {
                    showingCatalogPicker = true
                } label: {
                    HStack {
                        Text("Exercise")
                        Spacer()
                        if let name = selectedCatalogName, !name.isEmpty {
                            Text(name).foregroundStyle(.secondary)
                        } else {
                            Text("Choose…").foregroundStyle(.secondary)
                        }
                    }
                }
                .sheet(isPresented: $showingCatalogPicker) {
                    SingleCatalogExercisePicker(selected: $selectedCatalogName)
                }
                
                // Plan selection
                Picker("Plan (optional)", selection: $selectedPlan) {
                    Text("No Plan").tag(Optional<Plan>.none)
                    ForEach(plans) { plan in
                        Text(plan.name).tag(Optional(plan))
                    }
                }
                
                Section("Details") {
                    TextField("Reps", text: $inputReps).keyboardType(.decimalPad)
                    TextField("Sets", text: $inputSets).keyboardType(.decimalPad)
                    TextField("Weight (kg)", text: $inputWeight).keyboardType(.decimalPad)
                    TextField("Grade (e.g., 6a+)", text: $inputGrade)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Notes", text: $inputNotes)
                }
            }
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        guard let selectedName = selectedCatalogName, !selectedName.isEmpty else { return }
                        item.exerciseName = selectedName
                        item.planSourceId = selectedPlan?.id
                        item.planName = selectedPlan?.name
                        item.reps = Double(inputReps.replacingOccurrences(of: ",", with: ".")
                            .trimmingCharacters(in: .whitespaces))
                        item.sets = Double(inputSets.replacingOccurrences(of: ",", with: ".")
                            .trimmingCharacters(in: .whitespaces))
                        item.weightKg = Double(inputWeight.replacingOccurrences(of: ",", with: ".")
                            .trimmingCharacters(in: .whitespaces))
                        item.grade = inputGrade.trimmingCharacters(in: .whitespaces).isEmpty ? nil : inputGrade.trimmingCharacters(in: .whitespaces)
                        item.notes = inputNotes.isEmpty ? nil : inputNotes
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
    
    @MainActor
    private func initializeView() async {
        // Wait for data to be ready
        while !isDataReady {
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        }
        
        // Additional small delay to ensure context is stable
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Initialize form fields
        selectedCatalogName = item.exerciseName
        // Find the plan if one exists
        if let planId = item.planSourceId {
            selectedPlan = plans.first { $0.id == planId }
        }
        inputReps = item.reps.map { String($0) } ?? ""
        inputSets = item.sets.map { String($0) } ?? ""
        inputWeight = item.weightKg.map { String($0) } ?? ""
        inputGrade = item.grade ?? ""
        inputNotes = item.notes ?? ""
        
        isInitialized = true
    }
}

// Single-selection wrapper for CatalogExercisePicker
struct SingleCatalogExercisePicker: View {
    @Binding var selected: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isDataReady) private var isDataReady
    @State private var internalSelection: [String] = []

    var body: some View {
        CatalogExercisePicker(selected: Binding(
            get: { internalSelection },
            set: { newValue in
                // Only keep the last selected item
                internalSelection = newValue.suffix(1)
                selected = internalSelection.first
                dismiss()
            }
        ))
        .environment(\.isDataReady, isDataReady)
        .onAppear {
            if let selected = selected {
                internalSelection = [selected]
            }
        }
    }
}

// MARK: - Combined Log List (Sessions + Climb Entries)

private struct CombinedLogList: View {
    @Environment(\.modelContext) private var context
    let sessions: [Session]
    let climbEntries: [ClimbEntry]
    
    // Group data by date
    private var groupedData: [Date: (exercises: Int, climbs: Int, session: Session?, climbEntries: [ClimbEntry])] {
        var grouped: [Date: (exercises: Int, climbs: Int, session: Session?, climbEntries: [ClimbEntry])] = [:]
        
        // Add sessions (exercises)
        for session in sessions {
            let dateKey = Calendar.current.startOfDay(for: session.date)
            if grouped[dateKey] == nil {
                grouped[dateKey] = (exercises: 0, climbs: 0, session: nil, climbEntries: [])
            }
            grouped[dateKey]?.exercises = session.items.count
            grouped[dateKey]?.session = session
        }
        
        // Add climb entries
        for climb in climbEntries {
            let dateKey = Calendar.current.startOfDay(for: climb.dateLogged)
            if grouped[dateKey] == nil {
                grouped[dateKey] = (exercises: 0, climbs: 0, session: nil, climbEntries: [])
            }
            grouped[dateKey]?.climbs += 1
            grouped[dateKey]?.climbEntries.append(climb)
        }
        
        return grouped
    }
    
    private var sortedDates: [Date] {
        groupedData.keys.sorted(by: >)
    }
    
    var body: some View {
        List {
            ForEach(sortedDates, id: \.self) { date in
                let dayData = groupedData[date]!
                NavigationLink {
                    CombinedDayDetailView(
                        date: date,
                        session: dayData.session,
                        climbEntries: dayData.climbEntries
                    )
                } label: {
                    CombinedDayRow(
                        date: date,
                        exerciseCount: dayData.exercises,
                        climbCount: dayData.climbs
                    )
                }
            }
            .onDelete(perform: delete)
        }
        .listStyle(.insetGrouped)
    }
    
    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            let date = sortedDates[index]
            let dayData = groupedData[date]!
            
            // Delete session if exists
            if let session = dayData.session {
                context.delete(session)
            }
            
            // Delete climb entries
            for climbEntry in dayData.climbEntries {
                context.delete(climbEntry)
            }
        }
        try? context.save()
    }
}

private struct CombinedDayRow: View {
    let date: Date
    let exerciseCount: Int
    let climbCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.headline)
                
                Spacer()
                
                // Color tags for activity types
                HStack(spacing: 4) {
                    if exerciseCount > 0 {
                        Text("exercise")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                    
                    if climbCount > 0 {
                        Text("climb")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                }
            }
            
            HStack(spacing: 12) {
                if exerciseCount > 0 {
                    Text("\(exerciseCount) exercise\(exerciseCount == 1 ? "" : "s")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                if climbCount > 0 {
                    Text("\(climbCount) climb\(climbCount == 1 ? "" : "s")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Combined Day Detail View

private struct CombinedDayDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.isDataReady) private var isDataReady
    let date: Date
    let session: Session?
    let climbEntries: [ClimbEntry]
    
    @State private var showingAddItem = false
    @State private var showingAddClimb = false
    
    var body: some View {
        List {
            // Exercises section
            if let session = session, !session.items.isEmpty {
                Section("Exercises") {
                    ForEach(session.items) { item in
                        SessionItemRow(item: item)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    guard isDataReady else { return }
                                    if let index = session.items.firstIndex(where: { $0.id == item.id }) {
                                        session.items.remove(at: index)
                                        try? context.save()
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                
                                NavigationLink {
                                    EditSessionItemView(item: item)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                    }
                }
            }
            
            // Climbs section
            if !climbEntries.isEmpty {
                Section("Climbs") {
                    ForEach(climbEntries.sorted(by: { $0.dateLogged > $1.dateLogged })) { climb in
                        ClimbEntryRow(climb: climb)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    guard isDataReady else { return }
                                    context.delete(climb)
                                    try? context.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            
            // Empty state
            if (session?.items.isEmpty ?? true) && climbEntries.isEmpty {
                Section {
                    Text("No activities logged for this day")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: { addExercise() }) {
                        Label("Add Exercise", systemImage: "dumbbell")
                    }
                    
                    Button(action: { showingAddClimb = true }) {
                        Label("Add Climb", systemImage: "figure.climbing")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!isDataReady)
            }
        }
        .sheet(isPresented: $showingAddItem) {
            if let session = session {
                AddSessionItemSheet(session: session)
            }
        }
        .sheet(isPresented: $showingAddClimb) {
            AddClimbView()
        }
    }
    
    private func addExercise() {
        guard isDataReady else { return }
        
        // Create session if it doesn't exist
        if session == nil {
            let newSession = Session(date: date)
            context.insert(newSession)
            try? context.save()
        }
        
        showingAddItem = true
    }
}

// MARK: - Climb Entry Row

private struct ClimbEntryRow: View {
    let climb: ClimbEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Climb type indicator
                Text(climb.climbType.displayName)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(climb.climbType == .boulder ? Color.orange : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                
                // Grade
                Text(climb.grade)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // WIP indicator
                if climb.isWorkInProgress {
                    Text("WIP")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .cornerRadius(4)
                }
            }
            
            HStack {
                // Style
                Text(climb.style)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let angle = climb.angleDegrees {
                    Text("• \(angle)°")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let attempts = climb.attempts, !attempts.isEmpty {
                    Text("• \(attempts) attempts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                // Gym
                Text(climb.gym)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            if let notes = climb.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
