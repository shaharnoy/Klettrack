import Foundation
import SwiftData

@MainActor
enum GradeMigrationService {
    struct Summary: Equatable {
        let count: Int
    }

    static func availableOldGrades(in context: ModelContext, gym: String) -> [String] {
        let trimmedGym = gym.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGym.isEmpty else { return [] }

        let descriptor = FetchDescriptor<ClimbEntry>(
            predicate: #Predicate { entry in
                entry.gym == trimmedGym
            },
            sortBy: [SortDescriptor(\.grade, order: .forward)]
        )
        let entries = (try? context.fetch(descriptor)) ?? []
        return distinctSortedGrades(from: entries)
    }

    static func distinctSortedGrades(from entries: [ClimbEntry]) -> [String] {
        let grades = entries
            .map { $0.grade.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Array(Set(grades)).sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    static func matchingCount(in context: ModelContext, gym: String, oldGrade: String) -> Int {
        let trimmedGym = gym.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOldGrade = oldGrade.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGym.isEmpty, !trimmedOldGrade.isEmpty else { return 0 }

        let descriptor = FetchDescriptor<ClimbEntry>(
            predicate: #Predicate { entry in
                entry.gym == trimmedGym && entry.grade == trimmedOldGrade
            }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    @discardableResult
    static func migrate(
        in context: ModelContext,
        gym: String,
        oldGrade: String,
        newGrade: String,
        newFeelsLikeGrade: String?
    ) throws -> Summary {
        let trimmedGym = gym.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOldGrade = oldGrade.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNewGrade = newGrade.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFeelsLike = newFeelsLikeGrade?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedGym.isEmpty, !trimmedOldGrade.isEmpty, !trimmedNewGrade.isEmpty else {
            return Summary(count: 0)
        }

        let descriptor = FetchDescriptor<ClimbEntry>(
            predicate: #Predicate { entry in
                entry.gym == trimmedGym && entry.grade == trimmedOldGrade
            }
        )
        let entries = try context.fetch(descriptor)

        for entry in entries {
            entry.grade = trimmedNewGrade
            if let trimmedFeelsLike, !trimmedFeelsLike.isEmpty {
                entry.feelsLikeGrade = trimmedFeelsLike
            }
        }

        try context.save()
        return Summary(count: entries.count)
    }
}
