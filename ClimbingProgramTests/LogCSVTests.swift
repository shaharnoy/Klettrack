//
//  LogCSVTest.swift
//  klettrack Tests
//  Created by Shahar Noy on 30.09.25.
//
import XCTest
import SwiftData
@testable import klettrack

final class LogCSVTests: BaseSwiftDataTestCase {
    
    func testExerciseExportImportRoundTrip_RebuildsPlanDaysAndDayTypes() throws {
        // Prepare a plan with a day and an exercise, and a matching session item
        let plan = createTestPlan(name: "RoundTrip Plan", kind: .weekly, start: Calendar.current.startOfDay(for: Date()))
        let planDay = try XCTUnwrap(plan.days.first)
        planDay.type = .climbingFull
        
        let activity = createTestActivity(name: "Cat")
        let tt = createTestTrainingType(activity: activity, name: "TT")
        let ex = createTestExercise(trainingType: tt, name: "EX-1")
        planDay.chosenExercises = [ex.name]
        
        // Session on same day with item referencing the plan
        let session = createTestSession(date: planDay.date)
        session.items.append(SessionItem(
            exerciseName: ex.name,
            planSourceId: plan.id,
            planName: plan.name,
            reps: 8,
            sets: 3,
            weightKg: 12.5
        ))
        try context.save()
        
        // Export CSV
        let doc = LogCSV.makeExportCSV(context: context)
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString).csv")
        try doc.csv.data(using: .utf8)?.write(to: tmpURL)
        
        // Import into fresh in-memory store
        let fresh = try ModelContainer(
            for: container.schema,
            configurations: ModelConfiguration(schema: container.schema, isStoredInMemoryOnly: true)
        )
        let freshCtx = ModelContext(fresh)
        
        let inserted = try LogCSV.importCSV(from: tmpURL, into: freshCtx, tag: "test", dedupe: true)
        XCTAssertEqual(inserted, 1, "Should import exactly one exercise item")
        
        // Verify plan reconstructed with day and chosen exercise + day type
        let plans: [Plan] = (try? freshCtx.fetch(FetchDescriptor<Plan>())) ?? []
        XCTAssertEqual(plans.count, 1)
        let importedPlan = try XCTUnwrap(plans.first)
        XCTAssertFalse(importedPlan.days.isEmpty)
        let importedDay = try XCTUnwrap(importedPlan.days.first)
        XCTAssertEqual(importedDay.type, .climbingFull)
        XCTAssertTrue(importedDay.chosenExercises.contains(ex.name))
        
        // Verify session and item
        let sessions: [Session] = (try? freshCtx.fetch(FetchDescriptor<Session>())) ?? []
        XCTAssertEqual(sessions.count, 1)
        let items = sessions.first?.items ?? []
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.exerciseName, ex.name)
        XCTAssertEqual(items.first?.planSourceId, importedPlan.id)
        XCTAssertEqual(items.first?.planName, importedPlan.name)
    }
    
    func testClimbImportUpsert_ByExplicitIdAndTB2StableId() throws {
        // Build CSV rows manually
        let day = "2025-08-28"
        let header = "date,type,exercise_name,climb_type,grade,angle,holdColor,style,attempts,wip,gym,reps,sets,weight_kg,plan_id,plan_name,day_type,notes,climb_id,tb2_uuid"
        
        // 1) With explicit climb_id
        let climbId = UUID()
        let row1 = "\(day),climb,,Boulder,6A,20,Red,Power,3,false,Ostbloc,,,,,,,,\(climbId.uuidString),"
        let row1Update = "\(day),climb,,Boulder,6A+,25,Blue,Power,4,true,Ostbloc,,,,,,,,\(climbId.uuidString),"
        
        // 2) With TB2 uuid and climb_id
        let tb2 = "tb2-uuid-123"
        let climbId2 = UUID()
        let row2 = "\(day),climb,,Boulder,6B,30,Green,Technical,2,false,Ostbloc,,,,,,,,\(climbId2.uuidString),\(tb2)"
        let row2Update = "\(day),climb,,Boulder,6B+,35,Green,Technical,2,false,Ostbloc,,,,,,,,\(climbId2.uuidString),\(tb2)"
        
        func writeCSV(_ rows: [String]) throws -> URL {
            let text = ([header] + rows).joined(separator: "\n")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("climbs-\(UUID().uuidString).csv")
            try text.data(using: .utf8)!.write(to: url)
            return url
        }
        
        // Import first time
        let url1 = try writeCSV([row1, row2])
        var inserted = try LogCSV.importCSV(from: url1, into: context, tag: "t1", dedupe: true)
        XCTAssertEqual(inserted, 2)
        
        // Import updates (should upsert; no new insertions)
        let url2 = try writeCSV([row1Update, row2Update])
        inserted = try LogCSV.importCSV(from: url2, into: context, tag: "t2", dedupe: true)
        XCTAssertEqual(inserted, 0, "Upserts should not count as insertions")
        
        // Verify we have two climbs and they reflect updated values
        let climbs: [ClimbEntry] = (try? context.fetch(FetchDescriptor<ClimbEntry>())) ?? []
        XCTAssertEqual(climbs.count, 2)
        
        // Check explicit-id climb updated
        let c1 = try XCTUnwrap(climbs.first(where: { $0.id == climbId }))
        XCTAssertEqual(c1.grade, "6A+")
        XCTAssertEqual(c1.angleDegrees, 25)
        XCTAssertEqual(c1.isWorkInProgress, true)
        
        // Check TB2-stable id climb updated
        let c2 = try XCTUnwrap(climbs.first(where: { $0.tb2ClimbUUID == tb2 }))
        XCTAssertEqual(c2.grade, "6B+")
        XCTAssertEqual(c2.angleDegrees, 35)
    }
}

