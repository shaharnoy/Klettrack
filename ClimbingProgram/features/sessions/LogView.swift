//
//  LogView.swift
//  ClimbingProgram
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
            SessionsList(sessions: sessions) // <- tiny subview
                .navigationTitle("Log")
                .toolbar { trailingToolbar }
                .sheet(isPresented: $showingNew) { NewSessionSheet() }
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
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
        .onAppear {
            if let selected = selected {
                internalSelection = [selected]
            }
        }
    }
}
