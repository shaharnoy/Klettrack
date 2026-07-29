//
//  ExerciseTimerDefaultsTests.swift
//  klettrack Tests
//

import XCTest
import SwiftData
@testable import klettrack

final class ExerciseTimerDefaultsTests: ClimbingProgramTestSuite {

    // MARK: - Parsing
    //
    // The cases below are the actual strings seeded in SeedData.swift.

    func testParseSecondsHandlesSeededRestStrings() {
        XCTAssertEqual(ExerciseTimerDefaults.parseSeconds("3 min"), 180)
        XCTAssertEqual(ExerciseTimerDefaults.parseSeconds("3 mins"), 180)
        XCTAssertEqual(ExerciseTimerDefaults.parseSeconds("3-5 mins"), 180, "Ranges take the lower bound")
        XCTAssertEqual(ExerciseTimerDefaults.parseSeconds("2–3 min"), 120, "En dash must parse like a hyphen")
        XCTAssertEqual(ExerciseTimerDefaults.parseSeconds("3 min/asc"), 180)
        XCTAssertEqual(ExerciseTimerDefaults.parseSeconds("45 sec/asc"), 45)
        XCTAssertEqual(ExerciseTimerDefaults.parseSeconds("30 sec"), 30)
        XCTAssertEqual(ExerciseTimerDefaults.parseSeconds("30-60 sec"), 30)
        XCTAssertEqual(ExerciseTimerDefaults.parseSeconds("60 min"), 3600)
        XCTAssertEqual(ExerciseTimerDefaults.parseSeconds("4"), 240, "A bare number means minutes")
    }

    func testParseSecondsTreatsNoRestAsZeroAndVagueTextAsUnknown() {
        XCTAssertEqual(ExerciseTimerDefaults.parseSeconds("No rest"), 0)
        XCTAssertEqual(ExerciseTimerDefaults.parseSeconds("no rest between ascents"), 0)

        // These contain "min" but no number — they must not become a timer.
        XCTAssertNil(ExerciseTimerDefaults.parseSeconds("minimal"))
        XCTAssertNil(ExerciseTimerDefaults.parseSeconds("on the minute"))
        XCTAssertNil(ExerciseTimerDefaults.parseSeconds("brief"))
        XCTAssertNil(ExerciseTimerDefaults.parseSeconds(""))
        XCTAssertNil(ExerciseTimerDefaults.parseSeconds(nil))
    }

    func testParseCountTakesFirstInteger() {
        XCTAssertEqual(ExerciseTimerDefaults.parseCount("3"), 3)
        XCTAssertEqual(ExerciseTimerDefaults.parseCount("3–6"), 3)
        XCTAssertEqual(ExerciseTimerDefaults.parseCount("2-3"), 2)
        XCTAssertEqual(ExerciseTimerDefaults.parseCount("2 each hand"), 2)
        XCTAssertEqual(ExerciseTimerDefaults.parseCount("5 ascents"), 5)
        XCTAssertEqual(ExerciseTimerDefaults.parseCount("10–20"), 10)
        XCTAssertNil(ExerciseTimerDefaults.parseCount("as many as possible"))
        XCTAssertNil(ExerciseTimerDefaults.parseCount(nil))
    }

    func testParseCountCanTakeTheTopOfARange() {
        let top = { ExerciseTimerDefaults.parseCount($0, upperBound: true) }

        XCTAssertEqual(top("3-5"), 5)
        XCTAssertEqual(top("3–6"), 6, "En dash must parse like a hyphen")
        XCTAssertEqual(top("10–20"), 20)
        XCTAssertEqual(top("3 - 5"), 5, "Spaces around the dash are still a range")

        // No range: the single number is both bounds.
        XCTAssertEqual(top("3"), 3)
        XCTAssertEqual(top("2 each hand"), 2)
        XCTAssertEqual(top("5 ascents"), 5)
        XCTAssertNil(top("as many as possible"))
        XCTAssertNil(top(nil))
    }

