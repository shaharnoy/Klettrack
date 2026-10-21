import SwiftData

struct CatalogSeeder {
    static func reconcile(
        _ manifest: CatalogSeedManifest,
        in context: ModelContext,
        loadTombstones: (ModelContext) throws -> Set<String> = CatalogSeedTombstoneStore.keys,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) -> CatalogSeedReport {
        var report = CatalogSeedReport()
        let duplicateKeys = manifest.duplicateKeys()
        guard duplicateKeys.isEmpty else {
            report.issues.append(.init(seedKey: nil, message: "Duplicate catalog seed keys: \(duplicateKeys.joined(separator: ", "))"))
            return report
        }

        let tombstones: Set<String>
        do {
            tombstones = try loadTombstones(context)
        } catch {
            report.issues.append(.init(seedKey: nil, message: "Could not read catalog deletion markers: \(error.localizedDescription)"))
            return report
        }

        for activitySeed in manifest.activities {
            var activityReport = CatalogSeedReport()
            do {
                try reconcile(activitySeed, tombstones: tombstones, in: context, report: &activityReport)
                try save(context)
                report.merge(activityReport)
            } catch {
                context.rollback()
                report.issues.append(.init(seedKey: activitySeed.key, message: error.localizedDescription))
            }
        }
        return report
    }

    private static func reconcile(
        _ seed: CatalogActivitySeed,
        tombstones: Set<String>,
        in context: ModelContext,
        report: inout CatalogSeedReport
    ) throws {
        guard !tombstones.contains(seed.key) else {
            report.skipped += 1
            return
        }

        let activities = try context.fetch(FetchDescriptor<Activity>())
        let activity: Activity
        if let keyed = activities.first(where: { $0.seedKey == seed.key }) {
            activity = keyed
        } else if let legacy = exactLegacyActivity(for: seed, in: activities)
            ?? structuralLegacyActivity(for: seed, in: activities) {
            legacy.seedKey = seed.key
            report.claimed += 1
            activity = legacy
        } else {
            activity = Activity(seedKey: seed.key, name: seed.name)
            context.insert(activity)
            report.inserted += 1
        }

        for typeSeed in seed.types {
            try reconcile(typeSeed, in: activity, tombstones: tombstones, context: context, report: &report)
        }
    }

    private static func reconcile(
        _ seed: CatalogTypeSeed,
        in activity: Activity,
        tombstones: Set<String>,
        context: ModelContext,
        report: inout CatalogSeedReport
    ) throws {
        guard !tombstones.contains(seed.key) else {
            report.skipped += 1
            return
        }

        let type: TrainingType
        if let keyed = activity.types.first(where: { $0.seedKey == seed.key }) {
            type = keyed
        } else if let legacy = exactLegacyType(for: seed, in: activity.types)
            ?? structuralLegacyType(for: seed, in: activity.types) {
            legacy.seedKey = seed.key
            report.claimed += 1
            type = legacy
        } else {
            type = TrainingType(seedKey: seed.key, name: seed.name, area: seed.area, typeDescription: seed.typeDescription)
            activity.types.append(type)
            report.inserted += 1
        }

        for exerciseSeed in seed.exercises {
            try reconcile(exerciseSeed, in: type, tombstones: tombstones, context: context, report: &report)
        }
        for combinationSeed in seed.combinations {
            try reconcile(combinationSeed, in: type, tombstones: tombstones, context: context, report: &report)
        }
    }

    private static func reconcile(
        _ seed: CatalogCombinationSeed,
        in type: TrainingType,
        tombstones: Set<String>,
        context: ModelContext,
        report: inout CatalogSeedReport
    ) throws {
        guard !tombstones.contains(seed.key) else {
            report.skipped += 1
            return
        }

        let combination: BoulderCombination
        if let keyed = type.combinations.first(where: { $0.seedKey == seed.key }) {
            combination = keyed
        } else if let legacy = exactLegacyCombination(for: seed, in: type.combinations)
            ?? structuralLegacyCombination(for: seed, in: type.combinations) {
            legacy.seedKey = seed.key
            report.claimed += 1
            combination = legacy
        } else {
            combination = BoulderCombination(seedKey: seed.key, name: seed.name, comboDescription: seed.combinationDescription)
            type.combinations.append(combination)
            report.inserted += 1
        }

        for exerciseSeed in seed.exercises {
            try reconcile(exerciseSeed, in: combination, tombstones: tombstones, context: context, report: &report)
        }
    }

    private static func reconcile(
        _ seed: CatalogExerciseSeed,
        in type: TrainingType,
        tombstones: Set<String>,
        context: ModelContext,
        report: inout CatalogSeedReport
    ) throws {
        guard !tombstones.contains(seed.key) else {
            report.skipped += 1
            return
        }
        if try existingExercise(seedKey: seed.key, in: context) != nil { return }

        if let legacy = exactLegacyExercise(for: seed, in: type.exercises)
            ?? structuralLegacyExercise(for: seed, in: type.exercises) {
            legacy.seedKey = seed.key
            report.claimed += 1
            return
        }

        type.exercises.append(makeExercise(from: seed))
        report.inserted += 1
    }

