//
//  ExerciseTimerDefaults.swift
//  Klettrack
//
//  Works out what kind of timer an exercise wants.
//

import Foundation
import SwiftData

/// How an exercise's timer behaves.
///
/// Duration-based exercises time the work itself and advance automatically.
/// Rep-based exercises have no work duration to count — you do N reps, confirm,
/// and the rest runs.
enum ExerciseTimerPlan: Equatable {
    case durationBased(TimerConfiguration, templateId: UUID?)
    case repBased(reps: Int?, sets: Int, restSeconds: Int, templateId: UUID?)

    var templateId: UUID? {
        switch self {
        case .durationBased(_, let id), .repBased(_, _, _, let id): return id
        }
    }
}

enum ExerciseTimerDefaults {

    // MARK: - Text parsing
    //
    // Guidance text is hand-written and only semi-structured — the seeded values
    // include "3 min", "3-5 mins", "2–3 min", "45 sec/asc", "no rest between
    // ascents", "minimal" and "on the minute". Parse the common shapes and return
    // nil for the rest rather than guessing.

    /// Seconds from a duration/rest string. nil when there is no number to read.
    static func parseSeconds(_ text: String?) -> Int? {
        guard let normalised = normalise(text) else { return nil }

        // "No rest", "no rest between ascents", "none"
        if normalised.contains("no rest") || normalised == "none" { return 0 }

        guard let value = firstNumber(in: normalised) else { return nil }

        // "45 sec/asc" → seconds. "3 min", "2-3 min" → minutes. Bare "3" → minutes.
        if normalised.contains("sec") { return Int(value.rounded()) }
        return Int((value * 60).rounded())
    }

    /// A count (sets, reps) from a string. Takes the first integer, so ranges like
    /// "3–6" yield the lower bound — pass `upperBound: true` for the top of the range.
    ///
    /// Which end you want depends on what the number is for. A *set* count is a
    /// prescription the timer lays out in advance, and you can always stop short of it,
    /// so "3–5 sets" should offer five. A *rep* count is a target inside one set, and
    /// an inflated one silently over-reports what you did.
    static func parseCount(_ text: String?, upperBound: Bool = false) -> Int? {
        guard let normalised = normalise(text) else { return nil }
        guard let value = upperBound
                ? lastNumberOfRange(in: normalised)
                : firstNumber(in: normalised)
        else { return nil }
        let count = Int(value.rounded())
        return count > 0 ? count : nil
    }

    private static func normalise(_ text: String?) -> String? {
        guard let text else { return nil }
        let normalised = text
            .replacingOccurrences(of: "–", with: "-")   // en dash
            .replacingOccurrences(of: "—", with: "-")   // em dash
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalised.isEmpty ? nil : normalised
    }

    /// The top of an `n-m` range, or the single number when there is no range.
    ///
    /// Deliberately strict about what a range is: a second number counts only if a dash
    /// joins it to the first. "3-5 mins" is 5 and "3 - 5" is 5, but "3 sets of 5" is 3 —
    /// a trailing number that isn't a range end is almost always counting something else.
    private static func lastNumberOfRange(in text: String) -> Double? {
        let characters = Array(text)

        /// The number starting at `start`, and the index just past it.
        func number(at start: Int) -> (value: Double, end: Int)? {
            var digits = ""
            var index = start
            while index < characters.count,
                  characters[index].isNumber || (characters[index] == "." && !digits.isEmpty) {
                digits.append(characters[index])
                index += 1
            }
            guard let value = Double(digits) else { return nil }
            return (value, index)
        }

        func skippingSpaces(from start: Int) -> Int {
            var index = start
            while index < characters.count, characters[index] == " " { index += 1 }
            return index
        }

        var start = 0
        while start < characters.count, !characters[start].isNumber { start += 1 }
        guard let first = number(at: start) else { return nil }

        let afterDash = skippingSpaces(from: first.end)
        guard afterDash < characters.count, characters[afterDash] == "-" else { return first.value }
        return number(at: skippingSpaces(from: afterDash + 1))?.value ?? first.value
    }

    /// First number in the string, e.g. "3-5 mins" → 3, "2 each hand" → 2.
    private static func firstNumber(in text: String) -> Double? {
        var digits = ""
        for character in text {
            if character.isNumber || (character == "." && !digits.isEmpty) {
                digits.append(character)
            } else if !digits.isEmpty {
                break
            }
        }
        return digits.isEmpty ? nil : Double(digits)
    }

    // MARK: - Description

    /// The cue to show while the timer runs: the exercise's description, falling back to its
    /// notes. Mirrors the description-else-notes convention used for catalog search subtitles.
    /// Blank strings count as absent — the catalog editor stores "" for a cleared field.
    static func blurb(for exercise: Exercise) -> String? {
        for candidate in [exercise.exerciseDescription, exercise.notes] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    // MARK: - Classification

    /// Resolve the timer for an exercise. First match wins:
    /// an attached template, then a work duration, then a rest between sets.
    static func plan(for exercise: Exercise, in context: ModelContext) -> ExerciseTimerPlan? {
        if let template = attachedTemplate(for: exercise, in: context) {
            return plan(from: template)
        }

        let rest = parseSeconds(exercise.restText)

        // Attempts: rest between tries beats the duration, which is a session budget
        // rather than a work interval. A limit boulder is seeded with both — "30 min"
        // and "3 min/asc" — and counting down 30 blind minutes tells you nothing,
        // where a try counter with a rest between attempts is the actual protocol.
        if exercise.shape == .attempts, let rest, rest > 0 {
            return .repBased(
                // A try isn't a rep, and the app can't time one.
                reps: nil,
                // "3 ascents" / "3–6 boulders" is the try count; the books' default
                // for a limit session is 10 tries across two or three problems. Both
                // texts count tries here, so both take the top of their range.
                sets: parseCount(exercise.repsText, upperBound: true)
                    ?? parseCount(exercise.setsText, upperBound: true)
                    ?? 10,
                restSeconds: rest,
                templateId: nil
            )
        }

        // Duration-based: the work itself is timed.
        if let work = parseSeconds(exercise.durationText), work > 0 {
            let repetitions = parseCount(exercise.repsText)
                ?? parseCount(exercise.setsText, upperBound: true)
                ?? 1
            let interval = IntervalConfiguration(
                name: exercise.name,
                workTimeSeconds: work,
                restTimeSeconds: rest ?? 0,
                repetitions: max(1, repetitions)
            )
            return .durationBased(TimerConfiguration(intervals: [interval]), templateId: nil)
        }

        // Rep-based: nothing to time except the rest between sets.
        if let rest, rest > 0 {
            return .repBased(
                reps: parseCount(exercise.repsText),
                sets: max(1, parseCount(exercise.setsText, upperBound: true) ?? 1),
                restSeconds: rest,
                templateId: nil
            )
        }

        return nil
    }

    /// A template's own plan, independent of any exercise.
    static func plan(from template: TimerTemplate) -> ExerciseTimerPlan {
        if let reps = template.repsPerSet {
            return .repBased(
                reps: reps,
                sets: max(1, template.repeatCount ?? 1),
                restSeconds: template.restTimeBetweenIntervals ?? 0,
                templateId: template.id
            )
        }
        return .durationBased(template.makeConfiguration(), templateId: template.id)
    }

    /// The attached template, or nil when there is none or it has since been deleted.
    static func attachedTemplate(for exercise: Exercise, in context: ModelContext) -> TimerTemplate? {
        guard let id = exercise.timerTemplateId else { return nil }
        let descriptor = FetchDescriptor<TimerTemplate>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }
}
