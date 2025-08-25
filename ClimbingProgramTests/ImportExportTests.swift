//
//  ImportExportTests.swift
//  ClimbingProgram Tests
//
//  Created by AI Assistant on 23.08.25.
//

import XCTest
import SwiftData
@testable import ClimbingProgram

/**
 * Import/Export Tests
 * 
 * Tests CSV import/export functionality and data consistency
 */

class ImportExportTests: ClimbingProgramTestSuite {
    
    // MARK: - CSV Export Tests
    
    func testCSVExportStructure() {
        // Create test data
        let plan = createTestPlan()
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
        let expectedFields = ["date", "exercise", "reps", "sets", "weight_kg", "plan_id", "plan_name","day_type", "notes"]
        for field in expectedFields {
            XCTAssertTrue(header.contains(field), "Header should contain \(field)")
        }
        
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
    
    // MARK: - CSV Import Tests
    
    func testCSVImportBasic() throws {
        let csvContent = """
        date,exercise,reps,sets,weight_kg,plan_id,plan_name,notes
        2025-08-23,Push-ups,15,3,0.000,,,"Good form"
        2025-08-23,Pull-ups,8,3,10.000,,,"Challenging"
        """
        
        // Create temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_import.csv")
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        // Import CSV
        let importedCount = try LogCSV.importCSV(from: tempURL, into: context, tag: "test", dedupe: false)
        
        XCTAssertEqual(importedCount, 2, "Should import 2 items")
        
        // Verify imported data
        let sessionDescriptor = FetchDescriptor<Session>()
        let sessions = (try? context.fetch(sessionDescriptor)) ?? []
        XCTAssertEqual(sessions.count, 1, "Should create one session")
        
        let session = sessions.first!
        XCTAssertEqual(session.items.count, 2, "Session should have 2 items")
        
        let exercises = Set(session.items.map { $0.exerciseName })
        XCTAssertTrue(exercises.contains("Push-ups"))
        XCTAssertTrue(exercises.contains("Pull-ups"))
    }
    
    func testCSVImportWithPlanData() throws {
        // Create a plan first
        let plan = createTestPlan()
        try? context.save()
        
        let csvContent = """
        date,exercise,reps,sets,weight_kg,plan_id,plan_name,notes
        2025-08-23,Plank,1,3,0.000,\(plan.id.uuidString),\(plan.name),"From plan"
        """
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_plan_import.csv")
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let importedCount = try LogCSV.importCSV(from: tempURL, into: context, tag: "test", dedupe: false)
        
        XCTAssertEqual(importedCount, 1)
        
        // Verify plan linking
        let itemDescriptor = FetchDescriptor<SessionItem>()
        let items = (try? context.fetch(itemDescriptor)) ?? []
        let importedItem = items.first!
        
        XCTAssertEqual(importedItem.planSourceId, plan.id)
        XCTAssertEqual(importedItem.planName, plan.name)
    }
    
    func testCSVImportDeduplication() throws {
        let csvContent = """
        date,exercise,reps,sets,weight_kg,plan_id,plan_name,notes
        2025-08-23,Push-ups,15,3,0.000,,,"First entry"
        2025-08-23,Push-ups,15,3,0.000,,,"Duplicate entry"
        """
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_dedupe.csv")
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        // Import with deduplication enabled
        let importedCount = try LogCSV.importCSV(from: tempURL, into: context, tag: "test", dedupe: true)
        
        // Should only import unique entries
        XCTAssertLessThanOrEqual(importedCount, 1, "Deduplication should prevent duplicates")
        
        let itemDescriptor = FetchDescriptor<SessionItem>()
        let items = (try? context.fetch(itemDescriptor)) ?? []
        XCTAssertLessThanOrEqual(items.count, 1, "Should not create duplicate items")
    }
    
    func testCSVImportAsync() async throws {
        let csvContent = """
        date,exercise,reps,sets,weight_kg,plan_id,plan_name,notes
        2025-08-23,Exercise1,10,3,0.000,,,"Test1"
        2025-08-24,Exercise2,12,3,5.000,,,"Test2"
        2025-08-25,Exercise3,8,4,10.000,,,"Test3"
        """
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_async.csv")
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        var progressUpdates: [Double] = []
        
        let importedCount = try await LogCSV.importCSVAsync(
            from: tempURL,
            into: context,
            tag: "async-test",
            dedupe: false,
            progress: { progress in
                progressUpdates.append(progress)
            }
        )
        
        XCTAssertEqual(importedCount, 3)
        XCTAssertFalse(progressUpdates.isEmpty, "Should report progress")
        XCTAssertEqual(progressUpdates.last, 1.0, "Final progress should be 100%")
    }
    
    // MARK: - Round-trip Tests
    
    func testExportImportRoundTrip() throws {
        // Create original data
        let plan = createTestPlan()
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
        let importedCount = try LogCSV.importCSV(from: tempURL, into: context, tag: "roundtrip", dedupe: false)
        
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
    
    // MARK: - Error Handling Tests
    
    func testCSVImportInvalidFormat() {
        let invalidCSV = "This is not a valid CSV file"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("invalid.csv")
        
        do {
            try invalidCSV.write(to: tempURL, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            
            XCTAssertThrowsError(try LogCSV.importCSV(from: tempURL, into: context, tag: "invalid", dedupe: false)) {
                error in
                // Should throw an appropriate error
                XCTAssertNotNil(error)
            }
        } catch {
            XCTFail("Setup failed: \(error)")
        }
    }
    
    func testCSVImportMissingFile() {
        let nonExistentURL = FileManager.default.temporaryDirectory.appendingPathComponent("missing.csv")
        
        XCTAssertThrowsError(try LogCSV.importCSV(from: nonExistentURL, into: context, tag: "missing", dedupe: false)) {
            error in
            // Should throw file not found error
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Data Integrity Tests
    
    func testDateConsistencyInExportImport() throws {
        let specificDate = DateComponents(calendar: Calendar.current, year: 2025, month: 12, day: 25).date!
        let session = Session(date: specificDate)
        context.insert(session)
        
        let item = SessionItem(exerciseName: "Christmas Workout")
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
        
        _ = try LogCSV.importCSV(from: tempURL, into: context, tag: "date-test", dedupe: false)
        
        // Verify date consistency
        let importedSessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        let importedSession = importedSessions.first!
        
        let calendar = Calendar.current
        XCTAssertEqual(calendar.startOfDay(for: importedSession.date), 
                      calendar.startOfDay(for: specificDate),
                      "Date should be preserved through export/import")
    }
}
