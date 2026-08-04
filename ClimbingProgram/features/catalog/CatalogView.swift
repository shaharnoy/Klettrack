//
//  CatalogView.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import SwiftUI
import SwiftData

struct CatalogExerciseDraft {
    let name: String
    let area: String
    let reps: String
    let sets: String
    let duration: String
    let rest: String
    let notes: String
    let description: String

    private func optionalValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedArea: String? { optionalValue(area) }
    var normalizedReps: String? { optionalValue(reps) }
    var normalizedSets: String? { optionalValue(sets) }
    var normalizedDuration: String? { optionalValue(duration) }
    var normalizedRest: String? { optionalValue(rest) }
    var normalizedNotes: String? { optionalValue(notes) }
    var normalizedDescription: String? { optionalValue(description) }

    func makeExercise(order: Int) -> Exercise {
        Exercise(
            name: normalizedName,
            area: normalizedArea,
            order: order,
            exerciseDescription: normalizedDescription,
            repsText: normalizedReps,
            durationText: normalizedDuration,
            setsText: normalizedSets,
            restText: normalizedRest,
            notes: normalizedNotes
        )
    }

    func apply(to exercise: Exercise) {
        exercise.name = normalizedName
        exercise.area = normalizedArea
        exercise.exerciseDescription = normalizedDescription
        exercise.repsText = normalizedReps
        exercise.setsText = normalizedSets
        exercise.durationText = normalizedDuration
        exercise.restText = normalizedRest
        exercise.notes = normalizedNotes
    }
}

enum CatalogExercisePersistence {
    enum Error: Swift.Error, LocalizedError {
        case exerciseNotFoundAfterSave(UUID)

        var errorDescription: String? {
            switch self {
            case .exerciseNotFoundAfterSave(let id):
                return "Exercise \(id) was not found after saving."
            }
        }
    }

    static func saveNew(_ exercise: Exercise, in context: ModelContext) throws {
        context.insert(exercise)
        try saveAndVerify(exercise, in: context, operation: "create")
    }

    static func saveExisting(_ exercise: Exercise, in context: ModelContext) throws {
        try saveAndVerify(exercise, in: context, operation: "update")
    }

    private static func saveAndVerify(_ exercise: Exercise, in context: ModelContext, operation: String) throws {
        do {
            try context.save()
            let id = exercise.id
            let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
            guard (try context.fetch(descriptor)).first != nil else {
                throw Error.exerciseNotFoundAfterSave(id)
            }
        } catch {
            print("Catalog exercise \(operation) failed for '\(exercise.name)': \(error.localizedDescription)")
            throw error
        }
    }
}

// MARK: - Root Catalog (Categories = Activity)

struct CatalogView: View {
    private enum SheetRoute: String, Identifiable {
        case newActivity
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.isDataReady) private var isDataReady
    @Query(sort: \Activity.name) private var activities: [Activity]

    @State private var sheetRoute: SheetRoute?
    @State private var draftActivityName = ""
    @State private var renamingActivity: Activity?
    @State private var pendingDeletion: CatalogDeletion.Request?
    @State private var deletionError: String?

    // Helper function to count total exercises in an activity
    private func totalExerciseCount(for activity: Activity) -> Int {
        var count = 0
        for trainingType in activity.types {
            count += trainingType.exercises.count
            // Also count exercises in bouldering combinations
            for combination in trainingType.combinations {
                count += combination.exercises.count
            }
        }
        return count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(activities) { activity in
                        activityCard(for: activity)
                    }

                    Button {
                        guard isDataReady else { return }
                        draftActivityName = ""
                        sheetRoute = .newActivity
                    } label: {
                        Label("Add Category", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .padding(.top, 6)
                    .disabled(!isDataReady)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            // New Category
            .sheet(item: $sheetRoute) { route in
                switch route {
                case .newActivity:
                NameOnlySheet(title: "New Category", placeholder: "e.g. Core, Antagonist & Stabilizer…", name: $draftActivityName) {
                    guard !draftActivityName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    let a = Activity(name: draftActivityName.trimmingCharacters(in: .whitespaces))
                    context.insert(a)
                    try? context.save()
                }
                }
            }

            // Rename Category
            .sheet(item: $renamingActivity) { toRename in
                NameOnlySheet(title: "Rename Category", placeholder: "New name", name: $draftActivityName) {
                    toRename.name = draftActivityName.trimmingCharacters(in: .whitespaces)
                    try? context.save()
                }
            }
        }
        .navigationTitle("CATALOG")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog(
            pendingDeletion?.title ?? "Delete catalog node?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let request = pendingDeletion else { return }
                performDeletion(request)
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(pendingDeletion?.message ?? "")
        }
        .alert("Couldn’t delete catalog node", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deletionError ?? "")
        }
    }
    
