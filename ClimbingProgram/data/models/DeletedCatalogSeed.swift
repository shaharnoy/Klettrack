import SwiftData

/// Remembers that a user intentionally deleted an app-provided catalog item.
@Model
final class DeletedCatalogSeed {
    var seedKey: String = ""

    init(seedKey: String) {
        self.seedKey = seedKey
    }
}
