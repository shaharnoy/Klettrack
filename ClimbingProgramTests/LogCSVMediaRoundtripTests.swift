//
//  LogCSVMediaRoundtripTests.swift
//  ClimbingProgram
//
//  Created by Shahar Noy on 14.11.25.
//

import XCTest
import SwiftData
import UIKit
@testable import klettrack

@MainActor
final class LogCSVMediaRoundtripTests: XCTestCase {

    func testExportImportPhotoMediaRoundtrip() async throws {
        // ---------- 1) EXPORT SIDE: create climb + media in a fresh in-memory store ----------
        let exportContainer = try ModelContainer(
            for: ClimbEntry.self, ClimbMedia.self, Session.self, SessionItem.self, Plan.self, PlanKindModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let exportContext = ModelContext(exportContainer)

        // Use a fixed date with full "yyyy-MM-dd HH:mm:ss" precision
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        let fixedDate = df.date(from: "2025-08-23 11:22:11")!

        let climb = ClimbEntry(
            climbType: .boulder,
            grade: "6A",
            angleDegrees: 30,
            style: "Overhang",
            attempts: "1",
            isWorkInProgress: false,
            isPreviouslyClimbed: false,
            holdColor: nil,
            gym: "MediaRoundtripGym",
            notes: "Media roundtrip test",
            dateLogged: fixedDate
        )
        exportContext.insert(climb)

        let assetId = "FAKE-ASSET-ID-123"

        // Small dummy thumbnail so thumbnailData is non-nil on export
        let thumbImage = UIImage(systemName: "photo")!
        let thumbData = thumbImage.pngData()

        let media = ClimbMedia(
            assetLocalIdentifier: assetId,
            thumbnailData: thumbData,
            type: .photo,
            createdAt: fixedDate,
            climb: climb
        )
        exportContext.insert(media)

        try exportContext.save()

        // Export to CSV
        let exportDoc = LogCSV.makeExportCSV(context: exportContext)
        let csvContent = exportDoc.csv

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("media_roundtrip_test.csv")
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // ---------- 2) IMPORT SIDE: new empty store, import CSV there ----------
        let importContainer = try ModelContainer(
            for: ClimbEntry.self, ClimbMedia.self, Session.self, SessionItem.self, Plan.self, PlanKindModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let importContext = ModelContext(importContainer)

        let importedCount = try await LogCSV.importCSVAsync(
            from: tempURL,
            into: importContext,
            tag: "test-media-roundtrip",
            dedupe: false
        )
        XCTAssertEqual(importedCount, 1, "Import should create one climb row in a fresh store")

        // ---------- 3) Verify the imported climb + media ----------
        let allClimbsAfter = try importContext.fetch(FetchDescriptor<ClimbEntry>())
        XCTAssertEqual(allClimbsAfter.count, 1, "There should be exactly one climb after import")

        guard let importedClimb = allClimbsAfter.first else {
            XCTFail("Imported climb should exist")
            return
        }

        XCTAssertEqual(importedClimb.gym, "MediaRoundtripGym")
        XCTAssertEqual(importedClimb.notes, "Media roundtrip test")

        let climbMedia = importedClimb.media
        XCTAssertEqual(climbMedia.count, 1, "Imported climb should have one media entry")

        guard let importedMedia = climbMedia.first else {
            XCTFail("Imported climb should have at least one media entry")
            return
        }

        XCTAssertEqual(importedMedia.assetLocalIdentifier, assetId)
        XCTAssertEqual(importedMedia.type, .photo)
    }
}
