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

    // MARK: - Classification

    private func makeExercise(
        name: String = "Test Exercise",
        reps: String? = nil,
        sets: String? = nil,
        duration: String? = nil,
        rest: String? = nil
    ) -> Exercise {
        let activity = createTestActivity(name: "Strength")
        let type = createTestTrainingType(activity: activity, name: "Power")
        let exercise = Exercise(
            name: name,
            repsText: reps,
            durationText: duration,
            setsText: sets,
            restText: rest
        )
        type.exercises.append(exercise)
        try? context.save()
        return exercise
    }

    /// The motivating case: Weighted Pull-Ups as seeded.
    func testWeightedPullUpsClassifyAsRepBased() throws {
        let exercise = makeExercise(name: "Weighted Pull-Ups", reps: "5", sets: "3–6", rest: "3 min")

        let plan = try XCTUnwrap(ExerciseTimerDefaults.plan(for: exercise, in: context))
        guard case .repBased(let reps, let sets, let restSeconds, let templateId) = plan else {
            return XCTFail("Expected rep-based, got \(plan)")
        }
        XCTAssertEqual(reps, 5)
        XCTAssertEqual(sets, 3, "Set ranges take the lower bound")
        XCTAssertEqual(restSeconds, 180)
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
        guard case .repBased(let reps, let sets, let restSeconds, let templateId) = plan else {
            return XCTFail("Expected rep-based, got \(plan)")
        }
        XCTAssertEqual(reps, 6)
        XCTAssertEqual(sets, 4)
        XCTAssertEqual(restSeconds, 150)
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
        guard case .repBased(_, _, let restSeconds, _) = plan else {
            return XCTFail("Expected the derived rep-based plan, got \(plan)")
        }
        XCTAssertEqual(restSeconds, 180)
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
