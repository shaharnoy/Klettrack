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
            SyncLocalMutation.softDelete(item)
        }
        SyncLocalMutation.softDelete(item)
        SyncLocalMutation.touch(self)

        if deleteEmptySession && items.isEmpty {
            SyncLocalMutation.softDelete(self)
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
    @Query(
        filter: #Predicate<Session> { !$0.isDeleted },
        sort: [SortDescriptor(\Session.date, order: .reverse)]
    ) private var sessions: [Session]
    @Query(
        filter: #Predicate<ClimbEntry> { !$0.isDeleted },
        sort: [SortDescriptor(\ClimbEntry.dateLogged, order: .reverse)]
    ) private var climbEntries: [ClimbEntry]

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
                CombinedLogList(sessions: sessions, climbEntries: climbEntries)
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

                        CombinedDayDetailView(
                            date: dayKey,
                            session: sessionForDay,
                            climbEntries: climbsForDay
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
        for i in offsets { SyncLocalMutation.softDelete(sessions[i]) }
        try? context.save()
    }
}

private struct SessionRow: View {
    let session: Session
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.date.formatted(date: .abbreviated, time: .omitted))
                .font(.headline)
            let activeCount = SyncLocalMutation.active(session.items).count
            Text("\(activeCount) exercise\(activeCount == 1 ? "" : "s")")
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
    
    private var gradeDisplay: String {
        let hasGrade = climb.grade != "Unknown" && !climb.grade.isEmpty
        let feels = climb.feelsLikeGrade ?? ""
        let hasFeels = !feels.isEmpty
        
        switch (hasGrade, hasFeels) {
        case (true, true):  return "\(climb.grade) (\(feels))"
        case (true, false): return climb.grade
        case (false, true): return feels
        default:            return ""
        }
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

    @Query(
        filter: #Predicate<Exercise> { !$0.isDeleted },
        sort: [SortDescriptor(\Exercise.name)]
    ) private var allExercises: [Exercise]
    @Query(
        filter: #Predicate<Plan> { !$0.isDeleted },
        sort: [SortDescriptor(\Plan.startDate)]
    ) private var plans: [Plan]

    @State private var sheetRoute: SheetRoute?
    @State private var selectedCatalogName: String? = nil
    @State private var selectedPlan: Plan? = nil
    @State private var inputReps: String = ""
    @State private var inputSets: String = ""
    @State private var inputDuration: String = ""
    @State private var inputWeight: String = ""
    @State private var inputNotes: String = ""
    @State private var inputGrade: String = ""

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
                    TextField("Weight", text: $inputWeight).keyboardType(.decimalPad)
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
                        SyncLocalMutation.touch(item)
                        session.items.append(item)
                        SyncLocalMutation.touch(session)
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
                        SyncLocalMutation.touch(session)

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
                                SyncLocalMutation.touch(item)
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
                ForEach(SyncLocalMutation.active(session.items).sorted(by: { $0.sort < $1.sort })) { item in
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
        var working = SyncLocalMutation.active(session.items).sorted(by: { $0.sort < $1.sort })
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

    @Query(
        filter: #Predicate<Plan> { !$0.isDeleted },
        sort: [SortDescriptor(\Plan.startDate)]
    ) private var plans: [Plan]
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
                        TextField("Weight", text: $inputWeight).keyboardType(.decimalPad)
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
        try? await Task.sleep(nanoseconds: 30_000_000) // 0.03s
        
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
            grouped[dateKey]?.exercises = SyncLocalMutation.active(Array(session.items)).count
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
    
    @MainActor
    private func delete(_ offsets: IndexSet) {
        withAnimation {
            //disable undo snapphots for log view deletions
            let previousUndoManager = context.undoManager
            context.undoManager = nil
            defer { context.undoManager = previousUndoManager }
            
            for index in offsets {
                let date = sortedDates[index]
                guard let dayData = groupedData[date] else { continue }

                //If there's a Session, remove its items first
                if let session = dayData.session {
                    for item in SyncLocalMutation.active(Array(session.items)) {
                        SyncLocalMutation.softDelete(item)
                    }
                    SyncLocalMutation.softDelete(session)
                }

                // 2) Delete all climbs for that day
                for climb in dayData.climbEntries {
                    SyncLocalMutation.softDelete(climb)
                }
            }
            try? context.save()
        }
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
    
    @State private var addRoute: AddRoute? = nil
    @State private var didReorder = false
    @State private var editingClimb: ClimbEntry? = nil
    @State private var editingItem: SessionItem? = nil
    // Quick Progress
    @State private var progressExercise: ExerciseSelection? = nil
    //multi-exercise add flow
    @State private var shouldProcessMultiSelectionOnDismiss = false
    @State private var multiSelectedExercises: [String] = []
    
    // Pre-sorted climbs so we don't re-sort inside the body repeatedly
    private var sortedClimbs: [ClimbEntry] {
        climbEntries.sorted(by: { $0.dateLogged > $1.dateLogged })
    }
    
    var body: some View {
        List {
            // Exercises section
            if let session = session, !session.items.isEmpty {
                Section("Exercises") {
                    ForEach(SyncLocalMutation.active(session.items).sorted(by: { $0.sort < $1.sort })) { item in
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

        var working = SyncLocalMutation.active(session.items).sorted(by: { $0.sort < $1.sort })
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

        SyncLocalMutation.softDelete(climb)
        try? context.save()
    }
}
