//
//  LastLoggedWeightTests.swift
//  klettrack Tests
//

import XCTest
import SwiftData
@testable import klettrack

final class LastLoggedWeightTests: ClimbingProgramTestSuite {

    private func log(
        _ name: String,
        on date: Date,
        weightKg: Double? = nil,
        loggedSets: [LoggedSet] = [],
        sort: Int = 0
    ) throws {
        let session = findOrCreateSession(for: date, in: context)
        let item = SessionItem(exerciseName: name, weightKg: weightKg, loggedSets: loggedSets)
        item.sort = sort
        session.items.append(item)
        try context.save()
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date())!
    }

    func testReturnsNilWhenTheExerciseHasNeverBeenLogged() {
        XCTAssertNil(lastLoggedWeight(for: "Weighted Pull-up", in: context))
    }

    func testPrefersTheMostRecentSession() throws {
        try log("Weighted Pull-up", on: day(-14), weightKg: 20)
        try log("Weighted Pull-up", on: day(-2), weightKg: 30)
        try log("Weighted Pull-up", on: day(-7), weightKg: 25)

        XCTAssertEqual(lastLoggedWeight(for: "Weighted Pull-up", in: context), 30)
    }

    func testIgnoresOtherExercises() throws {
        try log("Front Lever", on: day(-1), weightKg: 99)
        try log("Weighted Pull-up", on: day(-5), weightKg: 30)

        XCTAssertEqual(lastLoggedWeight(for: "Weighted Pull-up", in: context), 30)
    }

    /// A bodyweight day must not shadow the last weighted day — it carries no
    /// weight at all, so the search has to keep walking back.
    func testSkipsPastItemsThatCarryNoWeight() throws {
        try log("Pull-up", on: day(-10), weightKg: 15)
        try log("Pull-up", on: day(-1), weightKg: nil)

        XCTAssertEqual(lastLoggedWeight(for: "Pull-up", in: context), 15)
    }

    /// The label says "Last", so a ramp must seed from the weight you finished on,
    /// not the mean the rollup stores.
    func testUsesTheFinalSetWhenPerSetDetailExists() throws {
        try log(
            "Weighted Pull-up",
            on: day(-1),
            weightKg: 26.25,
            loggedSets: [
                LoggedSet(reps: 3, weightKg: 20),
                LoggedSet(reps: 3, weightKg: 25),
                LoggedSet(reps: 3, weightKg: 30),
                LoggedSet(reps: 3, weightKg: 30)
            ]
        )

        XCTAssertEqual(
            lastLoggedWeight(for: "Weighted Pull-up", in: context), 30,
            "The ramp finished at 30, and the rollup mean of 26.25 is a poor place to start"
        )
    }

    /// Two items for the same exercise on one day: the later one is the correction.
    func testWithinADayTheLaterItemWins() throws {
        let date = day(-1)
        try log("Weighted Pull-up", on: date, weightKg: 20, sort: 0)
        try log("Weighted Pull-up", on: date, weightKg: 35, sort: 1)

        XCTAssertEqual(lastLoggedWeight(for: "Weighted Pull-up", in: context), 35)
    }

    // MARK: - exerciseShape(named:in:)

    private func catalog(_ name: String, shape: ExerciseShape?) throws {
        let ex = Exercise(name: name, shapeKey: shape?.rawValue)
        context.insert(ex)
        try context.save()
    }

    func testReadsTheStoredShape() throws {
        try catalog("Limit boulders", shape: .attempts)
        try catalog("Push-Up", shape: .bodyweight)
        try catalog("Weighted Pull-up", shape: .weighted)

        XCTAssertEqual(exerciseShape(named: "Limit boulders", in: context), .attempts)
        XCTAssertEqual(exerciseShape(named: "Push-Up", in: context), .bodyweight)
        XCTAssertEqual(exerciseShape(named: "Weighted Pull-up", in: context), .weighted)
    }

    /// A logged item can name an exercise the catalog has never heard of — imported,
    /// renamed, or since deleted. Keeping the field is the safe failure.
    func testUnknownNamesKeepTheWeightField() {
        XCTAssertEqual(exerciseShape(named: "Never seen this", in: context), .weighted)
        XCTAssertTrue(exerciseShape(named: "Never seen this", in: context).takesLoad)
    }

    func testAnUnclassifiedCatalogEntryReadsAsWeighted() throws {
        try catalog("Legacy entry", shape: nil)

        XCTAssertEqual(exerciseShape(named: "Legacy entry", in: context), .weighted)
    }
}
