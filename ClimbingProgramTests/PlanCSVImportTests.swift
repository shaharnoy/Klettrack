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
}