    private func activityCard(for activity: Activity) -> some View {
        NavigationLink {
            ActivityDetailView(activity: activity)
        } label: {
            let exerciseCount = totalExerciseCount(for: activity)
            let typeCountText = "\(activity.types.count) training type\(activity.types.count == 1 ? "" : "s")"
            let exerciseCountText = "\(exerciseCount) exercise\(exerciseCount == 1 ? "" : "s")"
            CatalogCard(
                title: activity.name,
                subtitle: "\(typeCountText)\n\(exerciseCountText)",
                tint: activity.hue.color
            ) {
                EmptyView()
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename") {
                guard isDataReady else { return }
                draftActivityName = activity.name
                renamingActivity = activity
            }
            Button(role: .destructive) {
                guard isDataReady else { return }
                requestDeletion(for: .activity(activity))
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func requestDeletion(for target: CatalogDeletion.Target) {
        let request = CatalogDeletion.request(for: target, in: context)
        if request.impact.isEmpty {
            performDeletion(request)
        } else {
            pendingDeletion = request
        }
    }

    private func performDeletion(_ request: CatalogDeletion.Request) {
        pendingDeletion = nil
        do {
            try CatalogDeletion.delete(request, in: context)
        } catch {
            deletionError = error.localizedDescription
        }
    }
}

// MARK: - Activity detail (Training Types)

struct ActivityDetailView: View {
    private enum SheetRoute: String, Identifiable {
        case newType
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.isDataReady) private var isDataReady
    @Bindable var activity: Activity

    @State private var sheetRoute: SheetRoute?
    @State private var draftTypeName = ""
    @State private var draftArea = ""
    @State private var draftTypeDesc = ""
    @State private var renamingType: TrainingType?
    @State private var pendingDeletion: CatalogDeletion.Request?
    @State private var deletionError: String?

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
                        Button("Rename") {
                            guard isDataReady else { return }
                            draftTypeName = t.name
                            draftArea = t.area ?? ""
                            draftTypeDesc = t.typeDescription ?? ""
                            renamingType = t
                        }
                        Button(role: .destructive) {
                            guard isDataReady else { return }
                            requestDeletion(for: .trainingType(t))
                        } label: { Label("Delete", systemImage: "trash") }

                    }
                }
                .onDelete { idx in
                    guard isDataReady else { return }
                    let toDelete = idx.map { activity.types[$0] }
                    requestDeletion(for: toDelete.map(CatalogDeletion.Target.trainingType))
                }


                Button {
                    guard isDataReady else { return }
                    draftTypeName = ""; draftArea = ""; draftTypeDesc = ""
                    sheetRoute = .newType
                } label: {
                    Label("Add Training Type", systemImage: "plus")
                }
                .disabled(!isDataReady)
            } header: {
                Text("Training Types")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(activity.name)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
        }
        .confirmationDialog(
            pendingDeletion?.title ?? "Delete catalog node?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let request = pendingDeletion else { return }
                performDeletion(request)
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(pendingDeletion?.message ?? "")
        }
        .alert("Couldn’t delete catalog node", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deletionError ?? "")
        }

        // Create Type
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .newType:
            TrainingTypeEditSheet(
                title: "New Training Type",
                name: $draftTypeName,
                area: $draftArea,
                typeDescription: $draftTypeDesc
            ) {
                let t = TrainingType(
                    name: draftTypeName.trimmingCharacters(in: .whitespaces),
                    area: draftArea.trimmingCharacters(in: .whitespaces).isEmpty ? nil : draftArea,
                    typeDescription: draftTypeDesc.trimmingCharacters(in: .whitespaces).isEmpty ? nil : draftTypeDesc
                )
                activity.types.append(t)
                try? context.save()
            }
            }
        }

        // Rename/Edit Type
        .sheet(item: $renamingType) { tt in
            TrainingTypeEditSheet(
                title: "Rename Training Type",
                name: $draftTypeName,
                area: $draftArea,
                typeDescription: $draftTypeDesc
            ) {
                tt.name = draftTypeName.trimmingCharacters(in: .whitespaces)
                tt.area = draftArea.trimmingCharacters(in: .whitespaces).isEmpty ? nil : draftArea
                tt.typeDescription = draftTypeDesc.trimmingCharacters(in: .whitespaces).isEmpty ? nil : draftTypeDesc
                try? context.save()
            }
        }
    }

    private func requestDeletion(for target: CatalogDeletion.Target) {
        requestDeletion(for: [target])
    }

    private func requestDeletion(for targets: [CatalogDeletion.Target]) {
        guard !targets.isEmpty else { return }
        let request = CatalogDeletion.request(for: targets, in: context)
        if request.impact.isEmpty {
            performDeletion(request)
        } else {
            pendingDeletion = request
        }
    }

    private func performDeletion(_ request: CatalogDeletion.Request) {
        pendingDeletion = nil
        do {
            try CatalogDeletion.delete(request, in: context)
        } catch {
            deletionError = error.localizedDescription
        }
    }
}

