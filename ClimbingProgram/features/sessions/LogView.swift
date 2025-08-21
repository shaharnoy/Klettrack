//
//  LogView.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//

import SwiftUI
import SwiftData

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
                            Text(s.date, style: .date).bold()
                            Text("\(s.items.count) exercises").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }.onDelete { idx in
                    idx.map { sessions[$0] }.forEach(context.delete)
                    try? context.save()
                }
            }
            .navigationTitle("Log")
            .toolbar {
                Button(systemImage: "plus") { showingNew = true }
            }
            .sheet(isPresented: $showingNew) {
                NewSessionSheet()
            }
        }
    }
}

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

struct SessionDetailView: View {
    @Environment(\.modelContext) private var context
    @State var session: Session
    @State private var showingAddItem = false

    var body: some View {
        List {
            Section("Exercises") {
                ForEach(session.items) { item in
                    VStack(alignment: .leading) {
                        Text(item.exerciseName).bold()
                        if let reps = item.repsDone { Text(reps).font(.footnote) }
                        if let n = item.notes { Text(n).font(.footnote).foregroundStyle(.secondary) }
                    }
                }.onDelete { idx in
                    idx.map { session.items[$0] }.forEach { context.delete($0) }
                    try? context.save()
                }
            }
        }
        .navigationTitle(session.date, format: .dateTime.year().month().day())
        .toolbar {
            Button(systemImage: "plus") { showingAddItem = true }
        }
        .sheet(isPresented: $showingAddItem) {
            AddSessionItemSheet(session: session)
        }
    }
}

struct AddSessionItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let session: Session
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @State private var selectedName: String = ""
    @State private var repsDone: String = ""
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Exercise", selection: $selectedName) {
                    Text("Choose…").tag("")
                    ForEach(allExercises.map { $0.name }, id: \.self) { Text($0).tag($0) }
                }
                TextField("Reps/Sets performed (free text)", text: $repsDone)
                TextField("Notes", text: $notes)
            }
            .navigationTitle("Add Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !selectedName.isEmpty else { return }
                        let item = SessionItem(exerciseName: selectedName, repsDone: repsDone.isEmpty ? nil : repsDone, notes: notes.isEmpty ? nil : notes)
                        session.items.append(item)
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
