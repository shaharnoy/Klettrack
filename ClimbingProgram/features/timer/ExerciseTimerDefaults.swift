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

    /// A count (sets, reps) from a string. Takes the first integer, so ranges
    /// like "3–6" yield the lower bound.
    static func parseCount(_ text: String?) -> Int? {
        guard let normalised = normalise(text), let value = firstNumber(in: normalised) else { return nil }
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

        // Duration-based: the work itself is timed.
        if let work = parseSeconds(exercise.durationText), work > 0 {
            let repetitions = parseCount(exercise.repsText) ?? parseCount(exercise.setsText) ?? 1
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
                sets: max(1, parseCount(exercise.setsText) ?? 1),
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