// MARK: - Type detail (Exercises or Bouldering combinations)

struct TrainingTypeDetailView: View {
    private enum ModalRoute: String, Identifiable {
        case editAbout
        case newExercise

        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editMode) private var editMode
    @Bindable var trainingType: TrainingType
    let tint: Color

    @State private var modalRoute: ModalRoute?
    @State private var editingExercise: Exercise?
    @State private var movingExercise: Exercise?
    @State private var bulkMoveRequest: CatalogExerciseMoveSelection?
    @State private var selectedExerciseIDs = Set<UUID>()
    @State private var pendingDeletion: CatalogDeletion.Request?
    @State private var deletionError: String?

    // Drafts
    @State private var draftExName = ""
    @State private var draftArea = ""
    @State private var draftReps = ""
    @State private var draftSets = ""
    @State private var draftDuration = ""
    @State private var draftRest = ""
    @State private var draftNotes = ""
    @State private var draftDescription = ""
    @State private var draftAbout = ""

    private var exercisesByArea: [(String, [Exercise])] {
        let grouped = Dictionary(grouping: trainingType.exercises) { $0.area ?? "" }
        if grouped.keys.contains("Fingers") || grouped.keys.contains("Pull") {
            // For climbing-specific exercises, maintain Fingers/Pull order
            return ["Fingers", "Pull"].compactMap { area in
                if let exercises = grouped[area], !exercises.isEmpty {
                    return (area, exercises.sorted { $0.order < $1.order })
                }
                return nil
            }
        } else {
            // For other types, just group if there are areas
            return grouped
                .filter { !$0.key.isEmpty }
                .map { ($0.key, $0.value.sorted { $0.order < $1.order }) }
                .sorted(by: { $0.0 < $1.0 })
        }
    }

    private var ungroupedExercises: [Exercise] {
        trainingType.exercises.filter { $0.area == nil }.sorted { $0.order < $1.order }
    }

    private var selectedExercises: [Exercise] {
        trainingType.exercises.filter { selectedExerciseIDs.contains($0.id) }
    }
    
