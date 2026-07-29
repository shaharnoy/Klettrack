//
//  UserDecimal.swift
//  Klettrack
//
//  Reading and writing the numbers a user types into a decimal field.
//

import Foundation

/// Parse a number the user typed.
///
/// A `.decimalPad` emits the locale's decimal separator, which is a comma across most
/// of Europe — and `Double("32,5")` is nil. Returns nil for anything unparseable so a
/// half-typed field can leave the model alone.
///
/// ponytail: `ExerciseLogSheet.number`, `AddSessionItemSheet`, `EditSessionItemView`
/// and `LogCSV` each inline this same replacement. Route them through here if one of
/// them ever needs touching; they work today, so this doesn't rewrite them.
func userDecimal(_ text: String) -> Double? {
    Double(
        text.replacing(",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    )
}

/// Render a number back into a field the user will read and edit: localised
/// separator, no trailing ".0", and no grouping separator (which would be ambiguous
/// with the decimal one).
func decimalText(_ value: Double?) -> String {
    guard let value else { return "" }
    return value.rounded() == value
        ? String(Int(value))
        : value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
}
