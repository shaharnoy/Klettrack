//
//  ImportExportTests.swift
//  klettrack Tests
//  Created by Shahar Noy on 30.09.25.
//

import XCTest
import SwiftData
import CryptoKit

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
            "date","type","exercise_name","climb_type","grade","angle","holdColor","rope_type","style","attempts","wip","gym","reps","sets","duration","weight_kg","plan_id","plan_name","day_type","notes","climb_id","tb2_uuid"
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
    
    // MARK: - CSV Import Tests
    
    // FIX: Centralized header to avoid duplication & indentation issues
    private let testCSVHeader = "date,type,exercise_name,climb_type,grade,angle,holdColor,rope_type,style,attempts,wip,gym,reps,sets,duration,weight_kg,plan_id,plan_name,day_type,notes,climb_id,tb2_uuid"
    
    
    func testCSVImportBasic() async throws {
        let csvContent = """
    \(testCSVHeader)
    2025-08-23,exercise,Push-ups,,,,,,,,,15,3,0.000,,,,,"Felt good",,
    2025-08-23,exercise,Pull-ups,,,,,,,,,10,3,5.000,,,,,"Challenging",,
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
    2025-08-23,exercise,Squats,,,,,,,,,,20,4,0.000,\(plan.id.uuidString),\(plan.name),,,"Leg day",,
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
    2025-08-23,exercise,Deadlifts,,,,,,,,,5,3,50.000,,,,,"Felt strong",,
    2025-08-23,exercise,Deadlifts,,,,,,,,,5,3,50.000,,,,,"Felt strong",,
    2025-08-23,exercise,Deadlifts,,,,,,,,,5,3,50.000,,,,,"Felt strong",,
    """
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_dedupe.csv")
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let importedCount = try await LogCSV.importCSVAsync(from: tempURL, into: context, tag: "test", dedupe: true)
        XCTAssertLessThanOrEqual(importedCount, 1)
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
            2025-09-01,climb,,boulder,V6,25,red,,Comp,3,false,GymA,,,,,,,,Updated \(Date()),\(climbId.uuidString),\(tb2)
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
            2025-09-02,climb,,boulder,V5,30,blue,,Style,4,false,GymB,,,,,,,,First import,,\(tb2)
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
        2025-09-03,climb,,boulder,V3,15,,,Sesh,1,false,GymC,,,,,,,,Initial,,\(tb2)
        """
        let second = """
        \(testCSVHeader)
        2025-09-03,climb,,boulder,V3,15,,,Sesh,2,false,GymC,,,,,,,,Updated notes,,\(tb2)
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
                2025-09-01,climb,,boulder,V2,10,,,x,1,false,GymD,,,,,,,A,,\(tb2)
                2025-09-01,climb,,boulder,V2,20,,,x,1,false,GymD,,,,,,,B,,\(tb2)
                """
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("tb2_angle.csv")
            try csv.write(to: url, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: url) }

            let inserted = try await LogCSV.importCSVAsync(from: url, into: context, dedupe: true)
            XCTAssertEqual(inserted, 2, "Angle change should produce distinct stable IDs")

            let climbs = try context.fetch(FetchDescriptor<ClimbEntry>())
            XCTAssertEqual(climbs.count, 2)

        }

        func testExportIncludesTB2UUID() throws {
            let day = parseDay("2025-09-01")
            let tb2 = "tb2-delta-333"
            let climb = ClimbEntry(
                climbType: .boulder,
                grade: "V7",
                angleDegrees: 40,
                style: "Dyno",
                attempts: "4",
                isWorkInProgress: false,
                holdColor: .green,
                gym: "GymE",
                notes: "Export test",
                dateLogged: day,
                tb2ClimbUUID: tb2
            )
            context.insert(climb)
            try context.save()

            let doc = LogCSV.makeExportCSV(context: context)
            let lines = doc.csv.split(separator: "\n").map(String.init)
            XCTAssertTrue(lines.first?.hasPrefix("date,type") == true)
            let climbLine = lines.first { $0.contains(tb2) }
            XCTAssertNotNil(climbLine)
            let parts = climbLine!.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            XCTAssertEqual(parts.count, 21)
            XCTAssertEqual(parts.last, tb2)
        }
    }
    