    // Define available areas for climbing exercises
    private var availableAreas: [String] {
        // Check if this is a climbing training type by looking at existing exercises
        let existingAreas = Set(trainingType.exercises.compactMap { $0.area })
        if existingAreas.contains("Fingers") || existingAreas.contains("Pull") ||
           trainingType.name.lowercased().contains("climb") {
            return ["Fingers", "Pull"]
        }
        return []
    }

    var body: some View {
        List(selection: $selectedExerciseIDs) {
            if let d = trainingType.typeDescription, !d.isEmpty {
                Section("About") {
                    Text(d).textCase(nil)
                }
            }

            if !trainingType.combinations.isEmpty {
                Section("Combinations") {
                    ForEach(trainingType.combinations) { combo in
                        NavigationLink {
                            CombinationDetailView(combo: combo, tint: tint)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(combo.name).font(.headline)
                                if let cd = combo.comboDescription, !cd.isEmpty {
                                    Text(cd).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                requestDeletion(for: .combination(combo))
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .textCase(nil)
                }
            }
            // Standalone exercises (also show for types that have combinations)
            // Grouped by area
            if !exercisesByArea.isEmpty {
                ForEach(exercisesByArea, id: \.0) { area, exercises in
                    Section(area) {
                        ForEach(exercises) { ex in
                            Button {
                                openEditor(for: ex)
                            } label: {
                                ExerciseRow(ex: ex, tint: tint)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    movingExercise = ex
                                } label: {
                                    Label("Move to…", systemImage: "folder")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    movingExercise = ex
                                } label: {
                                    Label("Move", systemImage: "arrow.up.and.down")
                                }
                                .tint(.blue)
                                Button(role: .destructive) {
                                    deleteExercise(ex)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .tag(ex.id)
                        }
                        .onDelete { indexes in
                            let toDelete = indexes.map { exercises[$0] }
                            deleteExercises(toDelete)
                        }

                    }
                }
            }

            // Ungrouped exercises
            if !ungroupedExercises.isEmpty {
                Section("Exercises") {
                    ForEach(ungroupedExercises) { ex in
                        Button {
                            openEditor(for: ex)
                        } label: {
                            ExerciseRow(ex: ex, tint: tint)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                movingExercise = ex
                            } label: {
                                Label("Move to…", systemImage: "folder")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                movingExercise = ex
                            } label: {
                                Label("Move", systemImage: "arrow.up.and.down")
                            }
                            .tint(.blue)
                            Button(role: .destructive) {
                                deleteExercise(ex)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .tag(ex.id)

                    }
                    .onDelete { indexes in
                        let toDelete = indexes.map { ungroupedExercises[$0] }
                        deleteExercises(toDelete)
                    }

                }
            }

            // Always allow adding an exercise
            Button { startNewExercise() } label: {
                Label("Add Exercise", systemImage: "plus")
            }
            .textCase(nil)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(trainingType.name)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit About") {
                    draftAbout = trainingType.typeDescription ?? ""
                    modalRoute = .editAbout
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    requestDeletion(for: .trainingType(trainingType))
                } label: {
                    Label("Delete Training Type", systemImage: "trash")
                }
            }
            if !selectedExerciseIDs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        bulkMoveRequest = CatalogExerciseMoveSelection(
                            exercises: selectedExercises,
                            sourceType: trainingType,
                            sourceCombination: nil
                        )
                    } label: {
                        Label("Move Selected", systemImage: "arrow.up.and.down")
                    }
                }
            }
        }
        .onChange(of: editMode?.wrappedValue) { _, newValue in
            if newValue != .active {
                selectedExerciseIDs.removeAll()
            }
        }
        .confirmationDialog(
            pendingDeletion?.title ?? "Delete catalog node?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let request = pendingDeletion else { return }
                performDeletion(request)
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(pendingDeletion?.message ?? "")
        }
        .alert("Couldn’t delete catalog item", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deletionError ?? "")
        }
        .sheet(item: $modalRoute) { route in
            switch route {
            case .editAbout:
                AboutEditSheet(title: "About \(trainingType.name)",
                               text: $draftAbout) {
                    let trimmed = draftAbout.trimmingCharacters(in: .whitespacesAndNewlines)
                    trainingType.typeDescription = trimmed.isEmpty ? nil : trimmed
                    try? context.save()
                }
            case .newExercise:
                ExerciseEditSheet(
                    title: "New Exercise",
                    name: $draftExName,
                    area: $draftArea,
                    reps: $draftReps,
                    sets: $draftSets,
                    duration: $draftDuration,
                    rest: $draftRest,
                    notes: $draftNotes,
                    description: $draftDescription,
                    availableAreas: availableAreas
                ) {
                    let nextOrder = (trainingType.exercises.map { $0.order }.max() ?? 0) + 1
                    let draft = CatalogExerciseDraft(
                        name: draftExName,
                        area: draftArea,
                        reps: draftReps,
                        sets: draftSets,
                        duration: draftDuration,
                        rest: draftRest,
                        notes: draftNotes,
                        description: draftDescription
                    )
                    let ex = draft.makeExercise(order: nextOrder)
                    trainingType.exercises.append(ex)
                    do {
                        try CatalogExercisePersistence.saveNew(ex, in: context)
                    } catch {
                        trainingType.exercises.removeAll { $0.id == ex.id }
                        context.delete(ex)
                    }
                }
            }
        }

