import Foundation

enum PlanDayExerciseOrdering {
    static func sortedNames(
        _ names: [String],
        manualOrder: [String: Int],
        catalogOrder: [String: Int],
        isQuickLogged: (String) -> Bool
    ) -> [String] {
        names.sorted { first, second in
            let firstManualOrder = manualOrder[first]
            let secondManualOrder = manualOrder[second]

            if let firstManualOrder, let secondManualOrder, firstManualOrder != secondManualOrder {
                return firstManualOrder < secondManualOrder
            }

            if firstManualOrder != nil, secondManualOrder == nil {
                return true
            }
            if firstManualOrder == nil, secondManualOrder != nil {
                return false
            }

            let firstIsQuickLogged = isQuickLogged(first)
            let secondIsQuickLogged = isQuickLogged(second)
            if firstIsQuickLogged != secondIsQuickLogged {
                return !firstIsQuickLogged
            }

            let firstCatalogOrder = catalogOrder[first] ?? .max
            let secondCatalogOrder = catalogOrder[second] ?? .max
            if firstCatalogOrder != secondCatalogOrder {
                return firstCatalogOrder < secondCatalogOrder
            }

            return first.localizedStandardCompare(second) == .orderedAscending
        }
    }
}
