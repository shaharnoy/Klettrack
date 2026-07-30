//
//  LoggedSet.swift
//  Klettrack
//
//  One performed set of an exercise: what was actually lifted, how hard it felt.
//

import Foundation

/// One performed set, captured by the timer.
///
/// Stored as a `Codable` array attribute on `SessionItem` rather than as a child
/// `@Model`: nothing queries sets individually, so an array needs no container
/// registration, no cascade rule, and no ordering column. The trade-off is that
/// `loggedSets` cannot appear in a `#Predicate`.
struct LoggedSet: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var reps: Double?
    var weightKg: Double?
    /// Perceived effort, 1...5. See `LoggedSet.effortLabels`.
    var rpe: Int?
    var note: String?
    /// Which set this effort belonged to, 1-based.
    ///
    /// Stored rather than derived because the log outlives the sequence that produced
    /// it: `SessionItem` has no rep count to reconstruct the grouping from, so without
    /// this a fifteen-effort boulder session reads back as a flat run of fifteen.
    /// `nil` on anything logged before this existed, and on hand-entered items.
    var setNumber: Int?

    /// `id` is identity for `ForEach` only. Leaving it out of the coding keys keeps
    /// exported cells small and stops a stale UUID surviving a CSV round-trip;
    /// the default value covers the decode.
    private enum CodingKeys: String, CodingKey { case reps, weightKg, rpe, note, setNumber }

    static let effortLabels = ["Easy", "Moderate", "Hard", "Very Hard", "Max"]

    /// Label for an effort rating, or nil when unrated or out of range.
    static func effortLabel(for rpe: Int?) -> String? {
        guard let rpe, effortLabels.indices.contains(rpe - 1) else { return nil }
        return effortLabels[rpe - 1]
    }

    var effortLabel: String? { Self.effortLabel(for: rpe) }
}

extension Array where Element == LoggedSet {
    /// Compact JSON for the CSV `sets_detail` column. Empty string for no detail, so
    /// the cell stays blank rather than reading "[]".
    ///
    /// JSON rather than a token format like `TimerSpec`: `LoggedSet` is already
    /// `Codable`, so there is no parser to write or get wrong, and a note containing
    /// any character survives intact.
    var csvEncoded: String {
        guard !isEmpty else { return "" }
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Decode the `sets_detail` column. A blank or malformed cell yields no detail
    /// rather than failing the row — the rollup columns still carry the numbers.
    static func csvDecoded(_ text: String?) -> [LoggedSet] {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = text.data(using: .utf8),
              let sets = try? JSONDecoder().decode([LoggedSet].self, from: data)
        else { return [] }
        return sets
    }

    /// The flat aggregate that `SessionItem.reps` / `.sets` / `.weightKg` keep
    /// exposing, so analytics, charts and CSV export stay untouched.
    ///
    /// ponytail: mean rollup — identical to the old single-value behaviour when the
    /// sets are uniform, which is the common case. Read `loggedSets` directly if
    /// per-set charts are ever wanted.
    var rollup: (reps: Double?, sets: Double?, weightKg: Double?) {
        guard !isEmpty else { return (nil, nil, nil) }
        // A nested session stamps the same set number on every rep in that set, so the
        // distinct count is the true set count; a flat or pre-nesting log carries no set
        // numbers at all, and falls back to one set per effort as before.
        let distinctSetNumbers = Set(compactMap(\.setNumber))
        let sets = distinctSetNumbers.isEmpty ? count : distinctSetNumbers.count
        return (mean(\.reps), Double(sets), mean(\.weightKg))
    }

    private func mean(_ value: (Element) -> Double?) -> Double? {
        let values = compactMap(value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// The log split into bouts for display. One group with a `nil` number when the
    /// entries carry no set — hand-logged items, and anything written before nesting.
    var groupedBySet: [(setNumber: Int?, efforts: [LoggedSet])] {
        // Only worth grouping when a set holds more than one effort. A flat session
        // stamps a distinct set number on every entry, and grouping those would caption
        // each of six pull-up sets as a set containing one rep — noise where the old
        // flat list was exactly right.
        let numbered = Set(compactMap(\.setNumber))
        guard !numbered.isEmpty, numbered.count < count else {
            return isEmpty ? [] : [(nil, self)]
        }
        return Dictionary(grouping: self) { $0.setNumber }
            .sorted { ($0.key ?? .max) < ($1.key ?? .max) }
            .map { (setNumber: $0.key, efforts: $0.value) }
    }
}
