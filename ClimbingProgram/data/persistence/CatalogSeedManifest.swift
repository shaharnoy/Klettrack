import Foundation

struct CatalogExerciseSeed {
    let key: String
    let name: String
    let aliases: [String]
    let order: Int
    let area: String?
    let exerciseDescription: String?
    let reps: String?
    let duration: String?
    let sets: String?
    let rest: String?
    let notes: String?
}

final class CatalogCombinationSeed {
    let key: String
    let name: String
    let aliases: [String]
    let combinationDescription: String?
    var exercises: [CatalogExerciseSeed] = []

    init(key: String, name: String, aliases: [String] = [], combinationDescription: String? = nil) {
        self.key = key
        self.name = name
        self.aliases = aliases
        self.combinationDescription = combinationDescription
    }
}

final class CatalogTypeSeed {
    let key: String
    let name: String
    let aliases: [String]
    let area: String?
    let typeDescription: String?
    var exercises: [CatalogExerciseSeed] = []
    var combinations: [CatalogCombinationSeed] = []

    init(
        key: String,
        name: String,
        aliases: [String] = [],
        area: String? = nil,
        typeDescription: String? = nil
    ) {
        self.key = key
        self.name = name
        self.aliases = aliases
        self.area = area
        self.typeDescription = typeDescription
    }
}

final class CatalogActivitySeed {
    let key: String
    let name: String
    let aliases: [String]
    var types: [CatalogTypeSeed] = []

    init(key: String, name: String, aliases: [String] = []) {
        self.key = key
        self.name = name
        self.aliases = aliases
    }
}

struct CatalogSeedManifest {
    var activities: [CatalogActivitySeed] = []

    var allKeys: [String] {
        var keys: [String] = []
        for activity in activities {
            keys.append(activity.key)
            for type in activity.types {
                keys.append(type.key)
                keys.append(contentsOf: type.exercises.map(\.key))
                for combination in type.combinations {
                    keys.append(combination.key)
                    keys.append(contentsOf: combination.exercises.map(\.key))
                }
            }
        }
        return keys
    }

    func duplicateKeys() -> [String] {
        Dictionary(grouping: allKeys, by: { $0 })
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
    }
}

final class CatalogSeedManifestBuilder {
    private(set) var manifest = CatalogSeedManifest()

    func activity(_ name: String, key: String, aliases: [String] = []) -> CatalogActivitySeed {
        let seed = CatalogActivitySeed(key: key, name: name, aliases: aliases)
        manifest.activities.append(seed)
        return seed
    }
}

extension CatalogActivitySeed {
    func type(
        _ name: String,
        key: String,
        aliases: [String] = [],
        area: String? = nil,
        typeDescription: String? = nil
    ) -> CatalogTypeSeed {
        let seed = CatalogTypeSeed(
            key: key,
            name: name,
            aliases: aliases,
            area: area,
            typeDescription: typeDescription
        )
        types.append(seed)
        return seed
    }
}

struct CatalogSeedReport: Equatable {
    struct Issue: Equatable {
        let seedKey: String?
        let message: String
    }

    var inserted = 0
    var claimed = 0
    var skipped = 0
    var issues: [Issue] = []

    var summary: String {
        "Catalog seed: inserted=\(inserted), claimed=\(claimed), skipped=\(skipped), failures=\(issues.count)"
    }

    mutating func merge(_ other: CatalogSeedReport) {
        inserted += other.inserted
        claimed += other.claimed
        skipped += other.skipped
        issues.append(contentsOf: other.issues)
    }
}
