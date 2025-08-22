//
//  LogView.swift
//  ClimbingProgram
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit // uses ShareSheet from your Plans module (or provide a local one)

// If you don't have a global ShareSheet, uncomment this:
// struct ShareSheet: UIViewControllerRepresentable {
//     let items: [Any]
//     let completion: (() -> Void)?
//     func makeUIViewController(context: Context) -> UIActivityViewController {
//         let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
//         vc.completionWithItemsHandler = { _,_,_,_ in completion?() }
//         return vc
//     }
//     func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
// }

// MARK: - Log (list of sessions)

struct LogView: View {
    @Environment(\.modelContext) private var context
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
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingNew = true } label: { Image(systemName: "plus") }
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
    @Bindable var session: Session
    @State private var showingAddItem = false

    var body: some View {
        NavigationStack {
            List {
                Section("Exercises") {
                    ForEach(session.items) { item in
                        SessionItemRow(item: item)
                    }
                    .onDelete { idx in
                        idx.map { session.items[$0] }.forEach { context.delete($0) }
                        try? context.save()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddItem = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAddItem) { AddSessionItemSheet(session: session) }
        }
    }
}

private struct SessionItemRow: View {
    @Bindable var item: SessionItem
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.exerciseName).font(.headline)
            HStack(spacing: 16) {
                if let r = item.reps { Text("Reps: \(r)") }
                if let s = item.sets { Text("Sets: \(s)") }
                if let w = item.weightKg { Text(String(format: "Wt: %.1f kg", w)) }
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

    @State private var selectedName: String = ""
    @State private var inputReps: String = ""
    @State private var inputSets: String = ""
    @State private var inputWeight: String = ""
    @State private var inputNotes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Exercise", selection: $selectedName) {
                    Text("Choose…").tag("")
                    ForEach(allExercises.map(\.name), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Section("Details") {
                    TextField("Reps (integer)", text: $inputReps).keyboardType(.numberPad)
                    TextField("Sets (integer)", text: $inputSets).keyboardType(.numberPad)
                    TextField("Weight (kg)", text: $inputWeight).keyboardType(.decimalPad)
                    TextField("Notes", text: $inputNotes)
                }
            }
            .navigationTitle("Add Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !selectedName.isEmpty else { return }
                        let reps = Int(inputReps.trimmingCharacters(in: .whitespaces))
                        let sets = Int(inputSets.trimmingCharacters(in: .whitespaces))
                        let weight = Double(inputWeight.replacingOccurrences(of: ",", with: ".")
                            .trimmingCharacters(in: .whitespaces))
                        let item = SessionItem(
                            exerciseName: selectedName,
                            reps: reps, sets: sets, weightKg: weight,
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
