//
//  BoardSyncShared.swift
//  Klettrack
//

import CryptoKit
import Foundation

enum BoardGradeMapper {
    struct Mapping {
        let fontGrade: String
        let vGrade: String
    }

    static let mappingCSV = """
    difficulty,grade_label
    1,1a/V0
    2,1b/V0
    3,1c/V0
    4,2a/V0
    5,2b/V0
    6,2c/V0
    7,3a/V0
    8,3b/V0
    9,3c/V0
    10,4a/V0
    11,4b/V0
    12,4c/V0
    13,5a/V1
    14,5b/V1
    15,5c/V2
    16,6a/V3
    17,6a+/V3
    18,6b/V4
    19,6b+/V4
    20,6c/V5
    21,6c+/V5
    22,7a/V6
    23,7a+/V7
    24,7b/V8
    25,7b+/V8
    26,7c/V9
    27,7c+/V10
    28,8a/V11
    29,8a+/V12
    30,8b/V13
    31,8b+/V14
    32,8c/V15
    33,8c+/V16
    34,9a/V17
    35,9a+/V18
    36,9b/V19
    37,9b+/V20
    38,9c/V21
    39,9c+/V22
    """

    static let diffToMapping: [Int: Mapping] = {
        var out: [Int: Mapping] = [:]
        for line in mappingCSV.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty || t.hasPrefix("#") || t.lowercased().hasPrefix("difficulty") { continue }
            let parts = t.split(separator: ",", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2, let n = Int(parts[0]) else { continue }
            let fontGrade = leftPart(of: parts[1])
            let vGrade = rightPart(of: parts[1])
            guard !fontGrade.isEmpty, !vGrade.isEmpty else { continue }
            out[n] = Mapping(fontGrade: fontGrade, vGrade: vGrade)
        }
        return out
    }()

    static let diffToGrade: [Int: String] = diffToMapping.mapValues(\.fontGrade)
    static let diffToVGrade: [Int: String] = diffToMapping.mapValues(\.vGrade)
    static let fontGradeToVGrade: [String: String] = {
        Dictionary(uniqueKeysWithValues: diffToMapping.values.map { (normalizedGrade($0.fontGrade), $0.vGrade) })
    }()

    static func leftPart(of label: String) -> String {
        let first = label.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first ?? Substring("")
        let leftDot = first.split(separator: "·", maxSplits: 1, omittingEmptySubsequences: false).first ?? Substring("")
        return String(leftDot).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func rightPart(of label: String) -> String {
        let parts = label.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count > 1 else { return "" }
        let rightDot = parts[1].split(separator: "·", maxSplits: 1, omittingEmptySubsequences: false).first ?? Substring("")
        return String(rightDot).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func grade(of number: Any?) -> String? {
        difficultyKey(from: number).flatMap { diffToGrade[$0] }
    }

    static func vGrade(of number: Any?) -> String? {
        difficultyKey(from: number).flatMap { diffToVGrade[$0] }
    }

    static func vGrade(fromFontGrade grade: String) -> String? {
        fontGradeToVGrade[normalizedGrade(grade)]
    }

    private static func difficultyKey(from number: Any?) -> Int? {
        guard let n = number else { return nil }
        let value: Double?
        if let i = n as? Int {
            value = Double(i)
        } else if let d = n as? Double {
            value = d
        } else if let s = n as? String {
            value = Double(s)
        } else {
            value = nil
        }
        guard let v = value else { return nil }
        return Int(v.rounded())
    }

    private static func normalizedGrade(_ grade: String) -> String {
        grade.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum BoardDateParser {
    static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func makeFormatter(_ fmt: String, tzUTC: Bool = true) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tzUTC ? TimeZone(secondsFromGMT: 0) : TimeZone.current
        f.dateFormat = fmt
        return f
    }

    static let f1 = makeFormatter("yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX")
    static let f2 = makeFormatter("yyyy-MM-dd HH:mm:ss.SSSSSSxxxx")
    static let f3 = makeFormatter("yyyy-MM-dd HH:mm:ss.SSSSSS")
    static let f4 = makeFormatter("yyyy-MM-dd HH:mm:ssXXXXX")
    static let f5 = makeFormatter("yyyy-MM-dd HH:mm:ssxxxx")
    static let f6 = makeFormatter("yyyy-MM-dd HH:mm:ss")
    static let f7 = makeFormatter("yyyy-MM-dd")
    static let f8 = makeFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX")
    static let f9 = makeFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX")
    static let f10 = makeFormatter("yyyy-MM-dd'T'HH:mm:ssXXXXX")

    /// Tension Board returns some `climbed_at` values without an offset. Those values
    /// represent the time the climber recorded locally, rather than a UTC timestamp.
    /// Parse only those offset-less values in the device timezone; timestamps that
    /// include an offset retain their original absolute instant.
    static func parseTensionClimbedAt(_ value: String?, timeZone: TimeZone = .current) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        guard !hasExplicitTimeZone(value) else {
            return parse(value)
        }

        for format in [
            "yyyy-MM-dd HH:mm:ss.SSSSSS",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss"
        ] {
            let formatter = makeFormatter(format, timeZone: timeZone)
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    static func parse(_ s: String?) -> Date? {
        guard var s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }

        if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: s)),
           let v = Double(s) {
            if s.count >= 13 { return Date(timeIntervalSince1970: v / 1000.0) }
            if s.count >= 10 { return Date(timeIntervalSince1970: v) }
        }

        if let d = isoFull.date(from: s) { return d }
        if let d = isoBasic.date(from: s) { return d }

        for f in [f1, f2, f3, f4, f5, f6, f7, f8, f9, f10] {
            if let d = f.date(from: s) { return d }
        }

        if s.hasSuffix(" UTC") {
            s.removeLast(4)
            for f in [f3, f6, f7] {
                if let d = f.date(from: s) { return d }
            }
        }
        return nil
    }

    private static func makeFormatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }

    private static func hasExplicitTimeZone(_ value: String) -> Bool {
        value.hasSuffix("Z") ||
        value.hasSuffix(" UTC") ||
        value.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil
    }
}

enum BoardSyncIdentity {
    static func deterministicUUID(from string: String) -> UUID {
        let hash = SHA256.hash(data: Data(string.utf8))
        let bytes = Array(hash.prefix(16))
        let uuid = uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }
}
