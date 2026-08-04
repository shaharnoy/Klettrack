import SwiftUI
import SwiftData

enum CatalogReassignment {
    struct Destination: Identifiable {
        enum Kind {
            case trainingType
            case combination
        }

        let id: UUID
        let activityName: String
        let typeName: String
        let name: String
        let kind: Kind
        let type: TrainingType
        let combination: BoulderCombination?

        var label: String {
            if let combination {
                return "\(activityName) › \(typeName) › \(combination.name)"
            }
            return "\(activityName) › \(typeName)"
        }
    }

    static func destinations(in context: ModelContext) -> [Destination] {
        let activities = (try? context.fetch(FetchDescriptor<Activity>(sortBy: [SortDescriptor(\.name)]))) ?? []
        return activities.flatMap { activity in
            activity.types.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.flatMap { type in
                let typeDestination = Destination(id: type.id, activityName: activity.name, typeName: type.name, name: type.name, kind: .trainingType, type: type, combination: nil)
                let combinations = type.combinations.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map {
                    Destination(id: $0.id, activityName: activity.name, typeName: type.name, name: $0.name, kind: .combination, type: type, combination: $0)
                }
                return [typeDestination] + combinations
            }
        }
    }

    static func move(
        _ exercise: Exercise,
        from sourceType: TrainingType?,
        sourceCombination: BoulderCombination?,
        to destination: Destination,
        in context: ModelContext
    ) throws {
        try move(
            [exercise],
            from: sourceType,
            sourceCombination: sourceCombination,
            to: destination,
            in: context
        )
    }

    static func move(
        _ exercises: [Exercise],
        from sourceType: TrainingType?,
        sourceCombination: BoulderCombination?,
        to destination: Destination,
        in context: ModelContext
    ) throws {
        var seenIDs = Set<UUID>()
        let uniqueExercises = exercises.filter { seenIDs.insert($0.id).inserted }

        for exercise in uniqueExercises {
            CatalogDeletion.detachExercise(
                exercise,
                from: sourceType,
                sourceCombination: sourceCombination
            )
        }

        if let combination = destination.combination {
            for exercise in uniqueExercises where !combination.exercises.contains(where: { $0.id == exercise.id }) {
                combination.exercises.append(exercise)
            }
        } else {
            for exercise in uniqueExercises where !destination.type.exercises.contains(where: { $0.id == exercise.id }) {
                destination.type.exercises.append(exercise)
            }
        }

        CatalogDeletion.removeEmptyImportedContainers(in: context)
        try context.save()
    }
}

struct CatalogExerciseMoveSelection: Identifiable {
    let id = UUID()
    let exercises: [Exercise]
    let sourceType: TrainingType?
    let sourceCombination: BoulderCombination?
}

struct CatalogExerciseMoveSheet: View {
    let exercises: [Exercise]
    let sourceType: TrainingType?
    let sourceCombination: BoulderCombination?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var selectedDestination: CatalogReassignment.Destination?
    @State private var errorMessage: String?

    private var destinations: [CatalogReassignment.Destination] {
        CatalogReassignment.destinations(in: context).filter { destination in
            destination.id != sourceType?.id && destination.id != sourceCombination?.id
        }
    }

    var body: some View {
        NavigationStack {
            List(destinations) { destination in
                Button {
                    selectedDestination = destination
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(destination.name)
                                .font(.headline)
                            Text(destination.label)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedDestination?.id == destination.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(exercises.count == 1 ? "Move Exercise" : "Move Exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        guard let selectedDestination else { return }
                        do {
                            try CatalogReassignment.move(exercises, from: sourceType, sourceCombination: sourceCombination, to: selectedDestination, in: context)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(selectedDestination == nil)
                }
            }
            .alert("Couldn’t move exercise", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    init(
        exercise: Exercise,
        sourceType: TrainingType?,
        sourceCombination: BoulderCombination?
    ) {
        self.exercises = [exercise]
        self.sourceType = sourceType
        self.sourceCombination = sourceCombination
    }

    init(
        exercises: [Exercise],
        sourceType: TrainingType?,
        sourceCombination: BoulderCombination?
    ) {
        self.exercises = exercises
        self.sourceType = sourceType
        self.sourceCombination = sourceCombination
    }
}
