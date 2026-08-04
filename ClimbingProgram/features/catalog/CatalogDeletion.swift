import Foundation
import SwiftData

enum CatalogDeletion {
    enum Target: Identifiable {
        case activity(Activity)
        case trainingType(TrainingType)
        case combination(BoulderCombination)

        var id: UUID {
            switch self {
            case .activity(let activity): return activity.id
            case .trainingType(let trainingType): return trainingType.id
            case .combination(let combination): return combination.id
            }
        }

        var name: String {
            switch self {
            case .activity(let activity): return activity.name
            case .trainingType(let trainingType): return trainingType.name
            case .combination(let combination): return combination.name
            }
        }

        var kindName: String {
            switch self {
            case .activity: return "category"
            case .trainingType: return "training type"
            case .combination: return "combination"
            }
        }
    }

    struct Impact {
        let nodeCount: Int
        let exerciseCount: Int

        var isEmpty: Bool { nodeCount == 0 && exerciseCount == 0 }

        var message: String {
            var parts: [String] = []
            if nodeCount > 0 {
                parts.append("\(nodeCount) nested catalog node\(nodeCount == 1 ? "" : "s")")
            }
            if exerciseCount > 0 {
                parts.append("\(exerciseCount) exercise\(exerciseCount == 1 ? "" : "s")")
            }
            guard !parts.isEmpty else {
                return "This empty catalog node will be deleted."
            }
            return "This will delete " + parts.joined(separator: " and ") + ". Plans, logs, climbs, and plan-local exercise data will be preserved."
        }
    }

    struct Request: Identifiable {
        let id = UUID()
        let targets: [Target]
        let impact: Impact

        var title: String {
            if targets.count == 1, let target = targets.first {
                return "Delete \(target.name)?"
            }
            return "Delete \(targets.count) catalog nodes?"
        }

        var message: String { impact.message }
    }

    static func request(for target: Target, in context: ModelContext) -> Request {
        request(for: [target], in: context)
    }

    static func request(for targets: [Target], in context: ModelContext) -> Request {
        let graph = deletionGraph(for: targets)
        let targetTypeIDs = Set(targets.compactMap { target -> UUID? in
            if case .trainingType(let trainingType) = target { return trainingType.id }
            return nil
        })
        let targetCombinationIDs = Set(targets.compactMap { target -> UUID? in
            if case .combination(let combination) = target { return combination.id }
            return nil
        })
        let impact = Impact(
            nodeCount: graph.typeIDs.subtracting(targetTypeIDs).count
                + graph.combinationIDs.subtracting(targetCombinationIDs).count,
            exerciseCount: graph.exerciseIDs.count
        )
        return Request(targets: targets, impact: impact)
    }

    static func delete(_ target: Target, in context: ModelContext) throws {
        try delete([target], in: context)
    }

    static func delete(_ request: Request, in context: ModelContext) throws {
        try delete(request.targets, in: context)
    }

    static func delete(_ targets: [Target], in context: ModelContext) throws {
        guard !targets.isEmpty else { return }

        let graph = deletionGraph(for: targets)
        let activities = fetchActivities(in: context)
        let trainingTypes = fetchTrainingTypes(in: context)
        let combinations = fetchCombinations(in: context)
        let exercises = fetchExercises(in: context)

        for activity in activities {
            activity.types.removeAll { graph.typeIDs.contains($0.id) }
        }
        for trainingType in trainingTypes {
            trainingType.combinations.removeAll { graph.combinationIDs.contains($0.id) }
            trainingType.exercises.removeAll { graph.exerciseIDs.contains($0.id) && graph.typeIDs.contains(trainingType.id) }
        }
        for combination in combinations where graph.combinationIDs.contains(combination.id) {
            combination.exercises.removeAll { graph.exerciseIDs.contains($0.id) }
        }

        for combination in combinations where graph.combinationIDs.contains(combination.id) {
            context.delete(combination)
        }
        for trainingType in trainingTypes where graph.typeIDs.contains(trainingType.id) {
            context.delete(trainingType)
        }
        for activity in activities where graph.activityIDs.contains(activity.id) {
            context.delete(activity)
        }

        let remainingExerciseIDs = catalogExerciseIDs(in: context)
        for exercise in exercises where graph.exerciseIDs.contains(exercise.id) && !remainingExerciseIDs.contains(exercise.id) {
            clearPlanCatalogReferences(for: exercise.id, in: context)
            context.delete(exercise)
        }

        removeEmptyImportedContainers(in: context)
        try context.save()
    }

    static func deleteExercisePlacement(
        _ exercise: Exercise,
        from sourceType: TrainingType?,
        sourceCombination: BoulderCombination?,
        in context: ModelContext
    ) throws {
        detachExercise(exercise, from: sourceType, sourceCombination: sourceCombination)

        let remainingExerciseIDs = catalogExerciseIDs(in: context)
        if !remainingExerciseIDs.contains(exercise.id) {
            clearPlanCatalogReferences(for: exercise.id, in: context)
            context.delete(exercise)
        }

        removeEmptyImportedContainers(in: context)
        try context.save()
    }

