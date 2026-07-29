//
//  LogView.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

// MARK: - Session helpers (deletion)

extension Session {
    @MainActor
    func removeItem(_ item: SessionItem, in context: ModelContext, deleteEmptySession: Bool = true) throws {
        let foundIdx = items.firstIndex(where: { $0.id == item.id })
        if let idx = foundIdx {
            items.remove(at: idx)
        } else {
            // Fallback: if the item isn't in this session array (shouldn't happen), try deleting it directly
            context.delete(item)
        }

        if deleteEmptySession && items.isEmpty {
            context.delete(self)
        }

        do {
            try context.save()
        } catch {
            throw error
        }
    }
}

private struct ExerciseSelection: Identifiable, Equatable {
    let name: String
    var id: String { name }
}

// MARK: - Log (list of sessions)

struct LogView: View {
    private enum ModalRoute: Hashable {
        case newSession
        case exportCSV
        case importCSV
    }

    @Environment(\.modelContext) private var context
    @Environment(\.isDataReady) private var isDataReady
    @Query(sort: [SortDescriptor(\Session.date, order: .reverse)]) private var sessions: [Session]
    @Query(sort: [SortDescriptor(\ClimbEntry.dateLogged, order: .reverse)]) private var climbEntries: [ClimbEntry]
    @Query(sort: [SortDescriptor(\DayLog.date, order: .reverse)]) private var dayLogs: [DayLog]

    @State private var modalRoute: ModalRoute?
    @State private var navigationPath = NavigationPath()


    // Export
    @State private var exportDoc: LogCSVDocument? = nil

    // Import (async with progress)
    @State private var importing = false
    @State private var importProgress: Double = 0

    // Share (use Identifiable payload)
    struct SharePayload: Identifiable { let id = UUID(); let url: URL }
    @State private var sharePayload: SharePayload? = nil

    // Alerts
    @State private var resultMessage: String? = nil

    var body: some View {
            NavigationStack(path: $navigationPath) {
                CombinedLogList(sessions: sessions, climbEntries: climbEntries, dayLogs: dayLogs)
                    .toolbar { trailingToolbar }
                    .sheet(isPresented: newSessionPresentedBinding) {
                        NewSessionSheet { createdDay in
                            navigationPath.append(createdDay)
                        }
                    }
                    .navigationTitle("LOG")
                    .navigationBarTitleDisplayMode(.large)
                    .navigationDestination(for: Date.self) { day in
                        let dayKey = Calendar.current.startOfDay(for: day)

                        let sessionForDay = sessions.first(where: {
                            Calendar.current.startOfDay(for: $0.date) == dayKey
                        })

                        let climbsForDay = climbEntries.filter {
                            Calendar.current.startOfDay(for: $0.dateLogged) == dayKey
                        }
                        let dayLogForDay = dayLogs.first {
                            Calendar.current.startOfDay(for: $0.date) == dayKey
                        }

                        CombinedDayDetailView(
                            date: dayKey,
                            session: sessionForDay,
                            climbEntries: climbsForDay,
                            dayLog: dayLogForDay
                        )
                    }
            }
        // Exporter
        .fileExporter(
            isPresented: exportPresentedBinding,
            document: exportDoc,
            contentType: .commaSeparatedText,
            defaultFilename: "klettrack-log-\(Date().formatted(.dateTime.year().month().day()))"
        ) { result in
            switch result {
            case .success: resultMessage = "CSV exported."
            case .failure(let err): resultMessage = "Export failed: \(err.localizedDescription)"
            }
        }
        // Importer (async)
        .fileImporter(
            isPresented: importPresentedBinding,
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

    private var newSessionPresentedBinding: Binding<Bool> {
        Binding(
            get: { modalRoute == .newSession },
            set: { if !$0 { modalRoute = nil } }
        )
    }

    private var exportPresentedBinding: Binding<Bool> {
        Binding(
            get: { modalRoute == .exportCSV },
            set: { if !$0 { modalRoute = nil } }
        )
    }

    private var importPresentedBinding: Binding<Bool> {
        Binding(
            get: { modalRoute == .importCSV },
            set: { if !$0 { modalRoute = nil } }
        )
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
                modalRoute = .newSession
            } label: {
                Image(systemName: "plus")
            }
            .disabled(!isDataReady)
        }
    }

