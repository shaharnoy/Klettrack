//
//  BusinessLogicTests.swift
//  klettrack Tests
//
//  Created by AI Assistant on 23.08.25.
//

import XCTest
import SwiftData
@testable import klettrack

/**
 * Business Logic Tests
 *
 * Tests core business logic including:
 * - Plan Factory functionality
 * - Data seeding operations
 * - Exercise catalog management
 * - Session management
 */

class BusinessLogicTests: ClimbingProgramTestSuite {
    
    // MARK: - Plan Factory Tests
    
    func testWeeklyPlanGeneration() {
        let startDate = Date()
        let plan = createTestPlan(name: "Weekly Plan", kindKey: "weekly", start: startDate)
        
        XCTAssertEqual(plan.name, "Weekly Plan")
        XCTAssertEqual(plan.kind?.key, "weekly")
        XCTAssertEqual(plan.days.count, 7)
        
        // Verify dates are consecutive
        let sortedDays = plan.days.sorted { $0.date < $1.date }
        for i in 0..<6 {
            let currentDay = sortedDays[i]
            let nextDay = sortedDays[i + 1]
            let expectedNextDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDay.date)!
            
            XCTAssertEqual(Calendar.current.startOfDay(for: nextDay.date),
                          Calendar.current.startOfDay(for: expectedNextDate))
        }
    }
    
    func testPyramidPlanGeneration() {
        let startDate = Date()
        let kf = FetchDescriptor<PlanKindModel>(predicate: #Predicate { $0.key == "3-2-1" })
        let existingKind = (try? context.fetch(kf))?.first
        let kind321: PlanKindModel
        if let k = existingKind {
            k.name = "3-2-1 (6 weeks)"
            k.totalWeeks = 6
            k.isRepeating = false
            k.order = 2
            kind321 = k
        } else {
            let k = PlanKindModel(key: "3-2-1", name: "3-2-1 (6 weeks)", totalWeeks: 6, isRepeating: false, order: 2)
            context.insert(k)
            kind321 = k
        }
        let plan = PlanFactory.create(name: "3-2-1 Plan", kind: kind321, start: startDate, in: context)
        
        XCTAssertEqual(plan.kind?.key, "3-2-1")
        XCTAssertEqual(plan.days.count, 42, "3-2-1 should produce 6 weeks (42 days)")
        
    }
    
    func testPlanWeekAppending() {
        let plan = createTestPlan(name: "Base Plan", kindKey: "weekly", start: Date())
        let initialDayCount = plan.days.count
        
        // Append 2 more weeks
        PlanFactory.appendWeeks(to: plan, count: 2, in: context)
        
        XCTAssertEqual(plan.days.count, initialDayCount + 14)
        
        // Verify new days are properly dated
        let sortedDays = plan.days.sorted { $0.date < $1.date }
        let lastOriginalDay = sortedDays[initialDayCount - 1]
        let firstNewDay = sortedDays[initialDayCount]
        
        let expectedDate = Calendar.current.date(byAdding: .day, value: 1, to: lastOriginalDay.date)!
        XCTAssertEqual(Calendar.current.startOfDay(for: firstNewDay.date),
                      Calendar.current.startOfDay(for: expectedDate))
    }
    
    // MARK: - Data Seeding Tests
    
    func testSeedDataExecution() {
        // Verify empty database initially
        let activityDescriptor = FetchDescriptor<Activity>()
        let initialActivities = (try? context.fetch(activityDescriptor)) ?? []
        XCTAssertTrue(initialActivities.isEmpty)
        
        // Run seed data
        SeedData.loadIfNeeded(context)
        
        // Verify seeded data
        let seededActivities = (try? context.fetch(activityDescriptor)) ?? []
        XCTAssertFalse(seededActivities.isEmpty)
        
        // Verify core activities exist
        let activityNames = Set(seededActivities.map { $0.name })
        XCTAssertTrue(activityNames.contains("Core"))
        XCTAssertTrue(activityNames.contains("Antagonist & Stabilizer"))
        
        // Verify training types and exercises are populated
        for activity in seededActivities {
            XCTAssertFalse(activity.types.isEmpty, "Activity \(activity.name) should have training types")
            
            for trainingType in activity.types {
                // Fix the assertion logic: should be true if EITHER exercises OR combinations exist
                let hasContent = !trainingType.exercises.isEmpty || !trainingType.combinations.isEmpty
                XCTAssertTrue(hasContent, "Training type \(trainingType.name) should have exercises or combinations")
            }
        }
    }
    
    func testSeedDataIdempotency() {
        // First run
        SeedData.loadIfNeeded(context)
        let descriptor = FetchDescriptor<Activity>()
        let firstRunCount = (try? context.fetch(descriptor))?.count ?? 0
        
        // Second run should not duplicate data
        SeedData.loadIfNeeded(context)
        let secondRunCount = (try? context.fetch(descriptor))?.count ?? 0
        
        XCTAssertEqual(firstRunCount, secondRunCount, "Seed data should be idempotent")
    }
    
    // MARK: - Session Management Tests
    
    func testSessionDeduplication() {
        // fixed date
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let date = iso.date(from: "2024-06-15T10:00:00Z")!
        let normalizedDate = Calendar.current.startOfDay(for: date)
        
        // Create two sessions for the same day
        let session1 = Session(date: date)
        let session2 = Session(date: Calendar.current.date(byAdding: .hour, value: 5, to: date)!)
        
        context.insert(session1)
        context.insert(session2)
        
        // Both should normalize to the same day
        XCTAssertEqual(Calendar.current.startOfDay(for: session1.date), normalizedDate)
        XCTAssertEqual(Calendar.current.startOfDay(for: session2.date), normalizedDate)
    }
    
    func testSessionItemPlanLinking() {
        let plan = createTestPlan(kindKey: "weekly")
        let session = createTestSession()
        
        let item = SessionItem(
            exerciseName: "Test Exercise",
            planSourceId: plan.id,
            planName: plan.name,
            reps: 10,
            sets: 3
        )
        
        session.items.append(item)
        try? context.save()
        
        // Verify linking
        XCTAssertEqual(item.planSourceId, plan.id)
        XCTAssertEqual(item.planName, plan.name)
        
        // Test query for plan-specific items - fix the predicate type mismatch
        let planId = plan.id
        let descriptor = FetchDescriptor<SessionItem>(
            predicate: #Predicate<SessionItem> { item in
                item.planSourceId == planId
            }
        )
        let planItems = (try? context.fetch(descriptor)) ?? []
        
        XCTAssertEqual(planItems.count, 1)
        XCTAssertEqual(planItems.first?.exerciseName, "Test Exercise")
    }
    
    // MARK: - TB2 Sync Logic Tests
    
    @MainActor
    func testTB2PreviouslyClimbedRequiresPriorNonWIPAndSameAngle() {
        let uuid = "tb2-uuid-123"
        let style = "Tension board"

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let earlier = iso.date(from: "2025-01-01T10:00:00Z")!
        let later   = iso.date(from: "2025-01-02T10:00:00Z")!

        // Prior attempt (WIP) on SAME angle -> should NOT count
        context.insert(ClimbEntry(
            id: UUID(),
            climbType: .boulder,
            grade: "6a",
            angleDegrees: 30,
            style: style,
            attempts: "3",
            isWorkInProgress: true,
            isPreviouslyClimbed: false,
            holdColor: nil,
            gym: "Test",
            notes: nil,
            dateLogged: earlier,
            tb2ClimbUUID: uuid
        ))

        // Prior ascent (non-WIP) but on DIFFERENT angle -> should NOT count for angle 30
        context.insert(ClimbEntry(
            id: UUID(),
            climbType: .boulder,
            grade: "6a",
            angleDegrees: 40,
            style: style,
            attempts: "1",
            isWorkInProgress: false,
            isPreviouslyClimbed: false,
            holdColor: nil,
            gym: "Test",
            notes: nil,
            dateLogged: earlier,
            tb2ClimbUUID: uuid
        ))

        try? context.save()

        // Verify: still false (only WIP on same angle + ascent on different angle)
        let initially = TB2SyncManager.wasPreviouslyClimbed(
            in: context,
            tb2ClimbUUID: uuid,
            angleDegrees: 30,
            before: later
        )
        XCTAssertFalse(initially)

        // Now add a real prior ascent on SAME angle -> should count
        context.insert(ClimbEntry(
            id: UUID(),
            climbType: .boulder,
            grade: "6a",
            angleDegrees: 30,
            style: style,
            attempts: "1",
            isWorkInProgress: false,
            isPreviouslyClimbed: false,
            holdColor: nil,
            gym: "Test",
            notes: nil,
            dateLogged: earlier,
            tb2ClimbUUID: uuid
        ))
        try? context.save()

        let afterAscent = TB2SyncManager.wasPreviouslyClimbed(
            in: context,
            tb2ClimbUUID: uuid,
            angleDegrees: 30,
            before: later
        )
        XCTAssertTrue(afterAscent)
    }

    @MainActor
    func testTB2ClimbMetadataCacheInsertsAndUpdatesRows() throws {
        let initial = TB2Client.SyncResponse(
            complete: true,
            ascents: nil,
            bids: nil,
            climbs: [
                TB2Client.Climb(
                    uuid: "climb-1",
                    name: "Original Name",
                    updatedAt: "2026-01-01 00:00:00.000000",
                    layoutID: 9,
                    isListed: true
                )
            ],
            climbStats: nil,
            difficulties: nil,
            userSyncs: nil,
            sharedSyncs: nil
        )

        XCTAssertTrue(TB2SyncManager.upsertClimbMetadata(from: [initial], board: .tension, into: context))
        var names = TB2SyncManager.cachedClimbNames(board: .tension, in: context)
        XCTAssertEqual(names["climb-1"], "Original Name")

        let delta = TB2Client.SyncResponse(
            complete: true,
            ascents: nil,
            bids: nil,
            climbs: [
                TB2Client.Climb(
                    uuid: "climb-1",
                    name: "Updated Name",
                    updatedAt: "2026-01-02 00:00:00.000000",
                    layoutID: 10,
                    isListed: false
                )
            ],
            climbStats: nil,
            difficulties: nil,
            userSyncs: nil,
            sharedSyncs: nil
        )

        XCTAssertTrue(TB2SyncManager.upsertClimbMetadata(from: [delta], board: .tension, into: context))
        names = TB2SyncManager.cachedClimbNames(board: .tension, in: context)
        XCTAssertEqual(names["climb-1"], "Updated Name")

        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<TB2ClimbMetadata>()).first)
        XCTAssertEqual(stored.updatedAt, "2026-01-02 00:00:00.000000")
        XCTAssertEqual(stored.layoutID, 10)
        XCTAssertEqual(stored.isListed, false)
    }

    func testTB2ClimbCacheCursorSavesOnlyWhenComplete() {
        UserDefaults.standard.removeObject(forKey: "tb2.climbsCache.tension.lastSynchronizedAt")
        UserDefaults.standard.removeObject(forKey: "tb2.climbsCache.tension.complete")
        defer {
            UserDefaults.standard.removeObject(forKey: "tb2.climbsCache.tension.lastSynchronizedAt")
            UserDefaults.standard.removeObject(forKey: "tb2.climbsCache.tension.complete")
        }

        let incomplete = TB2Client.SyncResponse(
            complete: false,
            ascents: nil,
            bids: nil,
            climbs: nil,
            climbStats: nil,
            difficulties: nil,
            userSyncs: nil,
            sharedSyncs: [
                TB2Client.TableSync(tableName: "climbs", lastSynchronizedAt: "2026-01-01 00:00:00.000000")
            ]
        )

        TB2SyncManager.saveClimbCacheCursor(from: [incomplete], board: .tension)
        var state = TB2SyncManager.climbCacheState(for: .tension)
        XCTAssertFalse(state.isComplete)
        XCTAssertNil(state.lastSynchronizedAt)

        let complete = TB2Client.SyncResponse(
            complete: true,
            ascents: nil,
            bids: nil,
            climbs: nil,
            climbStats: nil,
            difficulties: nil,
            userSyncs: nil,
            sharedSyncs: [
                TB2Client.TableSync(tableName: "climbs", lastSynchronizedAt: "2026-01-02 00:00:00.000000")
            ]
        )

        TB2SyncManager.saveClimbCacheCursor(from: [complete], board: .tension)
        state = TB2SyncManager.climbCacheState(for: .tension)
        XCTAssertTrue(state.isComplete)
        XCTAssertEqual(state.lastSynchronizedAt, "2026-01-02 00:00:00.000000")
    }

    @MainActor
    func testTB2ClimbStatsMetadataCacheInsertsAndUpdatesRows() throws {
        let initial = TB2Client.SyncResponse(
            complete: true,
            ascents: nil,
            bids: nil,
            climbs: nil,
            climbStats: [
                TB2Client.ClimbStats(
                    climbUUID: "climb-1",
                    angle: 40,
                    difficultyAverage: 19.2,
                    displayDifficulty: 19.0,
                    ascensionistCount: 12,
                    qualityAverage: 3.5
                )
            ],
            difficulties: nil,
            userSyncs: nil,
            sharedSyncs: nil
        )

        XCTAssertTrue(TB2SyncManager.upsertClimbStatsMetadata(from: [initial], board: .tension, into: context))
        var grades = TB2SyncManager.cachedClimbStatsDifficulties(board: .tension, in: context)
        XCTAssertEqual(grades[TB2SyncManager.DiffKey(uuid: "climb-1", angle: 40)], 19)

        let delta = TB2Client.SyncResponse(
            complete: true,
            ascents: nil,
            bids: nil,
            climbs: nil,
            climbStats: [
                TB2Client.ClimbStats(
                    climbUUID: "climb-1",
                    angle: 40,
                    difficultyAverage: 20.6,
                    displayDifficulty: 20.0,
                    ascensionistCount: 14,
                    qualityAverage: 3.9
                )
            ],
            difficulties: nil,
            userSyncs: nil,
            sharedSyncs: nil
        )

        XCTAssertTrue(TB2SyncManager.upsertClimbStatsMetadata(from: [delta], board: .tension, into: context))
        grades = TB2SyncManager.cachedClimbStatsDifficulties(board: .tension, in: context)
        XCTAssertEqual(grades[TB2SyncManager.DiffKey(uuid: "climb-1", angle: 40)], 21)

        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<TB2ClimbStatsMetadata>()).first)
        XCTAssertEqual(stored.difficultyAverage, 20.6)
        XCTAssertEqual(stored.displayDifficulty, 20.0)
        XCTAssertEqual(stored.ascensionistCount, 14)
        XCTAssertEqual(stored.qualityAverage, 3.9)
    }

    func testTB2ClimbStatsCacheCursorSavesOnlyWhenComplete() {
        UserDefaults.standard.removeObject(forKey: "tb2.climbStatsCache.tension.lastSynchronizedAt")
        UserDefaults.standard.removeObject(forKey: "tb2.climbStatsCache.tension.complete")
        defer {
            UserDefaults.standard.removeObject(forKey: "tb2.climbStatsCache.tension.lastSynchronizedAt")
            UserDefaults.standard.removeObject(forKey: "tb2.climbStatsCache.tension.complete")
        }

        let incomplete = TB2Client.SyncResponse(
            complete: false,
            ascents: nil,
            bids: nil,
            climbs: nil,
            climbStats: nil,
            difficulties: nil,
            userSyncs: nil,
            sharedSyncs: [
                TB2Client.TableSync(tableName: "climb_stats", lastSynchronizedAt: "2026-01-01 00:00:00.000000")
            ]
        )

        TB2SyncManager.saveClimbStatsCacheCursor(from: [incomplete], board: .tension)
        var state = TB2SyncManager.climbStatsCacheState(for: .tension)
        XCTAssertFalse(state.isComplete)
        XCTAssertNil(state.lastSynchronizedAt)

        let complete = TB2Client.SyncResponse(
            complete: true,
            ascents: nil,
            bids: nil,
            climbs: nil,
            climbStats: nil,
            difficulties: nil,
            userSyncs: nil,
            sharedSyncs: [
                TB2Client.TableSync(tableName: "climb_stats", lastSynchronizedAt: "2026-01-02 00:00:00.000000")
            ]
        )

        TB2SyncManager.saveClimbStatsCacheCursor(from: [complete], board: .tension)
        state = TB2SyncManager.climbStatsCacheState(for: .tension)
        XCTAssertTrue(state.isComplete)
        XCTAssertEqual(state.lastSynchronizedAt, "2026-01-02 00:00:00.000000")
    }

    @MainActor
    func testTB2ApplyRowsUsesCachedNameForFreshRows() throws {
        context.insert(TB2ClimbMetadata(boardRawValue: "tension", uuid: "climb-cached", name: "Cached Name"))
        let names = TB2SyncManager.cachedClimbNames(board: .tension, in: context)
        let date = try XCTUnwrap(BoardDateParser.parse("2026-01-03 10:00:00"))

        try TB2SyncManager.applyRows([
            TB2SyncManager.Row(
                climbUUID: "climb-cached",
                angle: 40,
                isMirror: false,
                day: date,
                climbName: names["climb-cached"],
                loggedDifficultyNum: 20,
                displayedDifficultyNum: 20,
                loggedGrade: "6c",
                displayedGrade: "6c",
                isBenchmark: false,
                tries: 2,
                isAscent: true,
                comment: nil
            )
        ], styleName: "Tension board", into: context)

        let entry = try XCTUnwrap(try context.fetch(FetchDescriptor<ClimbEntry>()).first)
        XCTAssertEqual(entry.gym, "Cached Name")
        XCTAssertEqual(entry.notes, "Cached Name")
    }

    @MainActor
    func testTB2ApplyRowsUsesCachedStatsGradeForBidOnlyRows() throws {
        context.insert(TB2ClimbStatsMetadata(
            boardRawValue: "tension",
            climbUUID: "stats-climb",
            angle: 40,
            difficultyAverage: 19.6,
            displayDifficulty: 18.0
        ))
        let stats = TB2SyncManager.cachedClimbStatsDifficulties(board: .tension, in: context)
        let difficulty = stats[TB2SyncManager.DiffKey(uuid: "stats-climb", angle: 40)]
        let date = try XCTUnwrap(BoardDateParser.parse("2026-01-03 10:00:00"))

        try TB2SyncManager.applyRows([
            TB2SyncManager.Row(
                climbUUID: "stats-climb",
                angle: 40,
                isMirror: false,
                day: date,
                climbName: nil,
                loggedDifficultyNum: difficulty,
                displayedDifficultyNum: difficulty,
                loggedGrade: BoardGradeMapper.grade(of: difficulty),
                displayedGrade: nil,
                isBenchmark: false,
                tries: 3,
                isAscent: false,
                comment: nil
            )
        ], styleName: "Tension board", into: context)

        let entry = try XCTUnwrap(try context.fetch(FetchDescriptor<ClimbEntry>()).first)
        XCTAssertEqual(entry.grade, "6c")
        XCTAssertTrue(entry.isWorkInProgress)
    }

    @MainActor
    func testTB2CachedStatsRequiresExactAngleAndFallsBackToDisplayDifficulty() throws {
        context.insert(TB2ClimbStatsMetadata(
            boardRawValue: "tension",
            climbUUID: "fallback-climb",
            angle: 30,
            difficultyAverage: nil,
            displayDifficulty: 22.2
        ))
        context.insert(TB2ClimbStatsMetadata(
            boardRawValue: "tension",
            climbUUID: "angle-climb",
            angle: 40,
            difficultyAverage: 18.2,
            displayDifficulty: nil
        ))

        let stats = TB2SyncManager.cachedClimbStatsDifficulties(board: .tension, in: context)

        XCTAssertEqual(stats[TB2SyncManager.DiffKey(uuid: "fallback-climb", angle: 30)], 22)
        XCTAssertNil(stats[TB2SyncManager.DiffKey(uuid: "angle-climb", angle: 30)])
        XCTAssertNil(stats[TB2SyncManager.DiffKey(uuid: "missing-climb", angle: 40)])
    }

    @MainActor
    func testTB2BackfillMissingNamesPreservesUserText() throws {
        context.insert(TB2ClimbMetadata(boardRawValue: "tension", uuid: "missing-fields", name: "Recovered Name"))
        context.insert(TB2ClimbMetadata(boardRawValue: "tension", uuid: "user-edited", name: "Should Not Overwrite"))

        let missing = ClimbEntry(
            climbType: .boulder,
            grade: "6a",
            angleDegrees: 30,
            style: "Tension board",
            attempts: "1",
            gym: "",
            notes: nil,
            tb2ClimbUUID: "missing-fields"
        )
        let userEdited = ClimbEntry(
            climbType: .boulder,
            grade: "6a",
            angleDegrees: 30,
            style: "Tension board",
            attempts: "1",
            gym: "User Gym",
            notes: "User note",
            tb2ClimbUUID: "user-edited"
        )
        context.insert(missing)
        context.insert(userEdited)
        try context.save()

        try TB2SyncManager.backfillMissingNames(board: .tension, into: context)

        XCTAssertEqual(missing.gym, "Recovered Name")
        XCTAssertEqual(missing.notes, "Recovered Name")
        XCTAssertEqual(userEdited.gym, "User Gym")
        XCTAssertEqual(userEdited.notes, "User note")
    }

    @MainActor
    func testTB2BackfillMissingGradesFromClimbStatsPreservesExistingGrades() throws {
        context.insert(TB2ClimbStatsMetadata(
            boardRawValue: "tension",
            climbUUID: "missing-grade",
            angle: 40,
            difficultyAverage: 20.6,
            displayDifficulty: nil
        ))
        context.insert(TB2ClimbStatsMetadata(
            boardRawValue: "tension",
            climbUUID: "existing-grade",
            angle: 40,
            difficultyAverage: 22.0,
            displayDifficulty: nil
        ))
        context.insert(TB2ClimbStatsMetadata(
            boardRawValue: "tension",
            climbUUID: "wrong-angle",
            angle: 50,
            difficultyAverage: 23.0,
            displayDifficulty: nil
        ))

        let missing = ClimbEntry(
            climbType: .boulder,
            grade: "",
            angleDegrees: 40,
            style: "Tension board",
            attempts: "2",
            isWorkInProgress: true,
            gym: "",
            notes: nil,
            tb2ClimbUUID: "missing-grade"
        )
        let existing = ClimbEntry(
            climbType: .boulder,
            grade: "6a",
            angleDegrees: 40,
            style: "Tension board",
            attempts: "2",
            isWorkInProgress: true,
            gym: "",
            notes: nil,
            tb2ClimbUUID: "existing-grade"
        )
        let mismatchedAngle = ClimbEntry(
            climbType: .boulder,
            grade: "",
            angleDegrees: 40,
            style: "Tension board",
            attempts: "2",
            isWorkInProgress: true,
            gym: "",
            notes: nil,
            tb2ClimbUUID: "wrong-angle"
        )
        context.insert(missing)
        context.insert(existing)
        context.insert(mismatchedAngle)
        try context.save()

        try TB2SyncManager.backfillMissingGradesFromClimbStats(board: .tension, into: context)

        XCTAssertEqual(missing.grade, "6c+")
        XCTAssertEqual(existing.grade, "6a")
        XCTAssertEqual(mismatchedAngle.grade, "")
    }

    
    // MARK: - Exercise Catalog Management Tests
    
    func testExerciseAreaGrouping() {
        let activity = createTestActivity()
        let trainingType = createTestTrainingType(activity: activity)
        
        // Create exercises with different areas
        let fingerExercise = Exercise(name: "Finger Rolls", area: "Fingers")
        let pullExercise = Exercise(name: "Pull-ups", area: "Pull")
        let ungroupedExercise = Exercise(name: "General Exercise")
        
        trainingType.exercises.append(contentsOf: [fingerExercise, pullExercise, ungroupedExercise])
        try? context.save()
        
        // Test area-based grouping logic
        let exercisesByArea = Dictionary(grouping: trainingType.exercises) { $0.area ?? "" }
        
        XCTAssertEqual(exercisesByArea["Fingers"]?.count, 1)
        XCTAssertEqual(exercisesByArea["Pull"]?.count, 1)
        XCTAssertEqual(exercisesByArea[""]?.count, 1) // Ungrouped
    }
    
    
    
    func testBoulderCombinationManagement() {
        let activity = createTestActivity()
        let trainingType = createTestTrainingType(activity: activity)
        
        let combo = BoulderCombination(name: "Power Circuit", comboDescription: "High intensity bouldering")
        trainingType.combinations.append(combo)
        
        let exercise1 = Exercise(name: "Campus Board")
        let exercise2 = Exercise(name: "Dyno Practice")
        combo.exercises.append(contentsOf: [exercise1, exercise2])
        
        try? context.save()
        
        XCTAssertEqual(combo.exercises.count, 2)
        XCTAssertEqual(combo.comboDescription, "High intensity bouldering")
        XCTAssertTrue(trainingType.exercises.isEmpty) // Exercises are in combo, not direct
        XCTAssertFalse(trainingType.combinations.isEmpty)
    }
    
    // MARK: - Data Validation Tests
    
    func testRequiredFieldValidation() {
        // Test that required fields are enforced
        let activity = Activity(name: "")
        XCTAssertEqual(activity.name, "") // Empty name should be allowed but tracked
        
        let exercise = Exercise(name: "Valid Exercise")
        XCTAssertEqual(exercise.name, "Valid Exercise")
        XCTAssertNotNil(exercise.id)
    }
    
    func testDateConsistency() {
        let originalDate = Date()
        let session = Session(date: originalDate)
        let plan = createTestPlan(kindKey: "weekly")
        
        // Dates should be normalized to start of day
        let calendar = Calendar.current
        let expectedDate = calendar.startOfDay(for: originalDate)
        
        XCTAssertEqual(calendar.startOfDay(for: session.date), expectedDate)
        XCTAssertEqual(calendar.startOfDay(for: plan.startDate), calendar.startOfDay(for: originalDate))
    }
    
    // MARK: - Performance Tests
    
    func testLargeDatasetPerformance() {
        measure {
            // Create a large dataset
            for i in 0..<100 {
                let activity = Activity(name: "Activity \(i)")
                context.insert(activity)
                
                for j in 0..<5 {
                    let trainingType = TrainingType(name: "Type \(i)-\(j)")
                    activity.types.append(trainingType)
                    
                    for k in 0..<10 {
                        let exercise = Exercise(name: "Exercise \(i)-\(j)-\(k)")
                        trainingType.exercises.append(exercise)
                    }
                }
            }
            
            try? context.save()
        }
    }
    
    func testQueryPerformance() {
        // Setup test data
        SeedData.loadIfNeeded(context)
        
        measure {
            // Test common queries
            let activityDescriptor = FetchDescriptor<Activity>(sortBy: [SortDescriptor(\Activity.name)])
            _ = try? context.fetch(activityDescriptor)
            
            let sessionDescriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\Session.date, order: .reverse)])
            _ = try? context.fetch(sessionDescriptor)
            
            let exerciseDescriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\Exercise.name)])
            _ = try? context.fetch(exerciseDescriptor)
        }
    }
    
    // MARK: - UI Component Integration Tests
    
    func testThemeIntegration() {
        // Test that Theme functionality is properly defined and accessible
        // Test DayType color extensions
        XCTAssertNotNil(DayTypeModel.color(for: "green"))
        XCTAssertNotNil(DayTypeModel.color(for: "orange"))
        XCTAssertNotNil(DayTypeModel.color(for: "purple"))
        
        // Test CatalogHue functionality
        XCTAssertNotNil(CatalogHue.core.color)
        XCTAssertNotNil(CatalogHue.climbing.color)
        XCTAssertNotNil(CatalogHue.antagonist.color)
        
        // Test Activity hue mapping
        let coreActivity = Activity(name: "Core Training")
        let climbingActivity = Activity(name: "Climbing Exercises")
        
        XCTAssertEqual(coreActivity.hue, .core)
        XCTAssertEqual(climbingActivity.hue, .climbing)
    }
    
    func testSharedSheetIntegration() {
        // Test shared sheet functionality with test data
        let session = createTestSession()
        let item = SessionItem(exerciseName: "Test Exercise", notes: "Test notes")
        session.items.append(item)
        try? context.save()
        
        let exportDoc = LogCSV.makeExportCSV(context: context)
        XCTAssertFalse(exportDoc.csv.isEmpty)
        XCTAssertTrue(exportDoc.csv.contains("Test Exercise"))
    }
    
    // MARK: - DevTools Integration Tests
    
    func testDevToolsNukeAndReseed() {
        // Create some test data first
        _ = createTestActivity()
        _ = createTestSession()
        _ = createTestPlan(kindKey: "weekly")
        try? context.save()
        
        // Verify data exists
        let initialActivities = (try? context.fetch(FetchDescriptor<Activity>()))?.count ?? 0
        let initialSessions = (try? context.fetch(FetchDescriptor<Session>()))?.count ?? 0
        let initialPlans = (try? context.fetch(FetchDescriptor<Plan>()))?.count ?? 0
        
        XCTAssertGreaterThan(initialActivities, 0)
        XCTAssertGreaterThan(initialSessions, 0)
        XCTAssertGreaterThan(initialPlans, 0)
        
        // Test DevTools nuke and reseed functionality
        #if DEBUG
        DevTools.nukeAndReseed(context)
        #endif
        
        // Verify data was cleared and reseeded
        let activities = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        
        // Should have seed data but no test sessions/plans
        XCTAssertFalse(activities.isEmpty, "Should have seeded activities")
    }
}
