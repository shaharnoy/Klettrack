//
//  LoggedSetsRow.swift
//  Klettrack
//
//  Read-only per-set breakdown of a logged exercise.
//

import SwiftUI

/// One line per set: what was lifted, how it felt, and any note.
///
/// Shown wherever a logged exercise is listed, so per-set detail captured by the
/// timer is actually readable afterwards rather than write-only.
struct LoggedSetsRow: View {
    let sets: [LoggedSet]

    var body: some View {
        if !sets.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(sets.enumerated(), id: \.element.id) { index, set in
                    LoggedSetLine(number: index + 1, set: set)
                }
            }
        }
    }
}

struct LoggedSetLine: View {
    let number: Int
    let set: LoggedSet

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Set \(number)")
                .foregroundStyle(.tertiary)

            if let reps = set.reps {
                Text("\(reps, format: .number.precision(.fractionLength(0...1))) reps")
            }

            if let weight = set.weightKg, weight > 0 {
                Text("\(weight, format: .number.precision(.fractionLength(0...1))) kg")
            }

            if let effort = set.effortLabel {
                Text(effort)
                    .foregroundStyle(.secondary)
            }

            if let note = set.note, !note.isEmpty {
                Text(note)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.caption.monospacedDigit())
    }
}
