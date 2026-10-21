import SwiftData

enum CatalogSeedTombstoneStore {
    static func keys(in context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<DeletedCatalogSeed>()).map(\.seedKey))
    }

    static func contains(_ seedKey: String, in context: ModelContext) throws -> Bool {
        try keys(in: context).contains(seedKey)
    }

    static func record(_ seedKey: String?, in context: ModelContext) throws {
        guard let seedKey, try !contains(seedKey, in: context) else { return }
        context.insert(DeletedCatalogSeed(seedKey: seedKey))
    }
}