    /// A second number only counts when a dash joins it to the first. Otherwise it is
    /// counting something else, and reading it as a set count would invent sets.
    func testParseCountUpperBoundIgnoresANonRangeSecondNumber() {
        XCTAssertEqual(ExerciseTimerDefaults.parseCount("3 sets of 5", upperBound: true), 3)
        XCTAssertEqual(ExerciseTimerDefaults.parseCount("2 each hand, 3 rounds", upperBound: true), 2)
    }

    /// The reported case: the catalog says 3–5 sets and the timer laid out three.
    func testASetRangePrescribesItsUpperBound() throws {
        let activity = createTestActivity(name: "Climbing-Specific Exercises")
        let type = createTestTrainingType(activity: activity, name: "Power")
        let exercise = Exercise(
            name: "Boulder Campusing", repsText: "5", setsText: "3-5", restText: "3 min"
        )
        type.exercises.append(exercise)
        try context.save()

        guard case .repBased(let reps, let sets, _, _, _) =
                try XCTUnwrap(ExerciseTimerDefaults.plan(for: exercise, in: context))
        else { return XCTFail("Expected a rep-based plan") }

        XCTAssertEqual(sets, 5, "The plan prescribes up to five sets; you can stop short")
        XCTAssertEqual(reps, 5, "Reps keep the lower bound — an inflated target over-reports")
    }

    // MARK: - Timer blurb

    func testBlurbPrefersDescriptionThenFallsBackToNotes() {
        let activity = createTestActivity(name: "Strength")
        let type = createTestTrainingType(activity: activity, name: "Power")

        let both = Exercise(name: "Both", exerciseDescription: "Keep tension", notes: "Ignore me")
        let notesOnly = Exercise(name: "Notes only", notes: "Use a 20mm edge")
        // The catalog editor writes "" for a cleared field, so blank must count as absent.
        let blankDescription = Exercise(name: "Blank", exerciseDescription: "   ", notes: "Real cue")
        let neither = Exercise(name: "Neither")
        [both, notesOnly, blankDescription, neither].forEach { type.exercises.append($0) }
        try? context.save()

        XCTAssertEqual(ExerciseTimerDefaults.blurb(for: both), "Keep tension")
        XCTAssertEqual(ExerciseTimerDefaults.blurb(for: notesOnly), "Use a 20mm edge")
        XCTAssertEqual(ExerciseTimerDefaults.blurb(for: blankDescription), "Real cue",
                       "A whitespace-only description must not win over real notes")
        XCTAssertNil(ExerciseTimerDefaults.blurb(for: neither))
    }

    // MARK: - Classification

    private func makeExercise(
        name: String = "Test Exercise",
        reps: String? = nil,
        sets: String? = nil,
        duration: String? = nil,
        rest: String? = nil,
        shape: ExerciseShape = .weighted
    ) -> Exercise {
        let activity = createTestActivity(name: "Strength")
        let type = createTestTrainingType(activity: activity, name: "Power")
        let exercise = Exercise(
            name: name,
            repsText: reps,
            durationText: duration,
            setsText: sets,
            restText: rest,
            shapeKey: shape.rawValue
        )
        type.exercises.append(exercise)
        try? context.save()
        return exercise
    }

    /// The motivating case: Weighted Pull-Ups as seeded.
    func testWeightedPullUpsClassifyAsRepBased() throws {
        let exercise = makeExercise(name: "Weighted Pull-Ups", reps: "5", sets: "3–6", rest: "3 min")

        let plan = try XCTUnwrap(ExerciseTimerDefaults.plan(for: exercise, in: context))
        guard case .repBased(let reps, let sets, _, let restBetweenSets, let templateId) = plan else {
            return XCTFail("Expected rep-based, got \(plan)")
        }
        XCTAssertEqual(reps, 5, "Rep ranges take the lower bound")
        XCTAssertEqual(sets, 6, "Set ranges prescribe the upper bound — you may stop short")
        XCTAssertEqual(restBetweenSets, 180)
        XCTAssertNil(templateId)
    }

