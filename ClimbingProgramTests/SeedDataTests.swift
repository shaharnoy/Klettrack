//
//  SeedDataTests.swift
//  klettrack Tests
//
//  Created by Shahar Noy on 30.09.25.
//
import XCTest
import SwiftData
@testable import klettrack

final class SeedDataTests: BaseSwiftDataTestCase {
    func testBoulderingCombinationsSeeded() throws {
        SeedData.loadIfNeeded(context)
        let activities: [Activity] = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        let boulder = try XCTUnwrap(activities.first(where: { $0.name == "Bouldering" }))
        let types = boulder.types
        XCTAssertFalse(types.isEmpty)
        // At least one type should have non-empty combinations
        XCTAssertTrue(types.contains { !$0.combinations.isEmpty })
    }
    
    func testSeedClimbingDataAndTimerTemplates() {
        SeedClimbingData.loadIfNeeded(context)
        SeedTimerTemplates.loadIfNeeded(context)
        
        let stylesCount = (try? context.fetchCount(FetchDescriptor<ClimbStyle>())) ?? 0
        let gymsCount = (try? context.fetchCount(FetchDescriptor<ClimbGym>())) ?? 0
        let templatesCount = (try? context.fetchCount(FetchDescriptor<TimerTemplate>())) ?? 0
        
        XCTAssertGreaterThan(stylesCount, 0)
        XCTAssertGreaterThan(gymsCount, 0)
        XCTAssertGreaterThan(templatesCount, 0)
    }
}