    private var exportButton: some View {
        Button {
            exportDoc = LogCSV.makeExportCSV(context: context)
            modalRoute = .exportCSV
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
        Button { modalRoute = .importCSV } label: {
            Label("Import logs from CSV", systemImage: "square.and.arrow.down")
        }
    }

    // MARK: - Actions

    private func prepareShare() {
        let doc = LogCSV.makeExportCSV(context: context)
        let fn = "klettrack-log-\(Date().formatted(.dateTime.year().month().day())).csv"
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
                        resultMessage = "Imported \(count) item(s)."
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
    var onProgress: (() -> Void)? = nil
    
    @ViewBuilder
    private var metricsRow: some View {
        HStack(spacing: 16) {
            if let r = item.reps { Text("Reps: \(r, format: .number.precision(.fractionLength(1)))") }
            if let s = item.sets { Text("Sets: \(s, format: .number.precision(.fractionLength(1)))") }
            if let d = item.duration { Text("Duration: \(d, format: .number.precision(.fractionLength(1)))") }
            if let w = item.weightKg { Text("Weight: \(w, format: .number.precision(.fractionLength(1))) kg") }
            if let g = item.grade { Text("Grade: \(g)") }
        }
        .font(.footnote.monospacedDigit())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.exerciseName).font(.headline)

                        Spacer()

                        if let onProgress {
                            Button(action: onProgress) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                            }
                            .labelStyle(.iconOnly)
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Show progress for \(item.exerciseName)")
                        }

                        if let planName = item.planName {
                            Text("Plan: \(planName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
            }
            metricsRow
            LoggedSetsRow(sets: item.loggedSets)
            if let n = item.notes, !n.isEmpty {
                Text(n).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Climb row styled like SessionItemRow
struct LogClimbRow: View {
    let climb: ClimbEntry
    @AppStorage(FeatureFlags.showSyncedBoardGradesAsVScale) private var showSyncedBoardGradesAsVScale = false
    
    private var gradeDisplay: String {
        BoardGradeDisplayRules.displayText(
            grade: climb.grade,
            feelsLikeGrade: climb.feelsLikeGrade,
            tb2ClimbUUID: climb.tb2ClimbUUID,
            kilterClimbUuid: climb.kilterClimbUuid,
            showSyncedBoardGradesAsVScale: showSyncedBoardGradesAsVScale
        ) ?? ""
    }
    
    private var secondaryLineText: String? {
        var parts: [String] = []
        
        if !climb.style.isEmpty {
            parts.append(climb.style)
        }
        if let angle = climb.angleDegrees {
            parts.append("\(angle)°")
        }
        if !climb.gym.isEmpty {
            parts.append(climb.gym)
        }
        
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private var climbTypeLabel: String {
        if let rope = climb.ropeClimbType?.displayName, !rope.isEmpty {
            return climb.climbType.displayName + " (\(rope))"
        } else {
            return climb.climbType.displayName
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: type / WIP / grade
            HStack(alignment: .firstTextBaseline) {
                Text(climbTypeLabel)
                    .font(.callout)
                
                if climb.isWorkInProgress {
                    Text("WIP")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.3))
                        .clipShape(.rect(cornerRadius: 4))
                }
                if climb.isPreviouslyClimbed == true {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                
                Spacer()
                
                if !gradeDisplay.isEmpty {
                    Text(gradeDisplay)
                        .font(.headline.monospacedDigit())
                }
            }
            
            // MARK: Secondary line with • separators
            HStack(spacing: 6) {
                if let text = secondaryLineText {
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                if let holdColor = climb.holdColor, holdColor != .none {
                    JugHoldShape()
                        .fill(holdColor.color)
                        .frame(width: 12, height: 12)
                        .overlay(
                            JugHoldShape()
                                .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.leading, 4)
                }
            }
            // Notes (if any)
            if let notes = climb.notes, !notes.isEmpty {
                Text(.init(notes))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}


// MARK: - Add item to a session
struct AddSessionItemSheet: View {
    private enum SheetRoute: String, Identifiable {
        case catalogPicker
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var session: Session

    @Query(sort: [SortDescriptor(\Exercise.name)]) private var allExercises: [Exercise]
    @Query(sort: [SortDescriptor(\Plan.startDate)]) private var plans: [Plan]

    @State private var sheetRoute: SheetRoute?
    @State private var selectedCatalogName: String? = nil
    @State private var selectedPlan: Plan? = nil
    @State private var inputReps: String = ""
    @State private var inputSets: String = ""
    @State private var inputDuration: String = ""
    @State private var inputWeight: String = ""
    @State private var inputNotes: String = ""
    @State private var inputGrade: String = ""

    /// Hidden for exercises that take no added load. Shown until one is picked, and
    /// never hidden once something has been typed. Reads `allExercises` rather than
    /// fetching — the query is already here.
    private var showsWeight: Bool {
        guard let name = selectedCatalogName, !name.isEmpty else { return true }
        if !inputWeight.isEmpty { return true }
        return (allExercises.first { $0.name == name }?.shape ?? .weighted).takesLoad
    }

    var body: some View {
        NavigationStack {
            Form {
                Button {
                    sheetRoute = .catalogPicker
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
                .sheet(item: $sheetRoute) { route in
                    switch route {
                    case .catalogPicker:
                        SingleCatalogExercisePicker(selected: $selectedCatalogName)
                    }
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
                    TextField("Duration", text: $inputDuration).keyboardType(.decimalPad)
                    if showsWeight {
                        TextField("Weight", text: $inputWeight).keyboardType(.decimalPad)
                    }
                    TextField("Grade", text: $inputGrade)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Notes", text: $inputNotes)
                }
            }
            .navigationTitle("Log Exercise")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let selectedName = selectedCatalogName, !selectedName.isEmpty else { return }
                        let reps = Double(inputReps.replacing(",", with: ".")
                            .trimmingCharacters(in: .whitespaces))
                        let sets = Double(inputSets.replacing(",", with: ".")
                            .trimmingCharacters(in: .whitespaces))
                        let duration = Double(inputDuration.replacing(",", with: ".")
                            .trimmingCharacters(in: .whitespaces))
                        let weight = Double(inputWeight.replacing(",", with: ".")
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
                            notes: inputNotes.isEmpty ? nil : inputNotes,
                            duration: duration
                        )
                        item.sort = (session.items.map(\.sort).max() ?? -1) + 1
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
    private enum SheetRoute: String, Identifiable {
        case multiExercisePicker
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.isDataReady) private var isDataReady

    @State private var date = Date()

    // NEW: multi-exercise add flow
    @State private var sheetRoute: SheetRoute?
    @State private var selectedExercises: [String] = []

    // NEW: tell LogView what day to open after creation
    let onCreated: (Date) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Exercises (optional)") {
                    Button {
                        guard isDataReady else { return }
                        sheetRoute = .multiExercisePicker
                    } label: {
                        HStack {
                            Text("Add Exercises")
                            Spacer()
                            if selectedExercises.isEmpty {
                                Text("Choose…").foregroundStyle(.secondary)
                            } else {
                                Text("\(selectedExercises.count) selected")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!isDataReady)

                    if !selectedExercises.isEmpty {
                        Text(selectedExercises.joined(separator: ", "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("New Session")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let dayKey = Calendar.current.startOfDay(for: date)

                        let session = Session(date: date)

                        if !selectedExercises.isEmpty {
                            for (idx, name) in selectedExercises.enumerated() {
                                let item = SessionItem(
                                    exerciseName: name,
                                    planSourceId: nil,
                                    planName: nil,
                                    reps: nil,
                                    sets: nil,
                                    weightKg: nil,
                                    grade: nil,
                                    notes: nil,
                                    duration: nil
                                )
                                item.sort = idx
                                session.items.append(item)
                            }
                        }

                        context.insert(session)
                        try? context.save()

                        dismiss()

                        // Navigate after the sheet is dismissed
                        Task { @MainActor in
                            onCreated(dayKey)
                        }
                    }
                    .disabled(!isDataReady)
                }
            }
        }
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .multiExercisePicker:
                CatalogExercisePicker(selected: $selectedExercises)
                    .environment(\.isDataReady, isDataReady)
            }
        }
    }
}


// MARK: - Session detail

struct SessionDetailView: View {
    private enum SheetRoute: String, Identifiable {
        case addItem
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.isDataReady) private var isDataReady
    @Environment(\.editMode) private var editMode
    @Bindable var session: Session
    @State private var sheetRoute: SheetRoute?
    @State private var editingItem: SessionItem? = nil
    @State private var didReorder = false
    // Quick Progress
       @State private var progressExercise: ExerciseSelection? = nil

    //multi-exercise add flow
    var body: some View {
        List {
            Section("Exercises") {
                ForEach(session.items.sorted(by: { $0.sort < $1.sort })) { item in
                    Button {
                        editingItem = item
                    } label: {
                        SessionItemRow(item: item) {
                            progressExercise = ExerciseSelection(name: item.exerciseName)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                guard isDataReady else { return }
                                do {
                                    try session.removeItem(item, in: context)
                                } catch {
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
                .onMove(perform: moveItems)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 10) {
                    // Reorder toggle (three horizontal lines ↔ checkmark)
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            editMode?.wrappedValue =
                                (editMode?.wrappedValue == .active) ? .inactive : .active
                        }
                    } label: {
                        Image(systemName:
                            editMode?.wrappedValue == .active
                            ? "checkmark"
                            : "line.3.horizontal"
                        )
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard isDataReady else { return }
                    sheetRoute = .addItem
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!isDataReady)
            }
        }
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .addItem:
                AddSessionItemSheet(session: session)
            }
        }
        .sheet(item: $editingItem) { item in
            NavigationStack {
                EditSessionItemView(item: item)
            }
        }
        .sheet(item: $progressExercise) { sel in
            QuickExerciseProgress(exerciseName: sel.name)
        }
        // Commit once when leaving edit mode, but only if a reorder occurred
        .onChange(of: editMode?.wrappedValue) { _, newValue in
            if newValue == .inactive, didReorder {
                didReorder = false
                try? context.save()
            }
        }
        // Safety: commit if navigating away mid-edit
        .onDisappear {
            if didReorder {
                didReorder = false
                try? context.save()
            }
        }
    }
    
    private func moveItems(from source: IndexSet, to destination: Int) {
        guard isDataReady else { return }

        // Reorder a working copy
        var working = session.items.sorted(by: { $0.sort < $1.sort })
        working.move(fromOffsets: source, toOffset: destination)

        // Reassign contiguous sort indices
        for (idx, item) in working.enumerated() {
            item.sort = idx
        }

        // Write back for UI consistency
        session.items = working
        didReorder = true
    }
}

struct EditSessionItemView: View {
    private enum SheetRoute: String, Identifiable {
        case catalogPicker
        var id: String { rawValue }
    }

    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.isDataReady) private var isDataReady
    @Bindable var item: SessionItem

    @Query(sort: [SortDescriptor(\Plan.startDate)]) private var plans: [Plan]
    @State private var sheetRoute: SheetRoute?
    @State private var selectedCatalogName: String? = nil
    @State private var selectedPlan: Plan? = nil
    @State private var inputReps: String = ""
    @State private var inputSets: String = ""
    @State private var inputDuration: String = ""
    @State private var inputWeight: String = ""
    @State private var inputNotes: String = ""
    @State private var inputGrade: String = ""
    @State private var isInitialized = false

    /// Hidden for exercises that take no added load — but an item that already carries
    /// a weight keeps the field, so an imported or legacy value stays editable rather
    /// than becoming invisible and stuck.
    private var showsWeight: Bool {
        if !inputWeight.isEmpty || item.weightKg != nil { return true }
        let name = selectedCatalogName ?? item.exerciseName
        return exerciseShape(named: name, in: context).takesLoad
    }

    var body: some View {
        Group {
            if !isInitialized {
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
            } else {
                Form {
                    Button {
                        sheetRoute = .catalogPicker
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
                    .sheet(item: $sheetRoute) { route in
                        switch route {
                        case .catalogPicker:
                            SingleCatalogExercisePicker(selected: $selectedCatalogName)
                        }
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
                        TextField("Duration", text: $inputDuration).keyboardType(.decimalPad)
                        if showsWeight {
                            TextField("Weight", text: $inputWeight).keyboardType(.decimalPad)
                        }
                        TextField("Grade", text: $inputGrade)
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
                            item.reps = Double(inputReps.replacing(",", with: ".")
                                .trimmingCharacters(in: .whitespaces))
                            item.sets = Double(inputSets.replacing(",", with: ".")
                                .trimmingCharacters(in: .whitespaces))
                            item.duration = Double(inputDuration.replacing(",", with: ".")
                                .trimmingCharacters(in: .whitespaces))
                            item.weightKg = Double(inputWeight.replacing(",", with: ".")
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
        // Initialize immediately on appear (no dependency on isDataReady)
        .task {
            await initializeView()
        }
        // If plans load/update after we initialized, try to preselect the plan by id
        .onChange(of: plans) {
            updateSelectedPlanIfNeeded()
        }
    }
    
    @MainActor
    private func initializeView() async {
        guard !isInitialized else { return }
        
        // Small delay to ensure SwiftUI has mounted the view
        try? await Task.sleep(for: .milliseconds(30))
        
        // Initialize from the current item immediately
        selectedCatalogName = item.exerciseName
        
        // Preselect plan if we already have it in the query
        updateSelectedPlanIfNeeded()
        
        inputReps = item.reps.map { String($0) } ?? ""
        inputSets = item.sets.map { String($0) } ?? ""
        inputDuration = item.duration.map { String($0) } ?? ""
        inputWeight = item.weightKg.map { String($0) } ?? ""
        inputGrade = item.grade ?? ""
        inputNotes = item.notes ?? ""
        
        isInitialized = true
    }
    
    @MainActor
    private func updateSelectedPlanIfNeeded() {
        guard selectedPlan == nil, let planId = item.planSourceId else { return }
        if let match = plans.first(where: { $0.id == planId }) {
            selectedPlan = match
        }
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
    @Query(
        filter: #Predicate<DayTag> { $0.isHidden == false },
        sort: [
            SortDescriptor<DayTag>(\DayTag.sort, order: .forward),
            SortDescriptor<DayTag>(\DayTag.name, order: .forward)
        ]
    ) private var tags: [DayTag]

    let sessions: [Session]
    let climbEntries: [ClimbEntry]
    let dayLogs: [DayLog]

    @State private var showFilters = false
    @State private var dateRange = DateRange()
    @State private var selectedTagIDs: Set<UUID> = []
    
    // Group data by date
    private var groupedData: [Date: LogDaySummary] {
        LogDaySummaryBuilder.build(
            sessions: sessions,
            climbEntries: climbEntries,
            dayLogs: dayLogs
        )
    }

    private var filteredData: [Date: LogDaySummary] {
        LogDaySummaryFilter.filteredSummaries(
            groupedData,
            dateRange: dateRange,
            selectedTagIDs: selectedTagIDs
        )
    }
    
    private var sortedDates: [Date] {
        filteredData.keys.sorted(by: >)
    }

    private var allDates: [Date] {
        groupedData.keys.sorted()
    }

    private var hasActiveFilters: Bool {
        LogDaySummaryFilter.isDateFilterActive(
            dateRange: dateRange,
            availableDates: allDates
        ) || !selectedTagIDs.isEmpty
    }
    
    var body: some View {
        List {
            if !groupedData.isEmpty {
                filterSection
            }

            ForEach(sortedDates, id: \.self) { date in
                let dayData = filteredData[date]!
                NavigationLink {
                    CombinedDayDetailView(
                        date: date,
                        session: dayData.session,
                        climbEntries: dayData.climbEntries,
                        dayLog: dayData.dayLog
                    )
                } label: {
                    CombinedDayRow(
                        date: date,
                        exerciseCount: dayData.exercises,
                        climbCount: dayData.climbs,
                        dayLog: dayData.dayLog
                    )
                }
            }
            .onDelete(perform: delete)

            if !groupedData.isEmpty, sortedDates.isEmpty {
                Section {
                    Text("No days match filters")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear(perform: ensureDateRangeInitialized)
        .onChange(of: groupedData.count) { _, _ in
            ensureDateRangeInitialized()
        }
    }

    @ViewBuilder
    private var filterSection: some View {
        VStack(spacing: 4) {
            Button(action: toggleFilters) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(showFilters ? "Hide filters" : "Show filters")
                    Spacer()
                    if hasActiveFilters {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 10, height: 10)
                    }
                }
                .font(.subheadline)
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)

            if showFilters {
                LogFilterCard {
                    VStack(spacing: 10) {
                        HStack {
                            HStack {
                                Text("Dates")
                                DateRangePicker(range: $dateRange)
                            }
                            ClearAllButton(
                                action: clearAllFilters,
                                isEnabled: hasActiveFilters
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tags")
                                .font(.callout)

                            if tags.isEmpty {
                                Text("No day tags yet")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                FlowLayout(spacing: 8, rowSpacing: 8) {
                                    ForEach(tags) { tag in
                                        LogTagFilterChip(
                                            tag: tag,
                                            isSelected: selectedTagIDs.contains(tag.id),
                                            onToggle: { toggleTag(tag) }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: showFilters ? 6 : 0, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
    
    @MainActor
    private func delete(_ offsets: IndexSet) {
        withAnimation {
            //disable undo snapphots for log view deletions
            let previousUndoManager = context.undoManager
            context.undoManager = nil
            defer { context.undoManager = previousUndoManager }
            
            for index in offsets {
                let date = sortedDates[index]
                guard let dayData = filteredData[date] else { continue }

                //If there's a Session, remove its items first
                if let session = dayData.session {
                    for item in Array(session.items) {
                        context.delete(item)
                    }
                    context.delete(session)
                }

                // 2) Delete all climbs for that day
                for climb in dayData.climbEntries {
                    context.delete(climb)
                }

                if let dayLog = dayData.dayLog {
                    context.delete(dayLog)
                }
            }
            try? context.save()
        }
    }

    private func toggleFilters() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showFilters.toggle()
        }
    }

    private func toggleTag(_ tag: DayTag) {
        if selectedTagIDs.contains(tag.id) {
            selectedTagIDs.remove(tag.id)
        } else {
            selectedTagIDs.insert(tag.id)
        }
    }

    private func clearAllFilters() {
        dateRange = DateRange()
        selectedTagIDs.removeAll()
        ensureDateRangeInitialized()
    }

    private func ensureDateRangeInitialized() {
        guard let minDate = allDates.min(), let maxDate = allDates.max() else {
            dateRange = DateRange()
            return
        }

        if dateRange.customStart == nil || (dateRange.customStart ?? minDate) > minDate {
            dateRange.customStart = minDate
        }

        if dateRange.customEnd == nil || (dateRange.customEnd ?? maxDate) < maxDate {
            dateRange.customEnd = maxDate
        }
    }
}

private struct LogFilterCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(12)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

private struct LogTagFilterChip: View {
    let tag: DayTag
    let isSelected: Bool
    let onToggle: () -> Void

    private var color: Color {
        DayTypeModel.color(for: tag.colorKey)
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                }

                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                Text(tag.name)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? color.opacity(0.22) : Color.clear)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? color : .secondary.opacity(0.35), lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 8))
        .contentShape(.rect(cornerRadius: 8))
        .accessibilityLabel(tag.name)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(isSelected ? "Double tap to remove this tag from the filters." : "Double tap to filter by this tag.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

}

private struct CombinedDayRow: View {
    let date: Date
    let exerciseCount: Int
    let climbCount: Int
    let dayLog: DayLog?

    private var tags: [DayTag] {
        DayLogStore.activeTags(from: dayLog)
    }
    
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
                            .foregroundStyle(.white)
                            .clipShape(.rect(cornerRadius: 4))
                    }
                    
                    if climbCount > 0 {
                        Text("climb")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .foregroundStyle(.white)
                            .clipShape(.rect(cornerRadius: 4))
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

            if !tags.isEmpty {
                DayTagChips(tags: tags)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Combined Day Detail View

private struct CombinedDayDetailView: View {
    private enum AddRoute: String, Identifiable {
        case exercise
        case climb
        case multiExercisePicker

        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.isDataReady) private var isDataReady
    @Environment(\.editMode) private var editMode
    let date: Date
    let session: Session?
    let climbEntries: [ClimbEntry]
    let dayLog: DayLog?
    
    @State private var addRoute: AddRoute? = nil
    @State private var didReorder = false
    @State private var editingClimb: ClimbEntry? = nil
    @State private var editingItem: SessionItem? = nil
    @State private var localDayLog: DayLog? = nil
    // Quick Progress
    @State private var progressExercise: ExerciseSelection? = nil
    //multi-exercise add flow
    @State private var shouldProcessMultiSelectionOnDismiss = false
    @State private var multiSelectedExercises: [String] = []
    
    // Pre-sorted climbs so we don't re-sort inside the body repeatedly
    private var sortedClimbs: [ClimbEntry] {
        climbEntries.sorted(by: { $0.dateLogged > $1.dateLogged })
    }

    private var resolvedDayLog: DayLog? {
        localDayLog ?? dayLog
    }
    
    var body: some View {
        List {
            DayContextEditorSection(
                date: date,
                dayLog: resolvedDayLog,
                onDayLogChanged: updateDayLog
            )

            // Exercises section
            if let session = session, !session.items.isEmpty {
                Section("Exercises") {
                    ForEach(session.items.sorted(by: { $0.sort < $1.sort })) { item in
                        Button {
                            editingItem = item
                        } label: {
                            SessionItemRow(item: item) {
                                progressExercise = ExerciseSelection(name: item.exerciseName)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    guard isDataReady else { return }
                                    do {
                                        try session.removeItem(item, in: context)
                                    } catch {
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
                    .onMove { source, destination in
                        moveItems(in: session, from: source, to: destination)
                    }
                }
            }

            
            // Climbs section
            if !sortedClimbs.isEmpty {
                Section("Climbs") {
                    ForEach(sortedClimbs) { climb in
                        Button {
                            editingClimb = climb
                        } label: {
                            LogClimbRow(climb: climb)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    guard isDataReady else { return }
                                    deleteClimbSafely(climb)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }



            
            // Empty state
            if (session?.items.isEmpty ?? true) && sortedClimbs.isEmpty {
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
            // Only show the reorder toggle if there are exercises
            if let session, !session.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                editMode?.wrappedValue =
                                    (editMode?.wrappedValue == .active) ? .inactive : .active
                            }
                        } label: {
                            Image(systemName:
                                    editMode?.wrappedValue == .active
                                  ? "checkmark"
                                  : "line.3.horizontal"
                            )
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: { addExercise() }) {
                        Label("Log Exercise", systemImage: "dumbbell")
                    }
                    Button(action: {
                        shouldProcessMultiSelectionOnDismiss = true
                        addRoute = .multiExercisePicker
                    }) {
                               Label("Add Several Exercises", systemImage: "text.badge.plus")
                           }
                    Button(action: {
                        shouldProcessMultiSelectionOnDismiss = false
                        addRoute = .climb
                    }) {
                        Label("Log Climb", systemImage: "figure.climbing")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!isDataReady)
            }
        }
        .sheet(item: $addRoute, onDismiss: {
            if shouldProcessMultiSelectionOnDismiss {
                addExercisesFromSelection()
                shouldProcessMultiSelectionOnDismiss = false
            }
        }) { route in
            switch route {
            case .exercise:
                if let session = session {
                    AddSessionItemSheet(session: session)
                }
            case .climb:
                AddClimbView()
            case .multiExercisePicker:
                CatalogExercisePicker(selected: $multiSelectedExercises)
                    .environment(\.isDataReady, isDataReady)
            }
        }
        .sheet(item: $editingClimb) { climb in
            ClimbLogForm(
                title: "Edit Climb",
                initialDate: climb.dateLogged,
                existingClimb: climb,
                onSave: nil
            )
        }
        .sheet(item: $editingItem) { item in
            NavigationStack {
                EditSessionItemView(item: item)
            }
        }
        .sheet(item: $progressExercise) { sel in
            QuickExerciseProgress(exerciseName: sel.name)
        }
        // Commit once when leaving edit mode, but only if a reorder occurred
        .onChange(of: editMode?.wrappedValue) { _, newValue in
            if newValue == .inactive, didReorder {
                didReorder = false
                try? context.save()
            }
        }
        .onDisappear {
            if didReorder {
                didReorder = false
                try? context.save()
            }
        }
        .onAppear {
            localDayLog = dayLog
        }
    }

    private func updateDayLog(_ dayLog: DayLog?) {
        localDayLog = dayLog
    }
    
    private func addExercise() {
        guard isDataReady else { return }
        
        // Create session if it doesn't exist
        if session == nil {
            let newSession = Session(date: date)
            context.insert(newSession)
            try? context.save()
        }
        
        shouldProcessMultiSelectionOnDismiss = false
        addRoute = .exercise
    }
    
    private func addExercisesFromSelection() {
        guard isDataReady else { return }
        guard !multiSelectedExercises.isEmpty else { return }

        // Create / reuse the session for this date
        let targetSession: Session = {
            if let session { return session }
            let newSession = Session(date: date)
            context.insert(newSession)
            return newSession
        }()

        let startSort = (targetSession.items.map(\.sort).max() ?? -1) + 1

        for (idx, name) in multiSelectedExercises.enumerated() {
            let item = SessionItem(
                exerciseName: name,
                planSourceId: nil,
                planName: nil,
                reps: nil,
                sets: nil,
                weightKg: nil,
                grade: nil,
                notes: nil,
                duration: nil
            )
            item.sort = startSort + idx
            targetSession.items.append(item)
        }

        try? context.save()
        multiSelectedExercises = []
    }

    
    private func moveItems(in session: Session, from source: IndexSet, to destination: Int) {
        guard isDataReady else { return }

        var working = session.items.sorted(by: { $0.sort < $1.sort })
        working.move(fromOffsets: source, toOffset: destination)

        for (idx, item) in working.enumerated() {
            item.sort = idx
        }

        session.items = working
        didReorder = true
    }
    
    private func deleteClimbSafely(_ climb: ClimbEntry) {
        let previousUndoManager = context.undoManager
        context.undoManager = nil
        defer { context.undoManager = previousUndoManager }

        context.delete(climb)
        try? context.save()
    }
}