    func testDurationTextMakesItDurationBased() throws {
        let exercise = makeExercise(name: "Repeaters", reps: "6", sets: "3", duration: "30 sec", rest: "1 min")

        let plan = try XCTUnwrap(ExerciseTimerDefaults.plan(for: exercise, in: context))
        guard case .durationBased(let config, _) = plan else {
            return XCTFail("Expected duration-based, got \(plan)")
        }
        let interval = try XCTUnwrap(config.intervals.first)
        XCTAssertEqual(interval.workTimeSeconds, 30)
        XCTAssertEqual(interval.restTimeSeconds, 60)
        XCTAssertEqual(interval.repetitions, 6)
    }

    func testNoGuidanceYieldsNoPlan() {
        let exercise = makeExercise(name: "Freeform")
        XCTAssertNil(ExerciseTimerDefaults.plan(for: exercise, in: context))
    }

    func testUnparseableRestYieldsNoPlan() {
        let exercise = makeExercise(name: "Vague", reps: "5", sets: "3", rest: "minimal")
        XCTAssertNil(ExerciseTimerDefaults.plan(for: exercise, in: context))
    }

    // MARK: - Attempts
    //
    // A limit boulder is seeded with both a duration and a rest. "30 min" is a session
    // budget; "3 min/asc" is the protocol. For attempts the rest has to win.

    /// The motivating case: "Work on 1–3 limit boulders" as seeded.
    func testAttemptsTakeRestOverDuration() throws {
        let exercise = makeExercise(
            name: "Work on 1–3 limit boulders",
            duration: "60 min",
            rest: "3 min/asc",
            shape: .attempts
        )

        let plan = try XCTUnwrap(ExerciseTimerDefaults.plan(for: exercise, in: context))
        guard case .repBased(let reps, let sets, let restBetweenReps, let restBetweenSets, _) = plan else {
            return XCTFail("Expected a try counter, got \(plan)")
        }
        XCTAssertNil(reps, "A try isn't a rep, and the app can't time one")
        XCTAssertEqual(sets, 1, "No set count given — attempts default to one set, like every other shape")
        XCTAssertEqual(restBetweenReps, 180, "With one set, the lone rest separates the tries")
        XCTAssertEqual(restBetweenSets, 0)
    }

    /// The same guidance on a loaded exercise must keep its old duration-based timer.
    func testTheFlipOnlyAppliesToAttempts() throws {
        let exercise = makeExercise(
            name: "Timed hang",
            duration: "60 min",
            rest: "3 min/asc",
            shape: .weighted
        )

        let plan = try XCTUnwrap(ExerciseTimerDefaults.plan(for: exercise, in: context))
        guard case .durationBased = plan else {
            return XCTFail("Expected duration-based, got \(plan)")
        }
    }

    /// The try count comes from the Sets field's upper bound, same as every other shape —
    /// not from Reps, which is what the conflation bug did.
    func testAttemptsReadTheTryCountFromSets() throws {
        let exercise = makeExercise(
            name: "Bouldering", reps: "3 ascents", sets: "3–10 problems",
            rest: "2 min/asc", shape: .attempts
        )

        let plan = try XCTUnwrap(ExerciseTimerDefaults.plan(for: exercise, in: context))
        guard case .repBased(let reps, let sets, _, let restBetweenSets, _) = plan else {
            return XCTFail("Expected a try counter, got \(plan)")
        }
        XCTAssertEqual(reps, 3)
        XCTAssertEqual(sets, 10, "The Sets field's upper bound, not the Reps field")
        XCTAssertEqual(restBetweenSets, 120)
    }

    /// "on the minute" doesn't parse, which used to leave Classic 4×4 with no work
    /// interval at all. As attempts it just doesn't matter.
    func testClassic4x4BecomesATryCounter() throws {
        let exercise = makeExercise(
            name: "Classic 4×4", reps: "4", sets: "4",
            duration: "on the minute", rest: "4 min", shape: .attempts
        )

        let plan = try XCTUnwrap(ExerciseTimerDefaults.plan(for: exercise, in: context))
        guard case .repBased(_, let sets, _, let restBetweenSets, _) = plan else {
            return XCTFail("Expected a try counter, got \(plan)")
        }
        XCTAssertEqual(sets, 4)
        XCTAssertEqual(restBetweenSets, 240)
    }

