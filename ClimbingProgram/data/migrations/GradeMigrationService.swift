import Foundation
import SwiftData

@MainActor
enum GradeMigrationService {
    struct Summary: Equatable {
        let count: Int
        let rows: [RowSummary]
    }

    struct GradeCount: Equatable, Identifiable {
        var id: String { grade }
        let grade: String
        let count: Int
    }

    struct Mapping: Equatable {
        let oldGrade: String
        let newGrade: String
        let newFeelsLikeGrade: String?
    }

    struct RowSummary: Equatable, Identifiable {
        var id: String { oldGrade }
        let oldGrade: String
        let newGrade: String
        let newFeelsLikeGrade: String?
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

    static func gradeCounts(in context: ModelContext, gym: String) -> [GradeCount] {
        let trimmedGym = gym.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGym.isEmpty else { return [] }

        let descriptor = FetchDescriptor<ClimbEntry>(
            predicate: #Predicate { entry in
                entry.gym == trimmedGym
            },
            sortBy: [SortDescriptor(\.grade, order: .forward)]
        )
        let entries = (try? context.fetch(descriptor)) ?? []
        let counts = entries.reduce(into: [String: Int]()) { result, entry in
            let grade = entry.grade.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !grade.isEmpty else { return }
            result[grade, default: 0] += 1
        }

        return counts
            .map { GradeCount(grade: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                lhs.grade.localizedStandardCompare(rhs.grade) == .orderedAscending
            }
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

    static func preview(in context: ModelContext, gym: String, mappings: [Mapping]) -> Summary {
        let activeMappings = sanitizedMappings(mappings)
        guard !activeMappings.isEmpty else {
            return Summary(count: 0, rows: [])
        }

        let counts = Dictionary(uniqueKeysWithValues: gradeCounts(in: context, gym: gym).map { ($0.grade, $0.count) })
        let rows = activeMappings.compactMap { mapping -> RowSummary? in
            let count = counts[mapping.oldGrade, default: 0]
            guard count > 0 else { return nil }
            return RowSummary(
                oldGrade: mapping.oldGrade,
                newGrade: mapping.newGrade,
                newFeelsLikeGrade: mapping.newFeelsLikeGrade,
                count: count
            )
        }

        return Summary(
            count: rows.reduce(0) { $0 + $1.count },
            rows: rows
        )
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
            return Summary(count: 0, rows: [])
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
        let rows = entries.isEmpty
            ? []
            : [
                RowSummary(
                    oldGrade: trimmedOldGrade,
                    newGrade: trimmedNewGrade,
                    newFeelsLikeGrade: trimmedFeelsLike?.isEmpty == false ? trimmedFeelsLike : nil,
                    count: entries.count
                )
            ]
        return Summary(count: entries.count, rows: rows)
    }

    @discardableResult
    static func migrateAll(
        in context: ModelContext,
        gym: String,
        mappings: [Mapping]
    ) throws -> Summary {
        let trimmedGym = gym.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeMappings = sanitizedMappings(mappings)
        guard !trimmedGym.isEmpty, !activeMappings.isEmpty else {
            return Summary(count: 0, rows: [])
        }

        let mappingByOldGrade = Dictionary(uniqueKeysWithValues: activeMappings.map { ($0.oldGrade, $0) })
        let descriptor = FetchDescriptor<ClimbEntry>(
            predicate: #Predicate { entry in
                entry.gym == trimmedGym
            }
        )
        let entries = try context.fetch(descriptor)

        var changedCounts: [String: Int] = [:]
        for entry in entries {
            let originalGrade = entry.grade.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let mapping = mappingByOldGrade[originalGrade] else { continue }

            entry.grade = mapping.newGrade
            if let newFeelsLikeGrade = mapping.newFeelsLikeGrade {
                entry.feelsLikeGrade = newFeelsLikeGrade
            }
            changedCounts[mapping.oldGrade, default: 0] += 1
        }

        try context.save()

        let rows = activeMappings.compactMap { mapping -> RowSummary? in
            let count = changedCounts[mapping.oldGrade, default: 0]
            guard count > 0 else { return nil }
            return RowSummary(
                oldGrade: mapping.oldGrade,
                newGrade: mapping.newGrade,
                newFeelsLikeGrade: mapping.newFeelsLikeGrade,
                count: count
            )
        }

        return Summary(
            count: rows.reduce(0) { $0 + $1.count },
            rows: rows
        )
    }

    private static func sanitizedMappings(_ mappings: [Mapping]) -> [Mapping] {
        var seenOldGrades = Set<String>()
        return mappings.compactMap { mapping in
            let oldGrade = mapping.oldGrade.trimmingCharacters(in: .whitespacesAndNewlines)
            let newGrade = mapping.newGrade.trimmingCharacters(in: .whitespacesAndNewlines)
            let newFeelsLikeGrade = mapping.newFeelsLikeGrade?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !oldGrade.isEmpty, !newGrade.isEmpty else { return nil }
            guard !seenOldGrades.contains(oldGrade) else { return nil }
            if oldGrade == newGrade && (newFeelsLikeGrade?.isEmpty ?? true) {
                return nil
            }
            seenOldGrades.insert(oldGrade)
            return Mapping(
                oldGrade: oldGrade,
                newGrade: newGrade,
                newFeelsLikeGrade: newFeelsLikeGrade?.isEmpty == false ? newFeelsLikeGrade : nil
            )
        }
    }
}