    static func detachExercise(
        _ exercise: Exercise,
        from sourceType: TrainingType?,
        sourceCombination: BoulderCombination?
    ) {
        sourceType?.exercises.removeAll { $0.id == exercise.id }
        sourceCombination?.exercises.removeAll { $0.id == exercise.id }
    }

    static func removeEmptyImportedContainers(in context: ModelContext) {
        let activities = fetchActivities(in: context)
        for activity in activities where normalized(activity.name) == normalized("Imported") {
            let importedTypes = activity.types.filter { normalized($0.name) == normalized("Imported Plans") }
            for trainingType in importedTypes where trainingType.exercises.isEmpty && trainingType.combinations.isEmpty {
                activity.types.removeAll { $0.id == trainingType.id }
                context.delete(trainingType)
            }

            if activity.types.isEmpty {
                context.delete(activity)
            }
        }
    }

    static func exists(_ target: Target, in context: ModelContext) -> Bool {
        switch target {
        case .activity(let activity):
            return fetchActivities(in: context).contains { $0.id == activity.id }
        case .trainingType(let trainingType):
            return fetchTrainingTypes(in: context).contains { $0.id == trainingType.id }
        case .combination(let combination):
            return fetchCombinations(in: context).contains { $0.id == combination.id }
        }
    }

    private struct DeletionGraph {
        var activityIDs = Set<UUID>()
        var typeIDs = Set<UUID>()
        var combinationIDs = Set<UUID>()
        var exerciseIDs = Set<UUID>()
    }

    private static func deletionGraph(for targets: [Target]) -> DeletionGraph {
        let activities = targets.compactMap { target -> Activity? in
            if case .activity(let activity) = target { return activity }
            return nil
        }
        let trainingTypes = targets.compactMap { target -> TrainingType? in
            if case .trainingType(let trainingType) = target { return trainingType }
            return nil
        }
        let combinations = targets.compactMap { target -> BoulderCombination? in
            if case .combination(let combination) = target { return combination }
            return nil
        }

        var graph = DeletionGraph()
        for activity in activities {
            graph.activityIDs.insert(activity.id)
            for trainingType in activity.types {
                graph.typeIDs.insert(trainingType.id)
                graph.combinationIDs.formUnion(trainingType.combinations.map(\.id))
                graph.exerciseIDs.formUnion(trainingType.exercises.map(\.id))
                graph.exerciseIDs.formUnion(trainingType.combinations.flatMap(\.exercises).map(\.id))
            }
        }
        for trainingType in trainingTypes {
            graph.typeIDs.insert(trainingType.id)
            graph.combinationIDs.formUnion(trainingType.combinations.map(\.id))
            graph.exerciseIDs.formUnion(trainingType.exercises.map(\.id))
            graph.exerciseIDs.formUnion(trainingType.combinations.flatMap(\.exercises).map(\.id))
        }
        for combination in combinations {
            graph.combinationIDs.insert(combination.id)
            graph.exerciseIDs.formUnion(combination.exercises.map(\.id))
        }
        return graph
    }

    private static func clearPlanCatalogReferences(for exerciseID: UUID, in context: ModelContext) {
        let definitions = (try? context.fetch(FetchDescriptor<PlanExerciseDefinition>())) ?? []
        for definition in definitions where definition.catalogExerciseID == exerciseID {
            definition.catalogExerciseID = nil
        }

        let days = (try? context.fetch(FetchDescriptor<PlanDay>())) ?? []
        for day in days {
            day.chosenExerciseIDs.removeAll { $0 == exerciseID }
            day.exerciseOrderByID.removeValue(forKey: exerciseID.uuidString)
        }
    }

    private static func catalogExerciseIDs(in context: ModelContext) -> Set<UUID> {
        let activities = fetchActivities(in: context)
        var ids = Set<UUID>()
        for activity in activities {
            for trainingType in activity.types {
                ids.formUnion(trainingType.exercises.map(\.id))
                for combination in trainingType.combinations {
                    ids.formUnion(combination.exercises.map(\.id))
                }
            }
        }
        return ids
    }

    private static func fetchActivities(in context: ModelContext) -> [Activity] {
        (try? context.fetch(FetchDescriptor<Activity>())) ?? []
    }

    private static func fetchTrainingTypes(in context: ModelContext) -> [TrainingType] {
        (try? context.fetch(FetchDescriptor<TrainingType>())) ?? []
    }

    private static func fetchCombinations(in context: ModelContext) -> [BoulderCombination] {
        (try? context.fetch(FetchDescriptor<BoulderCombination>())) ?? []
    }

    private static func fetchExercises(in context: ModelContext) -> [Exercise] {
        (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