    /// A skill drill has no guidance at all — it must still yield no timer.
    func testAttemptsWithNoRestYieldNoPlan() {
        let exercise = makeExercise(name: "One Touch", shape: .attempts)
        XCTAssertNil(ExerciseTimerDefaults.plan(for: exercise, in: context))
    }

    // MARK: - Precedence

    func testAttachedTemplateBeatsGuidanceText() throws {
        let exercise = makeExercise(name: "Hangs", sets: "3", rest: "3 min")
        let template = TimerTemplate(name: "Attached", totalTimeSeconds: 42)
        context.insert(template)
        exercise.timerTemplateId = template.id
        try context.save()

        let plan = try XCTUnwrap(ExerciseTimerDefaults.plan(for: exercise, in: context))
        guard case .durationBased(let config, let templateId) = plan else {
            return XCTFail("Expected duration-based from the template, got \(plan)")
        }
        XCTAssertEqual(config.totalTimeSeconds, 42)
        XCTAssertEqual(templateId, template.id)
    }

    func testRepBasedTemplateYieldsRepBasedPlan() throws {
        let exercise = makeExercise(name: "Weighted Pull-Ups")
        let template = TimerTemplate(
            name: "Pull-Up Protocol",
            repeatCount: 4,
            restTimeBetweenIntervals: 150,
            repsPerSet: 6
        )
        context.insert(template)
        exercise.timerTemplateId = template.id
        try context.save()

        let plan = try XCTUnwrap(ExerciseTimerDefaults.plan(for: exercise, in: context))
        guard case .repBased(let reps, let sets, _, let restBetweenSets, let templateId) = plan else {
            return XCTFail("Expected rep-based, got \(plan)")
        }
        XCTAssertEqual(reps, 6)
        XCTAssertEqual(sets, 4)
        XCTAssertEqual(restBetweenSets, 150)
        XCTAssertEqual(templateId, template.id)
    }

    /// The link is a loose UUID, so a deleted template must read as "no attachment".
    func testDeletedTemplateFallsBackToGuidance() throws {
        let exercise = makeExercise(name: "Weighted Pull-Ups", reps: "5", sets: "3", rest: "3 min")
        let template = TimerTemplate(name: "Doomed", totalTimeSeconds: 42)
        context.insert(template)
        exercise.timerTemplateId = template.id
        try context.save()

        context.delete(template)
        try context.save()

        let plan = try XCTUnwrap(ExerciseTimerDefaults.plan(for: exercise, in: context))
        guard case .repBased(_, _, _, let restBetweenSets, _) = plan else {
            return XCTFail("Expected the derived rep-based plan, got \(plan)")
        }
        XCTAssertEqual(restBetweenSets, 180)
    }

    // MARK: - Two rests

    func testARepRestMakesThePlanNested() throws {
        let activity = createTestActivity(name: "Bouldering")
        let type = createTestTrainingType(activity: activity, name: "Limit")
        let exercise = Exercise(name: "Boulder Limit Session", repsText: "3", setsText: "5",
                                restText: "3 min", shapeKey: ExerciseShape.attempts.rawValue)
        exercise.restBetweenRepsText = "30 sec"
        type.exercises.append(exercise)
        try context.save()

        guard case .repBased(let reps, let sets, let restReps, let restSets, _) =
                try XCTUnwrap(ExerciseTimerDefaults.plan(for: exercise, in: context))
        else { return XCTFail("Expected a rep-based plan") }

        XCTAssertEqual(reps, 3, "Reps mean reps")
        XCTAssertEqual(sets, 5, "Sets mean sets — not read from the reps field")
        XCTAssertEqual(restReps, 30)
        XCTAssertEqual(restSets, 180)
    }

