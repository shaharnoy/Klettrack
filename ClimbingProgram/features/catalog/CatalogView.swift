//
//  CatalogView.swift
//  ClimbingProgram
//
//  Created by Shahar Private on 21.08.25.
//

import SwiftUI
import SwiftData

// MARK: - Root Catalog (Categories = Activity)

struct CatalogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Activity.name) private var activities: [Activity]

    @State private var showingNewActivity = false
    @State private var draftActivityName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(activities) { activity in
                        NavigationLink {
                            ActivityDetailView(activity: activity)
                        } label: {
                            CatalogCard(
                                title: activity.name,
                                subtitle: "\(activity.types.count) training type\(activity.types.count == 1 ? "" : "s")",
                                tint: activity.hue.color
                            ) {
                                Text("Tap to view & edit")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Rename") { draftActivityName = activity.name; showingRenamePrompt = activity }
                            Button(role: .destructive, action: { context.delete(activity); try? context.save() }) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        draftActivityName = ""
                        showingNewActivity = true
                    } label: {
                        Label("Add Category", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .padding(.top, 6)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Catalog")
            .sheet(isPresented: $showingNewActivity) {
                NameEditSheet(
                    title: "New Category",
                    placeholder: "e.g. Core, Antagonist & Stabilizer…",
                    name: $draftActivityName
                ) {
                    guard !draftActivityName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    let a = Activity(name: draftActivityName.trimmingCharacters(in: .whitespaces))
                    context.insert(a)
                    try? context.save()
                }
            }
            .sheet(item: $showingRenamePrompt) { toRename in
                NameEditSheet(
                    title: "Rename Category",
                    placeholder: "New name",
                    name: Binding(
                        get: { draftActivityName },
                        set: { draftActivityName = $0 }
                    )
                ) {
                    toRename.name = draftActivityName.trimmingCharacters(in: .whitespaces)
                    try? context.save()
                }
            }
        }
    }

    // rename support
    @State private var showingRenamePrompt: Activity?
}

// MARK: - Activity detail (Training Types)

struct ActivityDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var activity: Activity

    @State private var showingNewType = false
    @State private var draftTypeName = ""
    @State private var draftArea = ""

    var body: some View {
        List {
            Section {
                ForEach(activity.types) { t in
                    NavigationLink {
                        TrainingTypeDetailView(trainingType: t, tint: activity.hue.color)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.name).font(.headline)
                            if let area = t.area, !area.isEmpty {
                                Text(area).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contextMenu {
                        Button("Rename") { draftTypeName = t.name; draftArea = t.area ?? ""; renamingType = t }
                        Button(role: .destructive) {
                            context.delete(t); try? context.save()
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                .onDelete { idx in
                    idx.map { activity.types[$0] }.forEach { context.delete($0) }
                    try? context.save()
                }

                Button {
                    draftTypeName = ""; draftArea = ""
                    showingNewType = true
                } label: {
                    Label("Add Training Type", systemImage: "plus")
                }
            } header: {
                Text("Training Types")
            }
        }
        .navigationTitle(activity.name)
        .toolbar { EditButton() }
        // Create
        .sheet(isPresented: $showingNewType) {
            TrainingTypeEditSheet(
                title: "New Training Type",
                name: $draftTypeName,
                area: $draftArea
            ) {
                let t = TrainingType(name: draftTypeName.trimmingCharacters(in: .whitespaces),
                                     area: draftArea.trimmingCharacters(in: .whitespaces).isEmpty ? nil : draftArea)
                activity.types.append(t)
                try? context.save()
            }
        }
        // Rename
        .sheet(item: $renamingType) { tt in
            TrainingTypeEditSheet(
                title: "Rename Training Type",
                name: Binding(get: { draftTypeName }, set: { draftTypeName = $0 }),
                area: Binding(get: { draftArea }, set: { draftArea = $0 })
            ) {
                tt.name = draftTypeName.trimmingCharacters(in: .whitespaces)
                tt.area = draftArea.trimmingCharacters(in: .whitespaces).isEmpty ? nil : draftArea
                try? context.save()
            }
        }
    }

    @State private var renamingType: TrainingType?
}

// MARK: - Type detail (Exercises)

struct TrainingTypeDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var trainingType: TrainingType
    let tint: Color

    // New vs Edit state
    @State private var showingNewExercise = false
    @State private var editingExercise: Exercise? = nil

    // Draft fields shared by the sheets
    @State private var draftExName = ""
    @State private var draftReps = ""
    @State private var draftSets = ""
    @State private var draftRest = ""
    @State private var draftNotes = ""

    var body: some View {
        List {
            Section {
                ForEach(trainingType.exercises) { ex in
                    ExerciseRow(ex: ex, tint: tint)
                        .contentShape(Rectangle())
                        // Tap row to edit this exact exercise
                        .onTapGesture {
                            openEditor(for: ex)
                        }
                        // Swipe: Edit / Delete
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Edit") { openEditor(for: ex) }
                                .tint(.blue)
                            Button(role: .destructive) {
                                context.delete(ex)
                                try? context.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        // Long-press: Edit / Delete
                        .contextMenu {
                            Button("Edit") { openEditor(for: ex) }
                            Button(role: .destructive) {
                                context.delete(ex); try? context.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onDelete { idx in
                    idx.map { trainingType.exercises[$0] }.forEach { context.delete($0) }
                    try? context.save()
                }

                // Add new exercise
                Button {
                    draftExName = ""
                    draftReps = ""
                    draftSets = ""
                    draftRest = ""
                    draftNotes = ""
                    showingNewExercise = true
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                }
            } header: {
                Text("Exercises")
            }
        }
        .navigationTitle(trainingType.name)
        .toolbar { EditButton() }

        // NEW exercise sheet (creates and inserts)
        .sheet(isPresented: $showingNewExercise) {
            ExerciseEditSheet(
                title: "New Exercise",
                name: $draftExName,
                reps: $draftReps,
                sets: $draftSets,
                rest: $draftRest,
                notes: $draftNotes
            ) {
                let ex = Exercise(
                    name: draftExName.trimmingCharacters(in: .whitespaces),
                    repsText: draftReps.isEmpty ? nil : draftReps,
                    setsText: draftSets.isEmpty ? nil : draftSets,
                    restText: draftRest.isEmpty ? nil : draftRest,
                    notes: draftNotes.isEmpty ? nil : draftNotes
                )
                trainingType.exercises.append(ex)
                try? context.save()
            }
        }

        // EDIT exercise sheet (updates existing; does NOT insert)
        .sheet(item: $editingExercise) { ex in
            ExerciseEditSheet(
                title: "Edit Exercise",
                name: Binding(get: { draftExName }, set: { draftExName = $0 }),
                reps: Binding(get: { draftReps }, set: { draftReps = $0 }),
                sets: Binding(get: { draftSets }, set: { draftSets = $0 }),
                rest: Binding(get: { draftRest }, set: { draftRest = $0 }),
                notes: Binding(get: { draftNotes }, set: { draftNotes = $0 })
            ) {
                // mutate the existing model
                ex.name = draftExName.trimmingCharacters(in: .whitespaces)
                ex.repsText = draftReps.isEmpty ? nil : draftReps
                ex.setsText = draftSets.isEmpty ? nil : draftSets
                ex.restText = draftRest.isEmpty ? nil : draftRest
                ex.notes = draftNotes.isEmpty ? nil : draftNotes
                try? context.save()
            }
        }
    }

    // Prefill the drafts and present the edit sheet
    private func openEditor(for ex: Exercise) {
        draftExName = ex.name
        draftReps   = ex.repsText ?? ""
        draftSets   = ex.setsText ?? ""
        draftRest   = ex.restText ?? ""
        draftNotes  = ex.notes ?? ""
        editingExercise = ex
    }
}


// MARK: - Rows & Sheets

private struct ExerciseRow: View {
    @Bindable var ex: Exercise
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(ex.name).font(.headline)
            }
            HStack {
                labelValue("REPS", ex.repsText)
                Spacer(minLength: 12)
                labelValue("SETS/REST", ex.setsText ?? ex.restText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let notes = ex.notes, !notes.isEmpty {
                Text(notes).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func labelValue(_ label: String, _ value: String?) -> some View {
        HStack(spacing: 4) {
            Text(label).bold()
            Text(value ?? "—")
        }
    }
}

// Generic small name sheet (for Activity)
private struct NameEditSheet: View {
    let title: String
    let placeholder: String
    @Binding var name: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField(placeholder, text: $name)
                    .textInputAutocapitalization(.words)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        onSave(); dismiss()
                    }
                }
            }
        }
    }
}

// Training Type edit sheet
private struct TrainingTypeEditSheet: View {
    let title: String
    @Binding var name: String
    @Binding var area: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Area (optional)", text: $area)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        onSave(); dismiss()
                    }
                }
            }
        }
    }
}

// Exercise edit sheet
private struct ExerciseEditSheet: View {
    let title: String
    @Binding var name: String
    @Binding var reps: String
    @Binding var sets: String
    @Binding var rest: String
    @Binding var notes: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise name", text: $name)
                }
                Section("Display Fields (free text)") {
                    TextField("REPS (display text)", text: $reps)
                    TextField("SETS (display text)", text: $sets)
                    TextField("REST (display text)", text: $rest)
                }
                Section("Notes") {
                    TextField("Notes (optional)", text: $notes)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        onSave(); dismiss()
                    }
                }
            }
        }
    }
}
