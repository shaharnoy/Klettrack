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

    // MARK: - Exercise shape
    //
    // The seed table *is* the classification, so these assertions are the only thing
    // standing between a mis-typed name and a resistance field on a limit boulder.

    private func shape(of name: String) throws -> ExerciseShape {
        let all: [Exercise] = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let match = try XCTUnwrap(
            all.first(where: { $0.name == name }),
            "No seeded exercise named \(name) — did the catalog rename it?"
        )
        return match.shape
    }

    func testWallWorkIsClassifiedAsAttempts() throws {
        SeedData.loadIfNeeded(context)

        for name in [
            "Work on 1–3 limit boulders",
            "3–6 near-maximal boulders",
            "Classic 4×4",
            "Board 3×6",
            "V5–V6",
            "One Touch",
            // Filed under Climbing-Specific, so only the name table can reach these.
            "Bouldering",
            "Boulder Campusing",
            "Big-Move Boulder Problems",
        ] {
            XCTAssertEqual(try shape(of: name), .attempts, "\(name) should be attempts-based")
        }
    }

    func testBodyweightExercisesTakeNoLoad() throws {
        SeedData.loadIfNeeded(context)

        for name in ["Push-Up", "Butterfly Stretch", "Front Lever", "Frenchies", "Band T"] {
            XCTAssertEqual(try shape(of: name), .bodyweight, "\(name) should be bodyweight")
            XCTAssertFalse(try shape(of: name).takesLoad)
        }
    }

    func testLoadedExercisesKeepTheWeightField() throws {
        SeedData.loadIfNeeded(context)

        for name in [
            "Weighted Pull-Ups",
            "Barbell Deadlift",
            "FB Max-Weight Hangs (10s, 14–20mm)",
            "Short-Duration Fingerboard Repeaters",
        ] {
            XCTAssertEqual(try shape(of: name), .weighted, "\(name) should be weighted")
            XCTAssertTrue(try shape(of: name).takesLoad)
        }
    }

    /// The structural rule, not the name table: guards against a future drill being
    /// seeded under Bouldering and silently defaulting to weighted.
    func testEverythingFiledUnderBoulderingIsAttempts() throws {
        SeedData.loadIfNeeded(context)

        let activities: [Activity] = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        let boulder = try XCTUnwrap(activities.first(where: { $0.name == "Bouldering" }))

        let filed = boulder.types.flatMap { type in
            type.exercises + type.combinations.flatMap(\.exercises)
        }
        XCTAssertFalse(filed.isEmpty, "Expected the Bouldering activity to hold exercises")

        for ex in filed {
            XCTAssertEqual(ex.shape, .attempts, "\(ex.name) is filed under Bouldering")
        }
    }

    func testReseedingIsIdempotent() throws {
        SeedData.loadIfNeeded(context)
        let firstCount = (try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0

        SeedData.loadIfNeeded(context)

        XCTAssertEqual((try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0, firstCount)
        XCTAssertEqual(try shape(of: "Push-Up"), .bodyweight)
        XCTAssertEqual(try shape(of: "Classic 4×4"), .attempts)
    }

    /// The structural rule fills blanks only. A user who files their own exercise under
    /// Bouldering and calls it weighted keeps that on the next launch.
    func testAUserOverrideUnderBoulderingSurvivesAReseed() throws {
        SeedData.loadIfNeeded(context)

        let activities: [Activity] = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        let boulder = try XCTUnwrap(activities.first(where: { $0.name == "Bouldering" }))
        let type = try XCTUnwrap(boulder.types.first)

        let mine = Exercise(name: "Weighted board laps", shapeKey: ExerciseShape.weighted.rawValue)
        type.exercises.append(mine)
        try context.save()

        SeedData.loadIfNeeded(context)

        XCTAssertEqual(mine.shape, .weighted, "A user's own classification must not be reset")
    }

    /// An exercise nobody classified behaves exactly as it did before the field existed.
    func testAnUnclassifiedExerciseDefaultsToWeighted() throws {
        let orphan = Exercise(name: "Something I invented")
        context.insert(orphan)
        try context.save()

        XCTAssertNil(orphan.shapeKey)
        XCTAssertEqual(orphan.shape, .weighted)
        XCTAssertTrue(orphan.shape.takesLoad)
    }
}