        // EDIT exercise
        .sheet(item: $editingExercise) { ex in
            ExerciseEditSheet(
                title: "Edit Exercise",
                name: $draftExName,
                area: $draftArea,
                reps: $draftReps,
                sets: $draftSets,
                duration: $draftDuration,
                rest: $draftRest,
                notes: $draftNotes,
                description: $draftDescription,
                availableAreas: availableAreas
            ) {
                let draft = CatalogExerciseDraft(
                    name: draftExName,
                    area: draftArea,
                    reps: draftReps,
                    sets: draftSets,
                    duration: draftDuration,
                    rest: draftRest,
                    notes: draftNotes,
                    description: draftDescription
                )
                draft.apply(to: ex)
                do {
                    try CatalogExercisePersistence.saveExisting(ex, in: context)
                } catch {
                    print("Catalog exercise update could not be committed: \(error.localizedDescription)")
                }
            }
        }
        .sheet(item: $movingExercise) { ex in
            CatalogExerciseMoveSheet(exercise: ex, sourceType: trainingType, sourceCombination: nil)
        }
        .sheet(item: $bulkMoveRequest, onDismiss: {
            selectedExerciseIDs.removeAll()
        }) { request in
            CatalogExerciseMoveSheet(
                exercises: request.exercises,
                sourceType: request.sourceType,
                sourceCombination: request.sourceCombination
            )
        }
    }

    private func startNewExercise() {
        draftExName = ""; draftArea = ""; draftDescription = ""; draftReps = ""; draftSets = ""; draftRest = ""; draftNotes = ""; draftDuration = "";
        modalRoute = .newExercise
    }
    private func openEditor(for ex: Exercise) {
        draftExName = ex.name
        draftArea = ex.area ?? ""
        draftDescription = ex.exerciseDescription ?? ""
        draftReps = ex.repsText ?? ""
        draftSets = ex.setsText ?? ""
        draftDuration = ex.durationText ?? ""
        draftRest = ex.restText ?? ""
        draftNotes = ex.notes ?? ""
        editingExercise = ex
    }

    private func requestDeletion(for target: CatalogDeletion.Target) {
        let request = CatalogDeletion.request(for: target, in: context)
        if request.impact.isEmpty {
            performDeletion(request)
        } else {
            pendingDeletion = request
        }
    }

    private func performDeletion(_ request: CatalogDeletion.Request) {
        pendingDeletion = nil
        do {
            let deletesCurrentType = request.targets.contains { target in
                if case .trainingType(let targetType) = target {
                    return targetType.id == trainingType.id
                }
                return false
            }
            try CatalogDeletion.delete(request, in: context)
            if deletesCurrentType || !CatalogDeletion.exists(.trainingType(trainingType), in: context) {
                dismiss()
            }
        } catch {
            deletionError = error.localizedDescription
        }
    }

    private func deleteExercise(_ exercise: Exercise) {
        do {
            try CatalogDeletion.deleteExercisePlacement(
                exercise,
                from: trainingType,
                sourceCombination: nil,
                in: context
            )
            if !CatalogDeletion.exists(.trainingType(trainingType), in: context) {
                dismiss()
            }
        } catch {
            deletionError = error.localizedDescription
        }
    }

    private func deleteExercises(_ exercises: [Exercise]) {
        for exercise in exercises {
            deleteExercise(exercise)
        }
    }
}