    /// The conflation this whole change is about: the attempts branch used to read the
    /// Reps field as the set count, so 5 sets x 3 reps ran three sets and lost the five.
    func testAttemptsNoLongerReadRepsAsTheSetCount() throws {
        let activity = createTestActivity(name: "Bouldering")
        let type = createTestTrainingType(activity: activity, name: "Limit")
        let exercise = Exercise(name: "Boulder Campusing", repsText: "3", setsText: "5",
                                restText: "3 min", shapeKey: ExerciseShape.attempts.rawValue)
        type.exercises.append(exercise)
        try context.save()

        guard case .repBased(let reps, let sets, _, _, _) =
                try XCTUnwrap(ExerciseTimerDefaults.plan(for: exercise, in: context))
        else { return XCTFail("Expected a rep-based plan") }

        XCTAssertEqual(sets, 5)
        XCTAssertEqual(reps, 3)
    }

    /// "3 ascents · 3 min/asc" is one bout of three goes, three minutes apart. With a
    /// single set there are no set boundaries, so a lone rest can only mean between reps.
    func testALoneCountBecomesRepsInOneSetAndTheRestGoesBetweenThem() throws {
        let activity = createTestActivity(name: "Bouldering")
        let type = createTestTrainingType(activity: activity, name: "Limit")
        let exercise = Exercise(name: "Limit Boulders", repsText: "3 ascents",
                                durationText: "30 min", restText: "3 min/asc",
                                shapeKey: ExerciseShape.attempts.rawValue)
        type.exercises.append(exercise)
        try context.save()

        guard case .repBased(let reps, let sets, let restReps, let restSets, _) =
                try XCTUnwrap(ExerciseTimerDefaults.plan(for: exercise, in: context))
        else { return XCTFail("Expected rest to beat the 30 min session budget") }

        XCTAssertEqual(reps, 3)
        XCTAssertEqual(sets, 1)
        XCTAssertEqual(restReps, 180, "The lone rest separates the goes")
        XCTAssertEqual(restSets, 0)
    }

    /// A rep-based template already carries both rests; it was discarding one of them.
    func testARepBasedTemplateKeepsItsIntervalRest() throws {
        let template = TimerTemplate(name: "Limit bouts", isRepeating: true,
                                     repeatCount: 5, restTimeBetweenIntervals: 180,
                                     repsPerSet: 3)
        template.intervals.append(
            TimerInterval(name: "Go", workTimeSeconds: 0, restTimeSeconds: 30,
                          repetitions: 3, order: 0)
        )
        context.insert(template)
        try context.save()

        guard case .repBased(let reps, let sets, let restReps, let restSets, let id) =
                ExerciseTimerDefaults.plan(from: template)
        else { return XCTFail("Expected a rep-based plan") }

        XCTAssertEqual(reps, 3)
        XCTAssertEqual(sets, 5)
        XCTAssertEqual(restReps, 30, "The interval rest is the rest between reps")
        XCTAssertEqual(restSets, 180)
        XCTAssertEqual(id, template.id)
    }

    // MARK: - Seed linking

    func testLinkTemplatesToExercisesIsIdempotentAndNeverOverwrites() throws {
        let activity = createTestActivity(name: "Fingers")
        let type = createTestTrainingType(activity: activity, name: "Max Strength")
        let pullUps = Exercise(name: "Pull-Up Intervals")
        let minEdge = Exercise(name: "FB \"Minimum Edge\" Hangs")
        type.exercises.append(pullUps)
        type.exercises.append(minEdge)

        let pullUpTemplate = TimerTemplate(name: "Pull-Up Interval")
        let minEdgeTemplate = TimerTemplate(name: "Minimum Edge FB")
        let userChoice = TimerTemplate(name: "My Own Timer")
        [pullUpTemplate, minEdgeTemplate, userChoice].forEach { context.insert($0) }

        // The user already picked something for one of them.
        minEdge.timerTemplateId = userChoice.id
        try context.save()

        let linked = SeedTimerTemplates.linkTemplatesToExercises(context)
        XCTAssertEqual(linked, 1, "Only the unlinked exercise should be touched")
        XCTAssertEqual(pullUps.timerTemplateId, pullUpTemplate.id)
        XCTAssertEqual(minEdge.timerTemplateId, userChoice.id, "A user's choice must survive")

        XCTAssertEqual(SeedTimerTemplates.linkTemplatesToExercises(context), 0, "Second run is a no-op")
    }
}
