//
//  ImportExportTests.swift
//  klettrack Tests
//  Created by Shahar Noy on 30.09.25.
//

import XCTest
import SwiftData
import CryptoKit
import UIKit

@testable import klettrack

private func testDeterministicUUID(from string: String) -> UUID {
    #if canImport(CryptoKit)
    let hash = SHA256.hash(data: Data(string.utf8))
    let bytes = Array(hash.prefix(16))
    #else
    var hasher = Hasher()
    hasher.combine(string)
    let seed = UInt64(bitPattern: Int64(hasher.finalize()))
    var rng = SeededRNG(seed: seed)
    var bytes: [UInt8] = (0..<16).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
    #endif
    let uuid = uuid_t(bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],
                      bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15])
    return UUID(uuid: uuid)
}

// MARK: - Helper for stableID duplication (matches production)
private func testStableID(climbUUID: String, day: Date, angle: Int?, isWIP: Bool) -> UUID {
    let dayEpoch = Int((day.timeIntervalSince1970 / 86400.0).rounded(.down))
    let key = "tb2|\(climbUUID)|\(dayEpoch)|\(angle ?? -999)|0|\(isWIP ? 0 : 1)"
    return testDeterministicUUID(from: key)
}

private func ensurePlanKind(_ ctx: ModelContext, key: String = "weekly", name: String = "Weekly") throws -> PlanKindModel {
    if let existing = try ctx.fetch(FetchDescriptor<PlanKindModel>(predicate: #Predicate { $0.key == key })).first {
        return existing
    }
    let kind = PlanKindModel(key: key, name: name)
    ctx.insert(kind)
    try ctx.save()
    return kind
}


class ImportExportTests: ClimbingProgramTestSuite {
    
    // MARK: - CSV Export Tests
    
    func testCSVExportStructure() {
        // Create test data
        let plan = createTestPlan(name: "Plan", kindKey: "weekly", start: Date())
        let session = createTestSession()
        
        let item = SessionItem(
            exerciseName: "Pull-ups",
            planSourceId: plan.id,
            planName: plan.name,
            reps: 10,
            sets: 3,
            weightKg: 5.0,
            grade: "V4",
            notes: "Great session"
        )
        session.items.append(item)
        try? context.save()
        
        // Generate CSV export
        let exportDoc = LogCSV.makeExportCSV(context: context)
        let csvContent = exportDoc.csv
        
        // Verify CSV structure
        let lines = csvContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
        XCTAssertGreaterThan(lines.count, 1, "CSV should have header + data rows")
        
        // Verify header
        let header = lines.first!
        let expectedFields = [
            "date","type","exercise_name","climb_type","grade","feelsLikeGrade","angle","holdColor","rope_type","style","attempts","wip","ispreviouslyClimbed","gym","reps","sets","duration","weight_kg","plan_id","plan_name","day_type","notes","climb_id","tb2_uuid","media_refs","rest","timer_name","timer_spec","sets_detail","activity","training_type","shape"
        ]
        let headerFields = header.components(separatedBy: ",")
        XCTAssertEqual(headerFields.count, expectedFields.count, "Header should have correct number of fields")
        XCTAssertEqual(headerFields, expectedFields, "Header fields should match expected order")
        
        // Verify data row
        if lines.count > 1 {
            let dataRow = lines[1]
            let components = dataRow.components(separatedBy: ",")
            XCTAssertEqual(components.count, expectedFields.count, "Data row should have correct number of fields")
            XCTAssertTrue(dataRow.contains("Pull-ups"))
            XCTAssertTrue(dataRow.contains(plan.id.uuidString))
        }
    }
    
    func testCSVExportDateFormatting() {
        let specificDate = DateComponents(calendar: Calendar.current, year: 2025, month: 8, day: 23).date!
        let session = Session(date: specificDate)
        context.insert(session)
        
        let item = SessionItem(exerciseName: "Test Exercise")
        session.items.append(item)
        try? context.save()
        
        let exportDoc = LogCSV.makeExportCSV(context: context)
        let csvContent = exportDoc.csv
        
        // Verify date formatting (ISO8601)
        XCTAssertTrue(csvContent.contains("2025-08-23"), "Date should be in ISO8601 format")
    }
    
    func testCSVExportEmptyData() {
        // Test export with no session data
        let exportDoc = LogCSV.makeExportCSV(context: context)
        let csvContent = exportDoc.csv
        
        let lines = csvContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 1, "Empty export should only contain header")
    }

    func testCSVExportNumericFormattingIsStable() {
        let session = Session(date: Date())
        context.insert(session)

        let item = SessionItem(
            exerciseName: "Numeric Formatting",
            reps: 1.23456,
            sets: 2.5,
            weightKg: 4,
            duration: 3.3333
        )
        session.items.append(item)
        try? context.save()

        let csvContent = LogCSV.makeExportCSV(context: context).csv
        let lines = csvContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
        XCTAssertGreaterThanOrEqual(lines.count, 2)

        let dataRow = lines[1]
        XCTAssertTrue(
            dataRow.contains(",1.235,2.500,3.333,4.000,"),
            "Exported numeric values should use deterministic 3-decimal POSIX formatting"
        )
    }
    
    // MARK: - CSV Import Tests
    
    // Centralized header to avoid duplication & indentation issues
    private let testCSVHeader =
    "date,type,exercise_name,climb_type,grade,feelsLikeGrade,angle,holdColor,rope_type,style,attempts,wip,ispreviouslyClimbed,gym,reps,sets,duration,weight_kg,plan_id,plan_name,day_type,notes,climb_id,tb2_uuid,media_refs"
    
    func testCSVImportBasic() async throws {
        let csvContent = """
        \(testCSVHeader)
        2025-08-23 11:22:11,exercise,Push-ups,,,,,,,,,,,,15,3,0.000,,,,,Felt good,,,
        2025-08-23 11:23:11,exercise,Pull-ups,,,,,,,,,,,,10,3,5.000,,,,,Challenging,,,
        """
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_import.csv")
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let importedCount = try await LogCSV.importCSVAsync(from: tempURL, into: context, tag: "test", dedupe: false)
        XCTAssertEqual(importedCount, 2)
    }

    
    func testCSVImportWithPlanData() async throws {
        let kindFetch = FetchDescriptor<PlanKindModel>(predicate: #Predicate { $0.key == "weekly" })
        let planKind = (try? context.fetch(kindFetch))?.first ?? PlanKindModel(key: "weekly", name: "Weekly", totalWeeks: nil, isRepeating: true, order: 1)
        if (try? context.fetch(kindFetch))?.first == nil { context.insert(planKind) }
        let plan = Plan(name: "Test Plan", kind: planKind, startDate: Date())
        context.insert(plan)
        try? context.save()
        let csvContent = """
    \(testCSVHeader)
    2025-08-23 11:30:00,exercise,Squats,,,,,,,,,,,,20,4,0.000,,\(plan.id.uuidString),\(plan.name),,Leg day,,,
    """
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_plan_import.csv")
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let importedCount = try await LogCSV.importCSVAsync(from: tempURL, into: context, tag: "test", dedupe: false)
        XCTAssertEqual(importedCount, 1)
    }
    
    func testCSVImportDeduplication() async throws {
        let csvContent = """
    \(testCSVHeader)
    2025-08-23 11:22:11,exercise,Deadlifts,,,,,,,,,,,5,3,50.000,,,,,"Felt strong",,,
    2025-08-23 11:22:11,exercise,Deadlifts,,,,,,,,,,,5,3,50.000,,,,,"Felt strong",,,
    2025-08-23 11:22:11,exercise,Deadlifts,,,,,,,,,,,5,3,50.000,,,,,"Felt strong",,,
    """
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_dedupe.csv")
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let importedCount = try await LogCSV.importCSVAsync(from: tempURL, into: context, tag: "test", dedupe: true)
        XCTAssertLessThanOrEqual(importedCount, 1)
    }
    
    
    // MARK: - Catalog reconciliation on plan import

    /// Plan views resolve grouping/guidance/logging affordances by exercise name
    /// against the catalog, so importing a plan must create the missing entries.
    private func importPlanCSV(
        named fileName: String,
        rows: [String],
        header: String? = nil
    ) async throws -> Int {
        let csvContent = ([header ?? testCSVHeader] + rows).joined(separator: "\n")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        return try await LogCSV.importCSVAsync(from: tempURL, into: context, tag: "catalog", dedupe: false)
    }

    private func catalogExercises() -> [(activity: String, type: String, exercise: Exercise)] {
        let activities = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        return activities.flatMap { activity in
            activity.types.flatMap { type in
                type.exercises.map { (activity.name, type.name, $0) }
            }
        }
    }

    func testPlanImportCreatesCatalogEntries() async throws {
        let planId = UUID()
        let planName = "Imported Plan"
        let imported = try await importPlanCSV(named: "catalog_create.csv", rows: [
            "2025-08-23 11:30:00,exercise,Boulder Project,,,,,,,,,,,,5,3,45.000,,\(planId.uuidString),\(planName),,Stay tense,,,",
            "2025-08-23 11:31:00,exercise,Hangboard Repeaters,,,,,,,,,,,,7,4,0.000,,\(planId.uuidString),\(planName),,,,,"
        ])
        XCTAssertEqual(imported, 2)

        let entries = catalogExercises()
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.exercise.name, $0) })

        let boulder = try XCTUnwrap(byName["Boulder Project"], "Boulder-named exercise should be in the catalog")
        XCTAssertEqual(boulder.activity, "Imported Bouldering",
                       "Boulder-named exercises route to the bouldering-tinted activity")
        XCTAssertEqual(boulder.exercise.shape, .attempts,
                       "The activity name only carries the tint — the shape is what routes it to the climb log")
        XCTAssertEqual(boulder.type, planName, "TrainingType should be named after the source plan")
        XCTAssertEqual(boulder.exercise.repsText, "5")
        XCTAssertEqual(boulder.exercise.setsText, "3")
        XCTAssertEqual(boulder.exercise.durationText, "45 min")
        XCTAssertEqual(boulder.exercise.notes, "Stay tense")

        let hangboard = try XCTUnwrap(byName["Hangboard Repeaters"])
        XCTAssertEqual(hangboard.activity, "Imported")
        XCTAssertEqual(hangboard.type, planName)
        XCTAssertEqual(hangboard.exercise.repsText, "7")
        XCTAssertEqual(hangboard.exercise.setsText, "4")
        XCTAssertNil(hangboard.exercise.durationText, "A 0.000 duration means unset, not \"0 min\"")
        XCTAssertEqual(hangboard.exercise.shape, .weighted, "Unclassified imports keep the weight field")
    }

    /// A re-import must not overrule a classification the user (or the seed) already set.
    func testReimportDoesNotOverruleAnExistingShape() async throws {
        let planId = UUID()
        let rows = [
            "2025-08-25 09:00:00,exercise,Boulder Project,,,,,,,,,,,,5,3,0.000,,\(planId.uuidString),Shape Plan,,,,,"
        ]

        // The user decided this one is weighted — ankle weights on board problems, say.
        let activity = createTestActivity(name: "Strength")
        let type = createTestTrainingType(activity: activity, name: "Mine")
        let mine = Exercise(name: "Boulder Project", shapeKey: ExerciseShape.weighted.rawValue)
        type.exercises.append(mine)
        try context.save()

        _ = try await importPlanCSV(named: "catalog_shape.csv", rows: rows)

        XCTAssertEqual(mine.shape, .weighted, "An existing classification must survive a re-import")
    }

    func testPlanImportDoesNotDuplicateCatalogEntries() async throws {
        let planId = UUID()
        let rows = [
            "2025-08-24 09:00:00,exercise,Campus Ladders,,,,,,,,,,,,6,3,0.000,,\(planId.uuidString),Dup Plan,,,,,"
        ]

        // Pre-existing user catalog entry with the same name must win.
        let activity = createTestActivity(name: "Strength")
        let type = createTestTrainingType(activity: activity, name: "Power")
        createTestExercise(trainingType: type, name: "Campus Ladders", repsText: "original")
        try context.save()

        _ = try await importPlanCSV(named: "catalog_dup_1.csv", rows: rows)
        let afterFirst = catalogExercises()
        XCTAssertEqual(afterFirst.filter { $0.exercise.name == "Campus Ladders" }.count, 1,
                       "Existing catalog name should not be duplicated by import")
        XCTAssertEqual(afterFirst.first { $0.exercise.name == "Campus Ladders" }?.exercise.repsText, "original",
                       "Existing catalog entry should be left untouched")

        _ = try await importPlanCSV(named: "catalog_dup_2.csv", rows: rows)
        XCTAssertEqual(catalogExercises().count, afterFirst.count,
                       "Re-importing the same plan should not add catalog entries")
    }

    func testLogOnlyImportDoesNotTouchCatalog() async throws {
        let imported = try await importPlanCSV(named: "catalog_logonly.csv", rows: [
            "2025-08-25 08:00:00,exercise,Boulder Freeplay,,,,,,,,,,,,10,2,0.000,,,,,No plan here,,,"
        ])
        XCTAssertEqual(imported, 1)
        XCTAssertTrue(catalogExercises().isEmpty, "Rows without a plan_id must not pollute the catalog")
    }

    // MARK: - Timers in the plan CSV

    /// Header including the timer columns. The plain `testCSVHeader` above deliberately
    /// stays without them, so the older-file path keeps being exercised.
    private var testCSVHeaderWithTimers: String { testCSVHeader + ",rest,timer_name,timer_spec" }

    private func timerRow(
        date: String = "2025-09-10 09:00:00",
        exercise: String,
        planId: UUID,
        planName: String = "Timer Plan",
        rest: String = "",
        timerName: String = "",
        timerSpec: String = ""
    ) -> String {
        "\(date),exercise,\(exercise),,,,,,,,,,,,5,3,0.000,,\(planId.uuidString),\(planName),,,,,,\(rest),\(timerName),\(timerSpec)"
    }

    private func catalogTemplates() -> [TimerTemplate] {
        (try? context.fetch(FetchDescriptor<TimerTemplate>())) ?? []
    }

    private func exercise(named name: String) -> Exercise? {
        catalogExercises().first { $0.exercise.name == name }?.exercise
    }

    func testImportCreatesTimerTemplateFromSpec() async throws {
        let planId = UUID()
        _ = try await importPlanCSV(named: "timer_create.csv", rows: [
            timerRow(exercise: "Weighted Pull-Ups", planId: planId,
                     timerName: "Pull Protocol", timerSpec: "reps=5;sets=3;rest=180")
        ], header: testCSVHeaderWithTimers)

        let template = try XCTUnwrap(catalogTemplates().first { $0.name == "Pull Protocol" })
        XCTAssertEqual(template.repsPerSet, 5, "reps= marks the template rep-based")
        XCTAssertEqual(template.repeatCount, 3)
        XCTAssertEqual(template.restTimeBetweenIntervals, 180)

        let imported = try XCTUnwrap(exercise(named: "Weighted Pull-Ups"))
        XCTAssertEqual(imported.timerTemplateId, template.id)

        // And it classifies the way the timer expects.
        guard case .repBased(let reps, let sets, let rest, _)? =
                ExerciseTimerDefaults.plan(for: imported, in: context) else {
            return XCTFail("Imported exercise should be rep-based")
        }
        XCTAssertEqual(reps, 5)
        XCTAssertEqual(sets, 3)
        XCTAssertEqual(rest, 180)
    }

    func testImportReusesExistingTemplateByName() async throws {
        let existing = TimerTemplate(name: "Shared Protocol", totalTimeSeconds: 90)
        context.insert(existing)
        try context.save()
        let countBefore = catalogTemplates().count

        let planId = UUID()
        _ = try await importPlanCSV(named: "timer_reuse.csv", rows: [
            timerRow(exercise: "Some Hangs", planId: planId,
                     timerName: "shared protocol", timerSpec: "total=999")
        ], header: testCSVHeaderWithTimers)

        XCTAssertEqual(catalogTemplates().count, countBefore, "Matching by name must reuse, not create")
        XCTAssertEqual(exercise(named: "Some Hangs")?.timerTemplateId, existing.id)
        XCTAssertEqual(existing.totalTimeSeconds, 90, "The existing template is not rewritten by the spec")
    }

    func testReimportingCreatesNoDuplicateTemplates() async throws {
        let planId = UUID()
        let rows = [
            timerRow(exercise: "Repeat Hangs", planId: planId,
                     timerName: "Once Only", timerSpec: "total=120")
        ]

        _ = try await importPlanCSV(named: "timer_dup_1.csv", rows: rows, header: testCSVHeaderWithTimers)
        let afterFirst = catalogTemplates().count

        _ = try await importPlanCSV(named: "timer_dup_2.csv", rows: rows, header: testCSVHeaderWithTimers)
        XCTAssertEqual(catalogTemplates().count, afterFirst, "Re-import must not duplicate the template")
        XCTAssertEqual(catalogTemplates().filter { $0.name == "Once Only" }.count, 1)
    }

    func testImportNeverOverwritesAnExistingAttachment() async throws {
        let activity = createTestActivity(name: "Strength")
        let type = createTestTrainingType(activity: activity, name: "Power")
        let mine = TimerTemplate(name: "My Choice", totalTimeSeconds: 60)
        context.insert(mine)
        let existing = Exercise(name: "Guarded Exercise", timerTemplateId: mine.id)
        type.exercises.append(existing)
        try context.save()

        _ = try await importPlanCSV(named: "timer_guard.csv", rows: [
            timerRow(exercise: "Guarded Exercise", planId: UUID(),
                     timerName: "Intruder", timerSpec: "total=999")
        ], header: testCSVHeaderWithTimers)

        XCTAssertEqual(existing.timerTemplateId, mine.id, "An import must not steal an existing attachment")
    }

    /// An exercise already in the catalog but without a timer may adopt one.
    func testImportFillsMissingTimerOnExistingExercise() async throws {
        let activity = createTestActivity(name: "Strength")
        let type = createTestTrainingType(activity: activity, name: "Power")
        let existing = Exercise(name: "Adoptable")
        type.exercises.append(existing)
        try context.save()

        _ = try await importPlanCSV(named: "timer_adopt.csv", rows: [
            timerRow(exercise: "Adoptable", planId: UUID(),
                     timerName: "Adopted", timerSpec: "total=45")
        ], header: testCSVHeaderWithTimers)

        let template = try XCTUnwrap(catalogTemplates().first { $0.name == "Adopted" })
        XCTAssertEqual(existing.timerTemplateId, template.id)
    }

    /// Without a rest column an imported exercise has nothing to derive a timer from,
    /// which is exactly why the column exists.
    func testImportedRestMakesAnExerciseRepBased() async throws {
        _ = try await importPlanCSV(named: "timer_rest.csv", rows: [
            timerRow(exercise: "Pull-ups Weighted", planId: UUID(), rest: "3 min")
        ], header: testCSVHeaderWithTimers)

        let imported = try XCTUnwrap(exercise(named: "Pull-ups Weighted"))
        XCTAssertEqual(imported.restText, "3 min")

        guard case .repBased(let reps, let sets, let restSeconds, _)? =
                ExerciseTimerDefaults.plan(for: imported, in: context) else {
            return XCTFail("An imported exercise with rest should be rep-based")
        }
        XCTAssertEqual(reps, 5)
        XCTAssertEqual(sets, 3)
        XCTAssertEqual(restSeconds, 180)
    }

    func testImportWithoutRestLeavesExerciseWithoutATimer() async throws {
        _ = try await importPlanCSV(named: "timer_norest.csv", rows: [
            timerRow(exercise: "No Rest Info", planId: UUID())
        ], header: testCSVHeaderWithTimers)

        let imported = try XCTUnwrap(exercise(named: "No Rest Info"))
        XCTAssertNil(imported.restText)
        XCTAssertNil(ExerciseTimerDefaults.plan(for: imported, in: context),
                     "Nothing to time and no rest to count — the user picks a template")
    }

    /// Re-importing an improved CSV should heal entries an earlier import created,
    /// filling only the gaps.
    func testReimportFillsMissingGuidanceWithoutOverwriting() async throws {
        let planId = UUID()

        // First import: no rest column value at all.
        _ = try await importPlanCSV(named: "heal_1.csv", rows: [
            timerRow(exercise: "Healable", planId: planId)
        ], header: testCSVHeaderWithTimers)
        let imported = try XCTUnwrap(exercise(named: "Healable"))
        XCTAssertNil(imported.restText)
        XCTAssertEqual(imported.repsText, "5")

        // Second import of the same exercise, now carrying rest.
        _ = try await importPlanCSV(named: "heal_2.csv", rows: [
            timerRow(exercise: "Healable", planId: planId, rest: "2 min")
        ], header: testCSVHeaderWithTimers)

        XCTAssertEqual(imported.restText, "2 min", "The missing field gets filled in")
        XCTAssertEqual(imported.repsText, "5", "Existing values are not rewritten")
        XCTAssertEqual(catalogExercises().filter { $0.exercise.name == "Healable" }.count, 1,
                       "Still exactly one catalog entry")
    }

    /// Pins the fixture (Fixtures/plan-timers-fast.csv): four short-rest exercises covering
    /// every branch of the classifier, so the file stays importable as the format evolves.
    /// It is a plan fixture, hence `type=plan` — importing it must not log anything.
    func testDebugTimersFixtureClassifiesEveryBranch() async throws {
        let planId = UUID().uuidString
        let imported = try await importPlanCSV(named: "debug_fixture.csv", rows: [
            "2026-07-30 09:00:00,plan,DEBUG Rep 5s,,,,,,,,,,,,3,3,0.000,,\(planId),DEBUG Timers,,Rep-based derived from rest text,,,,5 sec,,",
            "2026-07-30 09:05:00,plan,DEBUG Rep Spec 8s,,,,,,,,,,,,3,4,0.000,,\(planId),DEBUG Timers,,Rep-based from timer_spec,,,,,DEBUG Fast Protocol,reps=3;sets=4;rest=8",
            "2026-07-30 09:10:00,plan,DEBUG Interval 10s,,,,,,,,,,,,,,0.000,,\(planId),DEBUG Timers,,Duration-based - auto advances,,,,,DEBUG Fast Interval,interval=Work|10|5|3",
            "2026-07-30 09:15:00,plan,DEBUG Single Set,,,,,,,,,,,,5,1,0.000,,\(planId),DEBUG Timers,,Finishes on the first Done,,,,5 sec,,"
        ], header: testCSVHeaderWithTimers)
        XCTAssertEqual(imported, 4)
        XCTAssertTrue(((try? context.fetch(FetchDescriptor<SessionItem>())) ?? []).isEmpty,
                      "The fixture describes a plan, so nothing may land in the log")

        func plan(_ name: String) throws -> ExerciseTimerPlan {
            let exercise = try XCTUnwrap(self.exercise(named: name), "\(name) should be in the catalog")
            return try XCTUnwrap(ExerciseTimerDefaults.plan(for: exercise, in: context), "\(name) should have a timer")
        }

        // Derived from "5 sec" — the seconds unit must not be read as minutes.
        guard case .repBased(let reps, let sets, let rest, _) = try plan("DEBUG Rep 5s") else {
            return XCTFail("DEBUG Rep 5s should be rep-based")
        }
        XCTAssertEqual((reps, sets, rest).0, 3)
        XCTAssertEqual(sets, 3)
        XCTAssertEqual(rest, 5, "5 sec is five seconds, not five minutes")

        guard case .repBased(let specReps, let specSets, let specRest, let specTemplate) = try plan("DEBUG Rep Spec 8s") else {
            return XCTFail("DEBUG Rep Spec 8s should be rep-based")
        }
        XCTAssertEqual(specReps, 3)
        XCTAssertEqual(specSets, 4)
        XCTAssertEqual(specRest, 8)
        XCTAssertNotNil(specTemplate, "Comes from an explicit template")

        guard case .durationBased(let config, _) = try plan("DEBUG Interval 10s") else {
            return XCTFail("DEBUG Interval 10s should be duration-based")
        }
        let interval = try XCTUnwrap(config.intervals.first)
        XCTAssertEqual(interval.workTimeSeconds, 10)
        XCTAssertEqual(interval.restTimeSeconds, 5)
        XCTAssertEqual(interval.repetitions, 3)

        guard case .repBased(_, let singleSets, _, _) = try plan("DEBUG Single Set") else {
            return XCTFail("DEBUG Single Set should be rep-based")
        }
        XCTAssertEqual(singleSets, 1, "Finishes on the first confirmation, no rest ever runs")
    }

    // MARK: - `type=plan` rows are templates, not logs

    /// A row describing a planned exercise. `plan_id` blank means "fork a new plan".
    private func planRow(
        date: String = "2026-03-02 09:00:00",
        exercise: String,
        planId: UUID? = nil,
        planName: String = "Template Plan",
        reps: String = "5",
        sets: String = "3",
        duration: String = "0.000",
        dayType: String = "",
        type: String = "plan",
        notes: String = ""
    ) -> String {
        let id = planId?.uuidString ?? ""
        return "\(date),\(type),\(exercise),,,,,,,,,,,,\(reps),\(sets),\(duration),,\(id),\(planName),\(dayType),\(notes),,,"
    }

    private func allPlans() -> [Plan] {
        (try? context.fetch(FetchDescriptor<Plan>())) ?? []
    }

    private func loggedItems() -> [SessionItem] {
        (try? context.fetch(FetchDescriptor<SessionItem>())) ?? []
    }

    /// The reported bug: importing a plan made every exercise show up as already logged.
    func testPlanRowsCreateNoLoggedItems() async throws {
        let planId = UUID()
        let imported = try await importPlanCSV(named: "plan_no_logs.csv", rows: [
            planRow(exercise: "Hangboard Repeaters", planId: planId),
            planRow(exercise: "Pull-ups Weighted", planId: planId)
        ])
        XCTAssertEqual(imported, 2, "Two plan-day exercises landed")

        XCTAssertTrue(loggedItems().isEmpty, "A planned exercise is not a performed one")
        XCTAssertTrue(((try? context.fetch(FetchDescriptor<Session>())) ?? []).isEmpty,
                      "No plan row may open a Session")

        let plan = try XCTUnwrap(allPlans().first { $0.id == planId })
        let day = try XCTUnwrap(plan.days.first, "The plan day is still built")
        XCTAssertEqual(Set(day.chosenExercises), ["Hangboard Repeaters", "Pull-ups Weighted"])
    }

    /// Plan views resolve grouping and guidance by name against the catalog, so the
    /// catalog side must keep working now that plan rows skip the log.
    func testPlanRowsStillPopulateCatalog() async throws {
        _ = try await importPlanCSV(named: "plan_catalog.csv", rows: [
            planRow(exercise: "Boulder Project", planId: UUID(), planName: "Catalog Plan",
                    duration: "45.000", notes: "Stay tense")
        ])

        let entry = try XCTUnwrap(catalogExercises().first { $0.exercise.name == "Boulder Project" })
        XCTAssertEqual(entry.activity, "Imported Bouldering")
        XCTAssertEqual(entry.type, "Catalog Plan")
        XCTAssertEqual(entry.exercise.repsText, "5")
        XCTAssertEqual(entry.exercise.setsText, "3")
        XCTAssertEqual(entry.exercise.durationText, "45 min")
        XCTAssertEqual(entry.exercise.notes, "Stay tense")
    }

    /// The day editor sorts by `exerciseOrder`, falling back to catalog then alphabetical
    /// order, so the file's row order only survives if import writes that dictionary.
    func testPlanRowOrderIsPreserved() async throws {
        let planId = UUID()
        _ = try await importPlanCSV(named: "plan_order.csv", rows: [
            planRow(exercise: "Zercher Squat", planId: planId),
            planRow(exercise: "Ape Index Reach", planId: planId),
            planRow(exercise: "Muscle-up", planId: planId)
        ])

        let plan = try XCTUnwrap(allPlans().first { $0.id == planId })
        let day = try XCTUnwrap(plan.days.first)
        let expected = ["Zercher Squat", "Ape Index Reach", "Muscle-up"]
        XCTAssertEqual(day.chosenExercises, expected, "Row order, not alphabetical")
        XCTAssertEqual(expected.map { day.exerciseOrder[$0] }, [0, 1, 2],
                       "exerciseOrder pins the row order for the UI")
    }

    /// Blanking `plan_id` forks a fresh plan, so an edited export can be loaded alongside
    /// the original and the old one deleted by hand. One mint per plan_name, not per row.
    func testBlankPlanIdForksNewPlan() async throws {
        let planId = UUID()
        _ = try await importPlanCSV(named: "fork_original.csv", rows: [
            planRow(exercise: "Front Lever Pulls", planId: planId, planName: "Week 1"),
            planRow(exercise: "Hangboard Repeaters", planId: planId, planName: "Week 1")
        ])
        XCTAssertEqual(allPlans().count, 1)

        // Same file with the plan_id column cleared.
        let forked = try await importPlanCSV(named: "fork_copy.csv", rows: [
            planRow(exercise: "Front Lever Pulls", planName: "Week 1"),
            planRow(exercise: "Hangboard Repeaters", planName: "Week 1")
        ])
        XCTAssertEqual(forked, 2)

        let plans = allPlans()
        XCTAssertEqual(plans.count, 2, "The fork is a second plan, the original is untouched")
        let fresh = try XCTUnwrap(plans.first { $0.id != planId })
        XCTAssertEqual(fresh.name, "Week 1")
        XCTAssertEqual(fresh.days.count, 1, "Both blank-id rows joined the same new plan")
        XCTAssertEqual(fresh.days.first?.chosenExercises.count, 2)
    }

    /// A known plan_id edits that plan in place, additively: the file adds, never removes.
    func testKnownPlanIdMergesAdditively() async throws {
        let planId = UUID()
        _ = try await importPlanCSV(named: "merge_first.csv", rows: [
            planRow(exercise: "Hangboard Repeaters", planId: planId),
            planRow(exercise: "Core Rollouts", planId: planId)
        ])

        // Second file drops Core Rollouts and adds Campus Ladders.
        let added = try await importPlanCSV(named: "merge_second.csv", rows: [
            planRow(exercise: "Hangboard Repeaters", planId: planId),
            planRow(exercise: "Campus Ladders", planId: planId)
        ])
        XCTAssertEqual(added, 1, "Only the genuinely new exercise counts")

        let plan = try XCTUnwrap(allPlans().first { $0.id == planId })
        XCTAssertEqual(plan.days.count, 1, "Same date heals the existing day, no duplicate")
        let day = try XCTUnwrap(plan.days.first)
        XCTAssertEqual(day.chosenExercises,
                       ["Hangboard Repeaters", "Core Rollouts", "Campus Ladders"],
                       "Union: a line removed from the CSV is not removed from the plan")
    }

    /// One file may carry both a template and real history for the same day.
    func testExercisePlanRowsCoexist() async throws {
        let planId = UUID()
        let imported = try await importPlanCSV(named: "plan_and_log.csv", rows: [
            planRow(exercise: "Hangboard Repeaters", planId: planId),
            planRow(exercise: "Pull-ups Weighted", planId: planId),
            planRow(exercise: "Hangboard Repeaters", planId: planId, type: "exercise",
                    notes: "Felt strong")
        ])
        XCTAssertEqual(imported, 3, "Two plan-day exercises plus one logged item")

        let plan = try XCTUnwrap(allPlans().first { $0.id == planId })
        XCTAssertEqual(plan.days.first?.chosenExercises,
                       ["Hangboard Repeaters", "Pull-ups Weighted"])

        let logged = loggedItems()
        XCTAssertEqual(logged.count, 1, "Only the exercise row is history")
        XCTAssertEqual(logged.first?.exerciseName, "Hangboard Repeaters")
        XCTAssertEqual(logged.first?.notes, "Felt strong")
    }

    /// Export used to walk only Session.items, so a plan day nobody had logged against
    /// round-tripped to nothing. It must now survive the trip as `type=plan` rows.
    func testPlanRoundTrip() async throws {
        let kind = try ensurePlanKind(context, key: "weekly", name: "Weekly")
        let plan = Plan(name: "Round Trip Plan", kind: kind, startDate: Date())
        context.insert(plan)

        let dayDate = Calendar.current.startOfDay(for: Date())
        let dayType = DayTypeModel(key: "strength", name: "Strength", colorKey: "gray")
        context.insert(dayType)
        let day = PlanDay(date: dayDate, type: dayType)
        day.chosenExercises = ["Zercher Squat", "Ape Index Reach"]
        day.exerciseOrder = ["Zercher Squat": 0, "Ape Index Reach": 1]
        plan.days.append(day)

        // Guidance lives on the catalog, which is where plan rows source their metrics.
        let activity = createTestActivity(name: "Strength")
        let trainingType = createTestTrainingType(activity: activity, name: "Power")
        let seeded = createTestExercise(trainingType: trainingType, name: "Zercher Squat", repsText: "5")
        seeded.setsText = "4"
        seeded.durationText = "45 min"
        seeded.notes = "Brace hard"
        try context.save()

        let exported = LogCSV.makeExportCSV(context: context).csv
        let planRows = exported.split(separator: "\n").filter { $0.contains(",plan,") }
        XCTAssertEqual(planRows.count, 2, "One row per plan-day exercise")
        XCTAssertTrue(planRows[0].contains("Zercher Squat"), "Export follows exerciseOrder")
        XCTAssertTrue(planRows[0].contains("strength"), "day_type carries the key")
        XCTAssertTrue(planRows[0].contains("Brace hard"), "notes come from the catalog")
        XCTAssertTrue(planRows[0].contains(",5,4,45.000,"),
                      "reps/sets/duration parsed out of the guidance text: \(planRows[0])")
        XCTAssertTrue(planRows[1].contains("Ape Index Reach"))

        // Drop the plan subtree, then rebuild it from the CSV alone.
        plan.days.forEach { context.delete($0) }
        context.delete(plan)
        try context.save()
        XCTAssertTrue(allPlans().isEmpty)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plan_rt.csv")
        try exported.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await LogCSV.importCSVAsync(from: url, into: context, tag: "plan-rt", dedupe: true)

        let restored = try XCTUnwrap(allPlans().first { $0.name == "Round Trip Plan" })
        let restoredDay = try XCTUnwrap(restored.days.first)
        XCTAssertEqual(restoredDay.chosenExercises, ["Zercher Squat", "Ape Index Reach"],
                       "Names and order both survive")
        XCTAssertEqual(restoredDay.type?.key, "strength")
        XCTAssertTrue(loggedItems().isEmpty, "A round-tripped plan is still not a log")
    }

    /// Imports the real Fixtures/plan-timers-fast.csv off disk — not a copy of its rows —
    /// and then runs the two computations the plan day editor renders from. This is the
    /// on-screen bug expressed as a test: "Logged exercises" must read empty for a freshly
    /// imported plan. Reading the file itself also stops it drifting from the inline rows
    /// in testDebugTimersFixtureClassifiesEveryBranch above.
    func testShippedFixtureImportsAsAPlanWithAnEmptyLog() async throws {
        let testsRoot = URL(fileURLWithPath: #filePath)     // …/ClimbingProgramTests/ImportExportTests.swift
            .deletingLastPathComponent()
        let fixture = testsRoot.appendingPathComponent("Fixtures/plan-timers-fast.csv")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            return XCTFail("Fixture missing at \(fixture.path)")
        }

        let imported = try await LogCSV.importCSVAsync(from: fixture, into: context,
                                                      tag: "fixture", dedupe: true)
        XCTAssertEqual(imported, 4, "Four planned exercises")

        let plan = try XCTUnwrap(allPlans().first { $0.name == "DEBUG Timers" })

        // 1) What "Logged exercises" renders — the same fetch as
        //    PlanDayEditor.refreshLoggedItemsIntoCache(): sessions on the day, then the
        //    items belonging to this plan. This is the reported bug.
        for day in plan.days {
            let start = Calendar.current.startOfDay(for: day.date)
            let end = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: start))
            let sessions = (try? context.fetch(FetchDescriptor<Session>(
                predicate: #Predicate<Session> { $0.date >= start && $0.date < end }
            ))) ?? []
            let shown = sessions.flatMap(\.items).filter { $0.planSourceId == plan.id }
            XCTAssertTrue(shown.isEmpty,
                          "\(day.date) should read \"No logs yet for this day\", got \(shown.map(\.exerciseName))")
        }

        // 2) What "Chosen activities" renders, in the file's own row order.
        let names = plan.days
            .sorted { $0.date < $1.date }
            .flatMap { day in
                day.chosenExercises.sorted { (day.exerciseOrder[$0] ?? .max) < (day.exerciseOrder[$1] ?? .max) }
            }
        XCTAssertEqual(names, ["DEBUG Rep 5s", "DEBUG Rep Spec 8s",
                               "DEBUG Interval 10s", "DEBUG Single Set"])
    }

    /// Clearing the whole plan_id column to fork also blanks it on the log rows. Those
    /// rows can no longer dedupe against the history they came from, so importing them
    /// would duplicate every logged item. They are dropped instead.
    func testForkSkipsOrphanLogRows() async throws {
        let planId = UUID()
        _ = try await importPlanCSV(named: "orphan_seed.csv", rows: [
            planRow(exercise: "Hangboard Repeaters", planId: planId, planName: "Week 1"),
            planRow(exercise: "Hangboard Repeaters", planId: planId, planName: "Week 1",
                    type: "exercise", notes: "Felt strong")
        ])
        XCTAssertEqual(loggedItems().count, 1)

        // The same file with plan_id cleared everywhere.
        _ = try await importPlanCSV(named: "orphan_fork.csv", rows: [
            planRow(exercise: "Hangboard Repeaters", planName: "Week 1"),
            planRow(exercise: "Hangboard Repeaters", planName: "Week 1",
                    type: "exercise", notes: "Felt strong")
        ])

        XCTAssertEqual(loggedItems().count, 1, "The orphaned log row was dropped, not duplicated")
        XCTAssertEqual(allPlans().count, 2, "The template still forked")
    }

    func testLogOnlyRowsCreateNoTemplates() async throws {
        _ = try await importPlanCSV(named: "timer_logonly.csv", rows: [
            "2025-09-11 09:00:00,exercise,No Plan Here,,,,,,,,,,,,5,3,0.000,,,,,,,,,Ghost Timer,total=60"
        ], header: testCSVHeaderWithTimers)

        XCTAssertTrue(catalogTemplates().isEmpty, "Rows without a plan_id must not create templates")
    }

    func testCSVWithoutTimerColumnsStillImports() async throws {
        let planId = UUID()
        let imported = try await importPlanCSV(named: "timer_absent.csv", rows: [
            "2025-09-12 09:00:00,exercise,Legacy Exercise,,,,,,,,,,,,5,3,0.000,,\(planId.uuidString),Legacy Plan,,,,,"
        ])
        XCTAssertEqual(imported, 1)
        XCTAssertNotNil(exercise(named: "Legacy Exercise"))
        XCTAssertTrue(catalogTemplates().isEmpty)
    }

    // MARK: - Per-set detail round-trip

    /// The flat reps/sets/weight columns are a lossy rollup, so without a dedicated
    /// column an export/import cycle would silently discard per-set weight, effort
    /// and notes. Export is the backup path — that would be data loss.
    func testPerSetDetailSurvivesExportImportRoundTrip() async throws {
        let session = Session(date: parseDay("2026-03-04"))
        context.insert(session)
        session.items.append(
            SessionItem(
                exerciseName: "Weighted Pull-up",
                reps: 3,
                sets: 3,
                weightKg: 30,
                loggedSets: [
                    LoggedSet(reps: 3, weightKg: 30, rpe: 1),
                    LoggedSet(reps: 3, weightKg: 32.5, rpe: 3, note: "grip slipped, comma & \"quote\""),
                    LoggedSet(reps: 2, weightKg: 27.5, rpe: 5)
                ]
            )
        )
        try context.save()

        let exported = LogCSV.makeExportCSV(context: context).csv
        XCTAssertTrue(exported.contains("sets_detail"), "The column has to be in the header")

        (try? context.fetch(FetchDescriptor<Session>()))?.forEach { context.delete($0) }
        try context.save()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("per_set_roundtrip.csv")
        try exported.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await LogCSV.importCSVAsync(from: url, into: context, tag: "per-set", dedupe: false)

        let item = try XCTUnwrap(loggedItems().first { $0.exerciseName == "Weighted Pull-up" })
        XCTAssertEqual(item.loggedSets.count, 3)
        XCTAssertEqual(item.loggedSets.map(\.weightKg), [30, 32.5, 27.5])
        XCTAssertEqual(item.loggedSets.map(\.reps), [3, 3, 2])
        XCTAssertEqual(item.loggedSets.map(\.rpe), [1, 3, 5])
        XCTAssertEqual(
            item.loggedSets[1].note, "grip slipped, comma & \"quote\"",
            "A note with a comma and quotes must survive CSV escaping"
        )
    }

    /// Build a row by column name against a header, so a fixture can't silently land a
    /// value in the wrong column from a miscounted comma run.
    private func csvRow(_ values: [String: String], header: String) -> String {
        header.split(separator: ",").map { column in
            let value = values[String(column)] ?? ""
            return value.contains(",") || value.contains("\"")
                ? "\"\(value.replacing("\"", with: "\"\""))\""
                : value
        }
        .joined(separator: ",")
    }

    /// Hand-logged items and every pre-existing export have no per-set detail; the
    /// blank cell must import as "no detail", not as a broken row.
    func testRowsWithoutPerSetDetailImportCleanly() async throws {
        let header = testCSVHeaderWithTimers
        let imported = try await importPlanCSV(named: "no_set_detail.csv", rows: [
            csvRow([
                "date": "2026-03-05 09:00:00",
                "type": "exercise",
                "exercise_name": "Plain Pull-up",
                "reps": "8",
                "sets": "3"
            ], header: header)
        ], header: header)

        XCTAssertEqual(imported, 1)
        let item = try XCTUnwrap(loggedItems().first { $0.exerciseName == "Plain Pull-up" })
        XCTAssertEqual(item.loggedSets, [], "No detail is not an error")
        XCTAssertEqual(item.reps, 8, "The rollup columns still carry the numbers")
        XCTAssertEqual(item.sets, 3)
    }

    /// A hand-mangled cell must not take the row down with it.
    func testMalformedPerSetDetailIsIgnored() async throws {
        let header = testCSVHeaderWithTimers + ",sets_detail"
        let imported = try await importPlanCSV(named: "bad_set_detail.csv", rows: [
            csvRow([
                "date": "2026-03-06 09:00:00",
                "type": "exercise",
                "exercise_name": "Broken Detail",
                "reps": "5",
                "sets": "2",
                "sets_detail": "not json at all"
            ], header: header)
        ], header: header)

        XCTAssertEqual(imported, 1, "The row still imports")
        let item = try XCTUnwrap(loggedItems().first { $0.exerciseName == "Broken Detail" })
        XCTAssertEqual(item.loggedSets, [])
        XCTAssertEqual(item.reps, 5)
    }

    /// A per-set cell written by hand rather than exported must still be honoured.
    func testHandWrittenPerSetDetailIsImported() async throws {
        let header = testCSVHeaderWithTimers + ",sets_detail"
        let imported = try await importPlanCSV(named: "hand_set_detail.csv", rows: [
            csvRow([
                "date": "2026-03-08 09:00:00",
                "type": "exercise",
                "exercise_name": "Hand Written",
                "reps": "3",
                "sets": "2",
                "weight_kg": "30",
                "sets_detail": #"[{"reps":3,"weightKg":30,"rpe":2},{"reps":3,"weightKg":32.5}]"#
            ], header: header)
        ], header: header)

        XCTAssertEqual(imported, 1)
        let item = try XCTUnwrap(loggedItems().first { $0.exerciseName == "Hand Written" })
        XCTAssertEqual(item.loggedSets.map(\.weightKg), [30, 32.5])
        XCTAssertEqual(item.loggedSets[0].rpe, 2)
        XCTAssertNil(item.loggedSets[1].rpe)
    }

    /// Per-set detail is outside the dedupe signature, so a second import of the same
    /// export must not double the rows.
    func testReimportingPerSetDetailDoesNotDuplicate() async throws {
        let session = Session(date: parseDay("2026-03-07"))
        context.insert(session)
        session.items.append(
            SessionItem(
                exerciseName: "Dedupe Pull-up",
                reps: 3,
                sets: 2,
                weightKg: 30,
                loggedSets: [LoggedSet(reps: 3, weightKg: 30), LoggedSet(reps: 3, weightKg: 30)]
            )
        )
        try context.save()

        let exported = LogCSV.makeExportCSV(context: context).csv
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("per_set_dedupe.csv")
        try exported.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await LogCSV.importCSVAsync(from: url, into: context, tag: "dd", dedupe: true)

        XCTAssertEqual(
            loggedItems().filter { $0.exerciseName == "Dedupe Pull-up" }.count, 1,
            "The rollup columns are unchanged, so the row dedupes as before"
        )
    }

    func testTimerAttachmentSurvivesExportImportRoundTrip() async throws {
        let planId = UUID()
        _ = try await importPlanCSV(named: "timer_rt_seed.csv", rows: [
            timerRow(exercise: "Round Trip Hangs", planId: planId,
                     timerName: "RT Protocol", timerSpec: "reps=4;sets=2;rest=120")
        ], header: testCSVHeaderWithTimers)

        let exported = LogCSV.makeExportCSV(context: context).csv
        XCTAssertTrue(exported.contains("RT Protocol"), "Export should carry the template name")
        XCTAssertTrue(exported.contains("reps=4;sets=2;rest=120"), "Export should carry the spec")

        // Wipe the attachment, then re-import the export and confirm it comes back.
        let target = try XCTUnwrap(exercise(named: "Round Trip Hangs"))
        target.timerTemplateId = nil
        try context.save()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("timer_roundtrip.csv")
        try exported.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await LogCSV.importCSVAsync(from: url, into: context, tag: "rt", dedupe: true)

        let template = try XCTUnwrap(catalogTemplates().first { $0.name == "RT Protocol" })
        XCTAssertEqual(target.timerTemplateId, template.id, "Attachment restored from the round-tripped CSV")
    }

    // MARK: - Catalog path round-trip

    /// The reported case: an exercise that already lives somewhere in the catalog must
    /// come back to that same node, not to "Imported" → its plan's name.
    func testAnExerciseReturnsToItsOwnCatalogNode() async throws {
        let activity = createTestActivity(name: "Bouldering")
        let type = createTestTrainingType(activity: activity, name: "Limit Bouldering")
        type.exercises.append(
            Exercise(name: "Limit Boulders", restText: "3 min", shapeKey: ExerciseShape.attempts.rawValue)
        )

        let planKind = try ensurePlanKind(context, key: "weekly", name: "Weekly")
        let plan = Plan(name: "Power Block", kind: planKind, startDate: parseDay("2026-04-06"))
        let day = PlanDay(date: parseDay("2026-04-06"))
        day.chosenExercises = ["Limit Boulders"]
        plan.days.append(day)
        context.insert(plan)
        try context.save()

        let exported = LogCSV.makeExportCSV(context: context).csv
        XCTAssertTrue(exported.contains("Bouldering,Limit Bouldering,attempts"),
                      "The export carries the catalog path and shape")

        // Delete the catalog entry entirely, then re-import.
        let original = try XCTUnwrap(exercise(named: "Limit Boulders"))
        type.exercises.removeAll { $0.name == "Limit Boulders" }
        context.delete(original)
        try context.save()
        XCTAssertNil(exercise(named: "Limit Boulders"))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("catalog_path_rt.csv")
        try exported.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await LogCSV.importCSVAsync(from: url, into: context, tag: "rt", dedupe: true)

        let restored = try XCTUnwrap(exercise(named: "Limit Boulders"))
        XCTAssertEqual(restored.shape, .attempts, "Shape comes from the column, not a name guess")

        let activities = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        let home = activities.first { $0.types.contains { $0.exercises.contains { $0.name == "Limit Boulders" } } }
        XCTAssertEqual(home?.name, "Bouldering", "Not \"Imported Bouldering\"")
        XCTAssertEqual(
            home?.types.first(where: { $0.exercises.contains { $0.name == "Limit Boulders" } })?.name,
            "Limit Bouldering",
            "Not the plan's name"
        )
        XCTAssertFalse(activities.contains { $0.name.hasPrefix("Imported") },
                       "Nothing needed the Imported shelf")
    }

    /// Without the columns — an older export, or a hand-written file — the fallback
    /// shelf is still there, and the name heuristic still classifies wall work.
    func testAnUnknownExerciseStillLandsOnTheImportedShelf() async throws {
        _ = try await importPlanCSV(named: "no_path_columns.csv", rows: [
            planRow(exercise: "Mystery Boulder Drill", planId: UUID(), planName: "Some Plan")
        ])

        let restored = try XCTUnwrap(exercise(named: "Mystery Boulder Drill"))
        XCTAssertEqual(restored.shape, .attempts, "The \"boulder\" heuristic is the fallback")

        let activities = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        let home = activities.first { $0.types.contains { $0.exercises.contains { $0.name == "Mystery Boulder Drill" } } }
        XCTAssertEqual(home?.name, "Imported Bouldering")
        XCTAssertEqual(
            home?.types.first(where: { $0.exercises.contains { $0.name == "Mystery Boulder Drill" } })?.name,
            "Some Plan"
        )
    }

    // MARK: - Round-trip Tests

    func testExportImportRoundTrip() async throws {
        // Create original data
        let planKind = try ensurePlanKind(context, key: "weekly", name: "Weekly")
        let plan = Plan(name: "Roundtrip Plan", kind: planKind, startDate: Date())
        context.insert(plan)
        
        let session1 = Session(date: Date())
        let session2 = Session(date: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        
        context.insert(session1)
        context.insert(session2)
        
        let items = [
            SessionItem(exerciseName: "Exercise1", planSourceId: plan.id, planName: plan.name, reps: 10, sets: 3),
            SessionItem(exerciseName: "Exercise2", reps: 12, sets: 4, weightKg: 5.0),
            SessionItem(exerciseName: "Exercise3", planSourceId: plan.id, planName: plan.name, grade: "V5")
        ]
        
        session1.items.append(items[0])
        session1.items.append(items[1])
        session2.items.append(items[2])
        
        try? context.save()
        
        // Export
        let exportDoc = LogCSV.makeExportCSV(context: context)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("roundtrip.csv")
        try exportDoc.csv.write(to: tempURL, atomically: true, encoding: .utf8)
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        // Clear context
        let allSessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        allSessions.forEach { context.delete($0) }
        try? context.save()
        
        // Import back
        let importedCount = try await LogCSV.importCSVAsync(from: tempURL, into: context, tag: "roundtrip", dedupe: false)
        
        XCTAssertEqual(importedCount, 3, "Should import all original items")
        
        // Verify data integrity
        let importedSessions = (try? context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\Session.date)]))) ?? []
        let importedItems = importedSessions.flatMap { $0.items }
        
        XCTAssertEqual(importedItems.count, 3)
        
        let exerciseNames = Set(importedItems.map { $0.exerciseName })
        XCTAssertTrue(exerciseNames.contains("Exercise1"))
        XCTAssertTrue(exerciseNames.contains("Exercise2"))
        XCTAssertTrue(exerciseNames.contains("Exercise3"))
        
        // Verify plan relationships are maintained
        let planLinkedItems = importedItems.filter { $0.planSourceId == plan.id }
        XCTAssertEqual(planLinkedItems.count, 2, "Plan relationships should be preserved")
    }
    

    func testCSVImportMissingFile() async throws {
        let nonExistentURL = FileManager.default.temporaryDirectory.appendingPathComponent("missing.csv")
        
        do {
            _ = try await LogCSV.importCSVAsync(from: nonExistentURL, into: context, tag: "missing", dedupe: false)
            XCTFail("Expected importCSVAsync to throw for missing file, but it succeeded.")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    
    // MARK: - Data Integrity Tests
    
    func testDateConsistencyInExportImport() async throws {
        let specificDate = DateComponents(calendar: Calendar.current, year: 2025, month: 12, day: 25).date!
        let session = Session(date: specificDate)
        context.insert(session)
        
        let item = SessionItem(exerciseName: "abc Workout")
        session.items.append(item)
        try? context.save()
        
        // Export and import
        let exportDoc = LogCSV.makeExportCSV(context: context)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("date_test.csv")
        try exportDoc.csv.write(to: tempURL, atomically: true, encoding: .utf8)
        
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        // Clear and import
        context.delete(session)
        try? context.save()
        
        _ = try await LogCSV.importCSVAsync(from: tempURL, into: context, tag: "date-test", dedupe: false)
        
        // Verify date consistency
        let importedSessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        let importedSession = importedSessions.first!
        
        let calendar = Calendar.current
        XCTAssertEqual(calendar.startOfDay(for: importedSession.date),
                       calendar.startOfDay(for: specificDate),
                       "Date should be preserved through export/import")
    }


    private func parseDay(_ raw: String) -> Date {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        if let d = iso.date(from: raw) { return d }

        let df = DateFormatter()
        df.calendar = Calendar(identifier: .iso8601)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        if let d = df.date(from: raw) { return d }

        preconditionFailure("Invalid date string: \(raw)")
    }

    func testImportClimbUpsertWithExplicitIDAndTB2() async throws {
            let climbId = UUID()
            let tb2 = "XYANX-ALLSA-SIK1902"
            // Seed existing climb
            let day = parseDay("2025-09-01")
            let existing = ClimbEntry(
                id: climbId,
                climbType: .boulder,
                grade: "V4",
                feelsLikeGrade: "V5",
                angleDegrees: 25,
                style: "Old",
                attempts: "2",
                isWorkInProgress: false,
                holdColor: .red,
                gym: "GymA",
                notes: "Old note",
                dateLogged: day,
                tb2ClimbUUID: tb2
            )
            context.insert(existing)
            try context.save()

            let csv = """
            \(testCSVHeader)
            2025-09-01 11:22:11,climb,,boulder,V6,V5,25,red,,Comp,3,false,GymA,,,,,,,,,Updated \(Date()),\(climbId.uuidString),\(tb2),
            """
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("upsert_tb2.csv")
            try csv.write(to: url, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: url) }

            let inserted = try await LogCSV.importCSVAsync(from: url, into: context, dedupe: true)
            XCTAssertEqual(inserted, 0, "Should update not insert")

            let fetched = try context.fetch(FetchDescriptor<ClimbEntry>(predicate: #Predicate { $0.id == climbId }))
            XCTAssertEqual(fetched.first?.grade, "V6")
            XCTAssertEqual(fetched.first?.tb2ClimbUUID, tb2)
        }

        func testImportClimbCreatesStableIDFromTB2() async throws {
            let tb2 = "tb2-alpha-999"
            let csv = """
            \(testCSVHeader)
            2025-09-02 11:22:11,climb,,boulder,V5,V5,30,blue,,Style,4,false,GymB,,,,,,,,,First import,,\(tb2),
            """
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("stable_tb2.csv")
            try csv.write(to: url, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: url) }

            let inserted = try await LogCSV.importCSVAsync(from: url, into: context, dedupe: true)
            XCTAssertEqual(inserted, 1)

            let all = try context.fetch(FetchDescriptor<ClimbEntry>())
            let day = parseDay("2025-09-01")
            let expected = testStableID(climbUUID: tb2, day: day, angle: 30, isWIP: false)
            XCTAssertTrue(all.contains { $0.id == expected })
            XCTAssertEqual(all.first { $0.id == expected }?.tb2ClimbUUID, tb2)
        }

    func testImportClimbStableIDSecondImportUpdates() async throws {
        let tb2 = "tb2-beta-111"
        let first = """
        \(testCSVHeader)
        2025-09-03 11:22:11,climb,,boulder,V3,V5,15,,,Sesh,1,false,GymC,,,,,,,,,Initial,,\(tb2),
        """
        let second = """
        \(testCSVHeader)
        2025-09-03 11:22:11,climb,,boulder,V3,V5,15,,,Sesh,2,false,GymC,,,,,,,,,Updated notes,,\(tb2),
        """
        let u1 = FileManager.default.temporaryDirectory.appendingPathComponent("tb2_first.csv")
        let u2 = FileManager.default.temporaryDirectory.appendingPathComponent("tb2_second.csv")
        try first.write(to: u1, atomically: true, encoding: .utf8)
        try second.write(to: u2, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: u1)
            try? FileManager.default.removeItem(at: u2)
        }

        let firstImport = try await LogCSV.importCSVAsync(from: u1, into: context)
        XCTAssertEqual(firstImport, 1)

        let secondImport = try await LogCSV.importCSVAsync(from: u2, into: context)
        XCTAssertEqual(secondImport, 0, "Second should update not insert")

        let climbs = try context.fetch(FetchDescriptor<ClimbEntry>())
        XCTAssertEqual(climbs.count, 1)
        XCTAssertEqual(climbs.first?.attempts, "2")
        XCTAssertEqual(climbs.first?.notes, "Updated notes")
    }


        func testImportClimbSameTB2DifferentAngleCreatesNew() async throws {
            let tb2 = "tb2-gamma-222"
            let csv = """
                \(testCSVHeader)
                2025-09-01 11:22:11,climb,,boulder,V2,V5,10,,,x,1,false,GymD,,,,,,,,A,,\(tb2),
                2025-09-01 11:22:11,climb,,boulder,V2,V5,20,,,x,1,false,GymD,,,,,,,,B,,\(tb2),
                """
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("tb2_angle.csv")
            try csv.write(to: url, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: url) }

            let inserted = try await LogCSV.importCSVAsync(from: url, into: context, dedupe: true)
            XCTAssertEqual(inserted, 2, "Angle change should produce distinct stable IDs")

            let climbs = try context.fetch(FetchDescriptor<ClimbEntry>())
            XCTAssertEqual(climbs.count, 2)

        }
    }
    