// MARK: - Combination detail (Bouldering)

struct CombinationDetailView: View {
    private enum ModalRoute: String, Identifiable {
        case editAbout
        case newExercise

        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editMode) private var editMode
    @Bindable var combo: BoulderCombination
    let tint: Color

    @State private var editingExercise: Exercise?
    @State private var modalRoute: ModalRoute?
    @State private var movingExercise: Exercise?
    @State private var bulkMoveRequest: CatalogExerciseMoveSelection?
    @State private var selectedExerciseIDs = Set<UUID>()
    @State private var pendingDeletion: CatalogDeletion.Request?
    @State private var deletionError: String?

    @State private var draftExName = ""
    @State private var draftArea = ""
    @State private var draftReps = ""
    @State private var draftSets = ""
    @State private var draftDuration = ""
    @State private var draftRest = ""
    @State private var draftNotes = ""
    @State private var draftDesc = ""
    @State private var draftAbout = ""

    private var selectedExercises: [Exercise] {
        combo.exercises.filter { selectedExerciseIDs.contains($0.id) }
    }

    var body: some View {
        List(selection: $selectedExerciseIDs) {
            if let about = combo.comboDescription, !about.isEmpty {
                Section("About") { Text(about) }
            }
            Section("Exercises") {
                ForEach(combo.exercises.sorted { $0.order < $1.order }) { ex in
                    Button {
                        openEditor(for: ex)
                    } label: {
                        ExerciseRow(ex: ex, tint: tint)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            movingExercise = ex
                        } label: {
                            Label("Move to…", systemImage: "folder")
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            movingExercise = ex
                        } label: {
                            Label("Move", systemImage: "arrow.up.and.down")
                        }
                        .tint(.blue)
                        Button(role: .destructive) {
                            deleteExercise(ex)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteExercise(ex)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                        }
                    .tag(ex.id)
                }
                .onDelete { idx in
                    let sortedExercises = combo.exercises.sorted { $0.order < $1.order }
                    let toDelete = idx.map { sortedExercises[$0] }
                    deleteExercises(toDelete)
                }


                Button { startNewExercise() } label: {
                    Label("Add Exercise", systemImage: "plus")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(combo.name)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit About") {
                    draftAbout = combo.comboDescription ?? ""
                    modalRoute = .editAbout
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    requestDeletion(for: .combination(combo))
                } label: {
                    Label("Delete Combination", systemImage: "trash")
                }
            }
            if !selectedExerciseIDs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        bulkMoveRequest = CatalogExerciseMoveSelection(
                            exercises: selectedExercises,
                            sourceType: nil,
                            sourceCombination: combo
                        )
                    } label: {
                        Label("Move Selected", systemImage: "arrow.up.and.down")
                    }
                }
            }
        }
        .onChange(of: editMode?.wrappedValue) { _, newValue in
            if newValue != .active {
                selectedExerciseIDs.removeAll()
            }
        }
        .confirmationDialog(
            pendingDeletion?.title ?? "Delete catalog node?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let request = pendingDeletion else { return }
                performDeletion(request)
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(pendingDeletion?.message ?? "")
        }
        .alert("Couldn’t delete catalog item", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deletionError ?? "")
        }
        .sheet(item: $modalRoute) { route in
            switch route {
            case .editAbout:
                AboutEditSheet(title: "About \(combo.name)",
                               text: $draftAbout) {
                    let trimmed = draftAbout.trimmingCharacters(in: .whitespacesAndNewlines)
                    combo.comboDescription = trimmed.isEmpty ? nil : trimmed
                    try? context.save()
                }
            case .newExercise:
                ExerciseEditSheet(
                    title: "New Exercise",
                    name: $draftExName,
                    area: $draftArea,
                    reps: $draftReps,
                    sets: $draftSets,
                    duration: $draftDuration,
                    rest: $draftRest,
                    notes: $draftNotes,
                    description: $draftDesc,
                    availableAreas: []
                ) {
                    let nextOrder = (combo.exercises.map { $0.order }.max() ?? 0) + 1
                    let draft = CatalogExerciseDraft(
                        name: draftExName,
                        area: draftArea,
                        reps: draftReps,
                        sets: draftSets,
                        duration: draftDuration,
                        rest: draftRest,
                        notes: draftNotes,
                        description: draftDesc
                    )
                    let ex = draft.makeExercise(order: nextOrder)
                    combo.exercises.append(ex)
                    do {
                        try CatalogExercisePersistence.saveNew(ex, in: context)
                    } catch {
                        combo.exercises.removeAll { $0.id == ex.id }
                        context.delete(ex)
                    }
                }
            }
        }

        // Edit
        .sheet(item: $editingExercise) { ex in
            ExerciseEditSheet(
                title: "Edit Exercise",
                name: $draftExName,
                area: $draftArea,
                reps: $draftReps,
                sets: $draftSets,
                duration: $draftDuration,
                rest: $draftRest,
                notes: $draftNotes,
                description: $draftDesc,
                availableAreas: []
            ) {
                let draft = CatalogExerciseDraft(
                    name: draftExName,
                    area: draftArea,
                    reps: draftReps,
                    sets: draftSets,
                    duration: draftDuration,
                    rest: draftRest,
                    notes: draftNotes,
                    description: draftDesc
                )
                draft.apply(to: ex)
                do {
                    try CatalogExercisePersistence.saveExisting(ex, in: context)
                } catch {
                    print("Catalog exercise update could not be committed: \(error.localizedDescription)")
                }
            }
        }
        .sheet(item: $movingExercise) { ex in
            CatalogExerciseMoveSheet(exercise: ex, sourceType: nil, sourceCombination: combo)
        }
        .sheet(item: $bulkMoveRequest, onDismiss: {
            selectedExerciseIDs.removeAll()
        }) { request in
            CatalogExerciseMoveSheet(
                exercises: request.exercises,
                sourceType: request.sourceType,
                sourceCombination: request.sourceCombination
            )
        }
    }

    private func startNewExercise() {
        draftExName = ""; draftReps = ""; draftSets = ""; draftRest = ""; draftNotes = ""; draftDesc = ""; draftDuration = "";
        modalRoute = .newExercise
    }
    private func openEditor(for ex: Exercise) {
        draftExName = ex.name
        draftArea = ex.area ?? ""
        draftDesc = ex.exerciseDescription ?? ""
        draftReps = ex.repsText ?? ""
        draftSets = ex.setsText ?? ""
        draftDuration = ex.durationText ?? ""
        draftRest = ex.restText ?? ""
        draftNotes = ex.notes ?? ""
        editingExercise = ex
    }

    private func requestDeletion(for target: CatalogDeletion.Target) {
        let request = CatalogDeletion.request(for: target, in: context)
        if request.impact.isEmpty {
            performDeletion(request)
        } else {
            pendingDeletion = request
        }
    }

    private func performDeletion(_ request: CatalogDeletion.Request) {
        pendingDeletion = nil
        do {
            try CatalogDeletion.delete(request, in: context)
            if !CatalogDeletion.exists(.combination(combo), in: context) {
                dismiss()
            }
        } catch {
            deletionError = error.localizedDescription
        }
    }

    private func deleteExercise(_ exercise: Exercise) {
        do {
            try CatalogDeletion.deleteExercisePlacement(
                exercise,
                from: nil,
                sourceCombination: combo,
                in: context
            )
        } catch {
            deletionError = error.localizedDescription
        }
    }

    private func deleteExercises(_ exercises: [Exercise]) {
        for exercise in exercises {
            deleteExercise(exercise)
        }
    }
}

