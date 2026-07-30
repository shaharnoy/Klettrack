//
//  TimerSpec.swift
//  Klettrack
//
//  Compact, comma-free serialisation of a timer template so it can ride in a CSV column.
//

import Foundation

/// A decoded spec, ready to be turned into a TimerTemplate.
struct TimerTemplateDraft: Equatable {
    var totalTimeSeconds: Int?
    var intervals: [(name: String, work: Int, rest: Int, reps: Int)] = []
    var repeatCount: Int?
    var restBetweenSeconds: Int?
    var repsPerSet: Int?
    /// Rest between the reps inside a set, distinct from `restBetweenSeconds` (between sets).
    var restBetweenRepsSeconds: Int = 0

    static func == (lhs: TimerTemplateDraft, rhs: TimerTemplateDraft) -> Bool {
        lhs.totalTimeSeconds == rhs.totalTimeSeconds
            && lhs.repeatCount == rhs.repeatCount
            && lhs.restBetweenSeconds == rhs.restBetweenSeconds
            && lhs.repsPerSet == rhs.repsPerSet
            && lhs.restBetweenRepsSeconds == rhs.restBetweenRepsSeconds
            && lhs.intervals.count == rhs.intervals.count
            && zip(lhs.intervals, rhs.intervals).allSatisfy { $0 == $1 }
    }

    var isEmpty: Bool {
        totalTimeSeconds == nil && intervals.isEmpty && repsPerSet == nil
    }
}

/// Grammar (`;`-separated tokens, `|`-separated interval fields — same convention as `media_refs`):
///
///   reps=5;sets=3;rest=180;restReps=30            rep-based, waits for confirmation each set
///   total=180                                    plain countdown
///   interval=Hang|10|50|6;restBetween=180;repeat=3
///
/// No commas anywhere, so the value never needs CSV quoting.
enum TimerSpec {

    static func encode(_ template: TimerTemplate) -> String {
        var tokens: [String] = []

        if let reps = template.repsPerSet {
            tokens.append("reps=\(reps)")
            tokens.append("sets=\(max(1, template.repeatCount ?? 1))")
            tokens.append("rest=\(template.restTimeBetweenIntervals ?? 0)")
            let repRest = template.intervals.sorted { $0.order < $1.order }
                .first?.restTimeSeconds ?? 0
            if repRest > 0 { tokens.append("restReps=\(repRest)") }
            return tokens.joined(separator: ";")
        }

        if let total = template.totalTimeSeconds, template.intervals.isEmpty {
            tokens.append("total=\(total)")
        }

        for interval in template.intervals.sorted(by: { $0.order < $1.order }) {
            let name = sanitise(interval.name)
            tokens.append("interval=\(name)|\(interval.workTimeSeconds)|\(interval.restTimeSeconds)|\(interval.repetitions)")
        }

        if let rest = template.restTimeBetweenIntervals, rest > 0 {
            tokens.append("restBetween=\(rest)")
        }
        if template.isRepeating, let count = template.repeatCount, count > 1 {
            tokens.append("repeat=\(count)")
        }

        return tokens.joined(separator: ";")
    }

    static func decode(_ spec: String?) -> TimerTemplateDraft? {
        guard let spec, !spec.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        var draft = TimerTemplateDraft()

        for token in spec.split(separator: ";") {
            let parts = token.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "total":       draft.totalTimeSeconds = Int(value)
            case "reps":        draft.repsPerSet = Int(value)
            case "sets", "repeat": draft.repeatCount = Int(value)
            case "rest", "restbetween": draft.restBetweenSeconds = Int(value)
            case "restreps": draft.restBetweenRepsSeconds = Int(value) ?? 0
            case "interval":
                let fields = value.split(separator: "|", omittingEmptySubsequences: false)
                guard fields.count >= 4,
                      let work = Int(fields[1].trimmingCharacters(in: .whitespaces)),
                      let rest = Int(fields[2].trimmingCharacters(in: .whitespaces)),
                      let reps = Int(fields[3].trimmingCharacters(in: .whitespaces))
                else { continue }
                let name = fields[0].trimmingCharacters(in: .whitespaces)
                draft.intervals.append((name.isEmpty ? "Interval" : name, work, rest, max(1, reps)))
            default:
                continue
            }
        }

        return draft.isEmpty ? nil : draft
    }

    /// Build a template from a decoded spec. Caller inserts it into the context.
    static func makeTemplate(named name: String, from draft: TimerTemplateDraft) -> TimerTemplate {
        let template = TimerTemplate(
            name: name,
            templateDescription: "Imported from CSV",
            totalTimeSeconds: draft.totalTimeSeconds,
            isRepeating: (draft.repeatCount ?? 1) > 1 && draft.repsPerSet == nil,
            repeatCount: draft.repeatCount,
            restTimeBetweenIntervals: draft.restBetweenSeconds,
            repsPerSet: draft.repsPerSet
        )
        for (index, interval) in draft.intervals.enumerated() {
            template.intervals.append(
                TimerInterval(
                    name: interval.name,
                    workTimeSeconds: interval.work,
                    restTimeSeconds: interval.rest,
                    repetitions: interval.reps,
                    order: index
                )
            )
        }
        // A rep-based template keeps its rest between reps on an interval, which is
        // where plan(from:) looks for it.
        if draft.repsPerSet != nil, draft.restBetweenRepsSeconds > 0, draft.intervals.isEmpty {
            template.intervals.append(
                TimerInterval(name: "Rep", workTimeSeconds: 0,
                              restTimeSeconds: draft.restBetweenRepsSeconds,
                              repetitions: max(1, draft.repsPerSet ?? 1), order: 0)
            )
        }
        return template
    }

    /// Strip the delimiters so a template name can never corrupt the spec.
    private static func sanitise(_ name: String) -> String {
        name
            .replacingOccurrences(of: ";", with: " ")
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
