//
//  LogView.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//
import SwiftUI
import SwiftData

// MARK: Log (list of sessions)

struct LogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]
    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(sessions) { s in
                    NavigationLink {
                        SessionDetailView(session: s)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(s.date.formatted(date: .abbreviated, time: .omitted)).bold()
                            Text("\(s.items.count) exercises")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    idx.map { sessions[$0] }.forEach(context.delete)
                    try? context.save()
                }
            }
            .navigationTitle("Log")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNew) {
                NewSessionSheet()
            }
        }
    }
}

// MARK: New session

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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
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

// MARK: Session detail

struct SessionDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var session: Session      // <-- SwiftData editable model
    @State private var showingAddItem = false

    var body: some View {
        List {
            Section("Exercises") {
                ForEach(session.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.exerciseName).bold()
                        HStack(spacing: 16) {
                            if let r = item.reps { Text("Reps: \(r)") }
                            if let s = item.sets { Text("Sets: \(s)") }
                            if let w = item.weightKg { Text("Wt: \(w, specifier: "%.1f") kg") }
                        }
                        .font(.footnote)
                        if let n = item.notes, !n.isEmpty {
                            Text(n).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    idx.map { session.items[$0] }.forEach { context.delete($0) }
                    try? context.save()
                }
            }
        }
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddSessionItemSheet(session: session)
        }
    }
}

// MARK: Add item to a session (manual add, mirrors Quick Log)

struct AddSessionItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var session: Session

    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    // Inputs
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
                    ForEach(allExercises.map { $0.name }, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Section("Details") {
                    TextField("Reps (integer)", text: $inputReps)
                        .keyboardType(.numberPad)
                    TextField("Sets (integer)", text: $inputSets)
                        .keyboardType(.numberPad)
                    TextField("Weight (kg)", text: $inputWeight)
                        .keyboardType(.decimalPad)
                    TextField("Notes", text: $inputNotes)
                }
            }
            .navigationTitle("Add Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !selectedName.isEmpty else { return }

                        let reps = Int(inputReps.trimmingCharacters(in: .whitespaces))
                        let sets = Int(inputSets.trimmingCharacters(in: .whitespaces))
                        let weight = Double(inputWeight.replacingOccurrences(of: ",", with: ".")
                            .trimmingCharacters(in: .whitespaces))

                        let item = SessionItem(
                            exerciseName: selectedName,
                            reps: reps,
                            sets: sets,
                            weightKg: weight,
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
