//
//  PlanCSVImportTests.swift
//  Klettrack tests
//  Created by Shahar Noy on 17.02.26.
//

import XCTest
import SwiftData
@testable import klettrack

final class PlanCSVImportTests: XCTestCase {
    @MainActor
    func testExportPlanCSV_IncludesExpectedRows() throws {
        let schema = Schema([
            PlanKindModel.self,
            DayTypeModel.self,
            Plan.self,
            PlanDay.self,
            Activity.self,
            TrainingType.self,
            Exercise.self
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let planKind = PlanKindModel(key: "weekly", name: "Weekly", totalWeeks: nil, isRepeating: true, order: 1)
        let dayType = DayTypeModel(key: "power", name: "Power", order: 1, colorKey: "red")
        let activity = Activity(name: "Climbing")
        let trainingType = TrainingType(name: "Board")
        let exercise = Exercise(name: "Limit Boulders", area: nil, order: 1)
        trainingType.exercises.append(exercise)
        activity.types.append(trainingType)

        let plan = Plan(name: "Power Block", kind: planKind, startDate: Date(timeIntervalSince1970: 1_706_745_600)) // 2024-02-01
        let dayOne = PlanDay(date: Date(timeIntervalSince1970: 1_706_745_600), type: dayType)
        dayOne.dailyNotes = "Hard session"
        dayOne.chosenExerciseIDs = [exercise.id]
        dayOne.exerciseOrderByID = [exercise.id.uuidString: 0]

        let dayTwo = PlanDay(date: Date(timeIntervalSince1970: 1_706_832_000), type: dayType) // 2024-02-02
        dayTwo.dailyNotes = "Recovery"

        plan.days = [dayOne, dayTwo]
        context.insert(planKind)
        context.insert(dayType)
        context.insert(activity)
        context.insert(plan)
        try context.save()

        let exported = PlanCSV.makeExportCSV(for: plan, in: context).csv
        let lines = exported.components(separatedBy: .newlines).filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(
            lines.first,
            "plan_name,plan_kind,plan_start_date,day_date,weekday,day_type,day_notes,exercise_order,exercise_name,activity_name,training_type_name,exercise_id"
        )
        XCTAssertTrue(lines[1].contains("Power Block"))
        XCTAssertTrue(lines[1].contains("Limit Boulders"))
        XCTAssertTrue(lines[2].contains("Recovery"))
    }

    @MainActor
    func testImportPlanCSV_CreatesPlanDaysAndPlaceholders() async throws {
        let schema = Schema([
            PlanKindModel.self,
            DayTypeModel.self,
            Plan.self,
            PlanDay.self,
            Activity.self,
            TrainingType.self,
            Exercise.self
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let csv = """
        plan_name,plan_kind,plan_start_date,day_date,weekday,day_type,day_notes,exercise_order,exercise_name,activity_name,training_type_name,exercise_id
        Strength Cycle,Imported Kind,2026-02-01,2026-02-01,Sunday,Power Day,Heavy pulls,1,Board Pulls,Climbing,Finger Strength,
        Strength Cycle,Imported Kind,2026-02-01,2026-02-01,Sunday,Power Day,Heavy pulls,2,,Climbing,Grip Endurance,
        Strength Cycle,Imported Kind,2026-02-01,2026-02-02,Monday,Recovery,Easy day,,,,,
        Strength Cycle,Imported Kind,2026-02-01,invalid-date,Monday,Recovery,Skip me,1,Bad Row,Climbing,Grip Endurance,
        """

        let url = FileManager.default.temporaryDirectory.appending(path: "plan-import-\(UUID().uuidString).csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try await PlanCSV.importPlanCSVAsync(from: url, into: context)

        XCTAssertEqual(summary.importedDays, 2)
        XCTAssertEqual(summary.linkedExercises, 2)
        XCTAssertEqual(summary.skippedRows, 1)
        XCTAssertGreaterThan(summary.totalPlaceholders, 0)

        let plans = try context.fetch(FetchDescriptor<Plan>())
        XCTAssertEqual(plans.count, 1)

        let importedPlan = try XCTUnwrap(plans.first)
        XCTAssertEqual(importedPlan.days.count, 2)

        let firstDay = try XCTUnwrap(importedPlan.days.sorted(by: { $0.date < $1.date }).first)
        XCTAssertEqual(firstDay.chosenExerciseIDs.count, 2)
        XCTAssertEqual(firstDay.exerciseOrderByID.count, 2)
        XCTAssertEqual(firstDay.type?.name, "Power Day")
    }

    @MainActor
    func testExportPlanCSV_DoesNotCrashWithDuplicateNormalizedExerciseNames() throws {
        let schema = Schema([
            PlanKindModel.self,
            DayTypeModel.self,
            Plan.self,
            PlanDay.self,
            Activity.self,
            TrainingType.self,
            Exercise.self
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let planKind = PlanKindModel(key: "weekly", name: "Weekly", totalWeeks: nil, isRepeating: true, order: 1)
        let dayType = DayTypeModel(key: "power", name: "Power", order: 1, colorKey: "red")
        let activity = Activity(name: "Climbing")
        let boardType = TrainingType(name: "Board")
        let sprayType = TrainingType(name: "Spray Wall")
        let exerciseOne = Exercise(name: "V0  V2")
        let exerciseTwo = Exercise(name: "v0 v2")
        boardType.exercises.append(exerciseOne)
        sprayType.exercises.append(exerciseTwo)
        activity.types.append(boardType)
        activity.types.append(sprayType)

        let plan = Plan(name: "Power Block", kind: planKind, startDate: Date(timeIntervalSince1970: 1_706_745_600))
        let day = PlanDay(date: Date(timeIntervalSince1970: 1_706_745_600), type: dayType)
        day.chosenExerciseIDs = [exerciseOne.id, exerciseTwo.id]
        day.exerciseOrderByID = [
            exerciseOne.id.uuidString: 0,
            exerciseTwo.id.uuidString: 1
        ]
        plan.days = [day]

        context.insert(planKind)
        context.insert(dayType)
        context.insert(activity)
        context.insert(plan)
        try context.save()

        let exported = PlanCSV.makeExportCSV(for: plan, in: context).csv
        XCTAssertTrue(exported.contains(exerciseOne.id.uuidString))
        XCTAssertTrue(exported.contains(exerciseTwo.id.uuidString))
    }

    @MainActor
    func testImportPlanCSV_AcceptsWebExportShape() async throws {
        let schema = Schema([
            PlanKindModel.self,
            DayTypeModel.self,
            Plan.self,
            PlanDay.self,
            Activity.self,
            TrainingType.self,
            Exercise.self
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let existingActivity = Activity(name: "Climbing")
        let existingTrainingType = TrainingType(name: "Board")
        let existingExercise = Exercise(name: "Moonboard Limit")
        existingTrainingType.exercises.append(existingExercise)
        existingActivity.types.append(existingTrainingType)
        context.insert(existingActivity)
        try context.save()

        let csv = """
        plan_name,plan_kind,plan_start_date,day_date,weekday,day_type,day_notes,exercise_order,exercise_name,activity_name,training_type_name,exercise_id
        Moon Cycle,Weekly,2026-02-01,2026-02-01,Sunday,Power,Hard board session,1,Moonboard Limit,Climbing,Board,\(existingExercise.id.uuidString)
        Moon Cycle,Weekly,2026-02-01,2026-02-02,Monday,Rest,No loading,,,,,
        """

        let url = FileManager.default.temporaryDirectory.appending(path: "plan-web-export-\(UUID().uuidString).csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try await PlanCSV.importPlanCSVAsync(from: url, into: context)
        XCTAssertEqual(summary.importedDays, 2)
        XCTAssertEqual(summary.linkedExercises, 1)
        XCTAssertEqual(summary.skippedRows, 0)

        let plans = try context.fetch(FetchDescriptor<Plan>())
        XCTAssertEqual(plans.count, 1)
        let importedPlan = try XCTUnwrap(plans.first)
        XCTAssertEqual(importedPlan.days.count, 2)

        let sortedDays = importedPlan.days.sorted(by: { $0.date < $1.date })
        XCTAssertEqual(sortedDays[0].chosenExerciseIDs.count, 1)
        XCTAssertEqual(sortedDays[0].dailyNotes, "Hard board session")
        XCTAssertEqual(sortedDays[1].chosenExerciseIDs.count, 0)
        XCTAssertEqual(sortedDays[1].dailyNotes, "No loading")
    }

    @MainActor
    func testImportPlanCSV_DoesNotCrashWithDuplicateNormalizedCatalogNames() async throws {
        let schema = Schema([
            PlanKindModel.self,
            DayTypeModel.self,
            Plan.self,
            PlanDay.self,
            Activity.self,
            TrainingType.self,
            Exercise.self
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let activity = Activity(name: "Climbing")
        let trainingTypeOne = TrainingType(name: "Board")
        let trainingTypeTwo = TrainingType(name: "Spray Wall")
        trainingTypeOne.exercises.append(Exercise(name: "V0  V2"))
        trainingTypeTwo.exercises.append(Exercise(name: "v0 v2"))
        activity.types.append(trainingTypeOne)
        activity.types.append(trainingTypeTwo)
        context.insert(activity)
        try context.save()

        let csv = """
        plan_name,plan_kind,plan_start_date,day_date,weekday,day_type,day_notes,exercise_order,exercise_name,activity_name,training_type_name,exercise_id
        Duplicate Names,Weekly,2026-02-01,2026-02-01,Sunday,Power,Hard board session,1,v0 v2,Climbing,Board,
        """

        let url = FileManager.default.temporaryDirectory.appending(path: "plan-import-duplicate-names-\(UUID().uuidString).csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try await PlanCSV.importPlanCSVAsync(from: url, into: context)
        XCTAssertEqual(summary.importedDays, 1)
        XCTAssertEqual(summary.linkedExercises, 1)

        let plans = try context.fetch(FetchDescriptor<Plan>())
        let importedPlan = try XCTUnwrap(plans.first)
        let firstDay = try XCTUnwrap(importedPlan.days.first)
        XCTAssertEqual(firstDay.chosenExerciseIDs.count, 1)
    }
}