    private static func reconcile(
        _ seed: CatalogExerciseSeed,
        in combination: BoulderCombination,
        tombstones: Set<String>,
        context: ModelContext,
        report: inout CatalogSeedReport
    ) throws {
        guard !tombstones.contains(seed.key) else {
            report.skipped += 1
            return
        }
        if try existingExercise(seedKey: seed.key, in: context) != nil { return }

        if let legacy = exactLegacyExercise(for: seed, in: combination.exercises)
            ?? structuralLegacyExercise(for: seed, in: combination.exercises) {
            legacy.seedKey = seed.key
            report.claimed += 1
            return
        }

        combination.exercises.append(makeExercise(from: seed))
        report.inserted += 1
    }

    private static func exactLegacyActivity(for seed: CatalogActivitySeed, in activities: [Activity]) -> Activity? {
        unique(activities.filter { $0.seedKey == nil && names(for: seed.name, aliases: seed.aliases).contains($0.name) })
    }

    private static func structuralLegacyActivity(for seed: CatalogActivitySeed, in activities: [Activity]) -> Activity? {
        guard !seed.types.isEmpty else { return nil }
        return unique(activities.filter { activity in
            guard activity.seedKey == nil else { return false }
            return seed.types.allSatisfy { typeSeed in
                activity.types.contains { names(for: typeSeed.name, aliases: typeSeed.aliases).contains($0.name) }
            }
        })
    }

    private static func exactLegacyType(for seed: CatalogTypeSeed, in types: [TrainingType]) -> TrainingType? {
        unique(types.filter { $0.seedKey == nil && names(for: seed.name, aliases: seed.aliases).contains($0.name) })
    }

    private static func structuralLegacyType(for seed: CatalogTypeSeed, in types: [TrainingType]) -> TrainingType? {
        let childNames = seed.exercises.map { names(for: $0.name, aliases: $0.aliases) }
            + seed.combinations.map { names(for: $0.name, aliases: $0.aliases) }
        guard !childNames.isEmpty else { return nil }
        return unique(types.filter { type in
            guard type.seedKey == nil else { return false }
            let existingNames = Set(type.exercises.map(\.name) + type.combinations.map(\.name))
            return childNames.allSatisfy { !$0.isDisjoint(with: existingNames) }
        })
    }

    private static func exactLegacyCombination(for seed: CatalogCombinationSeed, in combinations: [BoulderCombination]) -> BoulderCombination? {
        unique(combinations.filter { $0.seedKey == nil && names(for: seed.name, aliases: seed.aliases).contains($0.name) })
    }

    private static func structuralLegacyCombination(for seed: CatalogCombinationSeed, in combinations: [BoulderCombination]) -> BoulderCombination? {
        guard !seed.exercises.isEmpty else { return nil }
        return unique(combinations.filter { combination in
            guard combination.seedKey == nil else { return false }
            let existingNames = Set(combination.exercises.map(\.name))
            return seed.exercises.allSatisfy { !names(for: $0.name, aliases: $0.aliases).isDisjoint(with: existingNames) }
        })
    }

    private static func exactLegacyExercise(for seed: CatalogExerciseSeed, in exercises: [Exercise]) -> Exercise? {
        unique(exercises.filter { $0.seedKey == nil && names(for: seed.name, aliases: seed.aliases).contains($0.name) })
    }

    private static func structuralLegacyExercise(for seed: CatalogExerciseSeed, in exercises: [Exercise]) -> Exercise? {
        unique(exercises.filter { exercise in
            exercise.seedKey == nil
                && exercise.order == seed.order
                && exercise.area == seed.area
                && exercise.exerciseDescription == seed.exerciseDescription
                && exercise.repsText == seed.reps
                && exercise.durationText == seed.duration
                && exercise.setsText == seed.sets
                && exercise.restText == seed.rest
                && exercise.notes == seed.notes
        })
    }

    private static func makeExercise(from seed: CatalogExerciseSeed) -> Exercise {
        Exercise(
            seedKey: seed.key,
            name: seed.name,
            area: seed.area,
            order: seed.order,
            exerciseDescription: seed.exerciseDescription,
            repsText: seed.reps,
            durationText: seed.duration,
            setsText: seed.sets,
            restText: seed.rest,
            notes: seed.notes
        )
    }

    private static func existingExercise(seedKey: String, in context: ModelContext) throws -> Exercise? {
        try context.fetch(FetchDescriptor<Exercise>()).first { $0.seedKey == seedKey }
    }

    private static func names(for name: String, aliases: [String]) -> Set<String> {
        Set([name] + aliases)
    }

    private static func unique<T>(_ candidates: [T]) -> T? {
        candidates.count == 1 ? candidates[0] : nil
    }
}
