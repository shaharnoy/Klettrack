import Foundation

enum ClimbAttemptsOption: Hashable, Identifiable {
    case flash
    case count(Int)
    case none
    case legacy(String)

    static let standardOptions: [ClimbAttemptsOption] =
        [.flash] + (2...15).map(ClimbAttemptsOption.count) + [.none]

    var id: String {
        switch self {
        case .flash:
            "flash"
        case .count(let value):
            "count-\(value)"
        case .none:
            "none"
        case .legacy(let value):
            "legacy-\(value)"
        }
    }

    var displayName: String {
        switch self {
        case .flash:
            "Flash"
        case .count(let value):
            String(value)
        case .none:
            "None"
        case .legacy(let value):
            value
        }
    }

    var storedValue: String {
        displayName
    }

    var statisticsCount: Int {
        switch self {
        case .flash:
            return 1
        case .count(let value):
            return value
        case .none:
            return 0
        case .legacy(let value):
            let digits = value.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            return Int(digits) ?? 1
        }
    }

    static func fromStoredValue(_ value: String?) -> ClimbAttemptsOption {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmed.isEmpty || trimmed == "1" || trimmed.localizedCaseInsensitiveCompare("Flash") == .orderedSame {
            return .flash
        }

        if trimmed == "0" || trimmed.localizedCaseInsensitiveCompare("None") == .orderedSame {
            return .none
        }

        if let count = Int(trimmed), 2...15 ~= count {
            return .count(count)
        }

        return .legacy(trimmed)
    }

    static func statisticsCount(forStoredValue value: String?) -> Int {
        fromStoredValue(value).statisticsCount
    }
}