// MARK: - Shared UI bits
private struct MetricRow: View {
    let reps: String?
    let sets: String?
    let duration: String?
    let rest: String?

    var body: some View {
        HStack(spacing: 12) {
            metric("Reps", reps)
            metric("Sets", sets)
            metric("Duration", duration)
            metric("Rest", rest)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func metric(_ label: String, _ value: String?) -> some View {
        if let v = value, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HStack(spacing: 4) {
                Text(label).bold().foregroundStyle(.secondary)
                Text(v)
            }
        }
    }
}

private struct ExerciseRow: View {
    @Bindable var ex: Exercise
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(tint.gradient)
                    .frame(width: 8, height: 8)
                Text(ex.name)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            MetricRow(reps: ex.repsText, sets: ex.setsText,duration: ex.durationText, rest: ex.restText)
            if let desc = ex.exerciseDescription, !desc.isEmpty {
                Text(desc).font(.footnote)
            } else if let notes = ex.notes, !notes.isEmpty {
                Text(.init(notes)).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}


// MARK: - Sheets

struct NameOnlySheet: View {
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

struct TrainingTypeEditSheet: View {
    let title: String
    @Binding var name: String
    @Binding var area: String
    @Binding var typeDescription: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Area (optional)", text: $area)
                TextField("Description (optional)", text: $typeDescription)
            }
            .navigationTitle(title)
            .toolbar {
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

struct ExerciseEditSheet: View {
    let title: String
    @Binding var name: String
    @Binding var area: String
    @Binding var reps: String
    @Binding var sets: String
    @Binding var duration: String
    @Binding var rest: String
    @Binding var notes: String
    @Binding var description: String
    
    let availableAreas: [String]
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Description (optional)", text: $description)
                        .textCase(nil)
                }
                
                // Area selection for climbing exercises
                if !availableAreas.isEmpty {
                    Section {
                        Picker("Area", selection: $area) {
                            Text("None").tag("")
                            ForEach(availableAreas, id: \.self) { area in
                                Text(area).tag(area)
                            }
                        }
                        .pickerStyle(.menu)
                    } header: {
                        Text("CATEGORY")
                    } footer: {
                        Text("Choose the exercise category (e.g., Fingers, Pull).")
                    }
                }
                
                Section {
                    LabeledContent {
                        TextField("e.g. 15–25", text: $reps)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Label("Reps", systemImage: "repeat")
                        }
                    LabeledContent {
                        TextField("e.g. 2 min", text: $duration)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Label("Duration", systemImage: "clock")
                    }
                    LabeledContent {
                        TextField("e.g. 2–3", text: $sets)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Label("Sets", systemImage: "square.grid.3x3")
                    }
                    
                    LabeledContent {
                        TextField("e.g. 3 min", text: $rest)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Label("Rest", systemImage: "hourglass")
                    }
                    .textCase(nil)
                } header: {
                    Text("DISPLAY FIELDS")
                } footer: {
                    Text("These are display strings (e.g., \"6-10\", \"45 sec\", \"3 min\"). Analytics come from your logs.")
                }
                
                Section("Preview") {
                    MetricRow(reps: reps.isEmpty ? nil : reps,
                              sets: sets.isEmpty ? nil : sets,
                              duration: duration.isEmpty ? nil : duration,
                              rest: rest.isEmpty ? nil : rest)
                }
                
                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(); dismiss() }
                }
            }
        }
    }
}
// MARK: - Reusable About editor
struct AboutEditSheet: View {
    let title: String
    @Binding var text: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $text)
                    .frame(minHeight: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.quaternary)
                    )
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(); dismiss() }
                }
            }
        }
    }
}
