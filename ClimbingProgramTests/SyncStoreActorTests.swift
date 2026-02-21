//
//  SyncStoreActorTests.swift
//  Klettrack tests
//  Created by Shahar Noy on 17.02.26.
//

import XCTest
import SwiftData
@testable import klettrack

@MainActor
final class SyncStoreActorTests: BaseSwiftDataTestCase {
    func testEnqueueAndFetchPendingMutations() async throws {
        let store = SyncStoreActor(modelContainer: container)
        let entityId = UUID()

        _ = try await store.enqueueMutation(
            entity: .plans,
            entityId: entityId,
            mutationType: .upsert,
            baseVersion: 0,
            payload: ["name": .string("Board Cycle")]
        )

        let pending = try await store.fetchPendingMutations(limit: 10)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.entity, .plans)
        XCTAssertEqual(pending.first?.entityId, entityId)
        XCTAssertEqual(pending.first?.payload["name"], .string("Board Cycle"))
    }

    func testProcessPushResponseAcksAndFailures() async throws {
        let store = SyncStoreActor(modelContainer: container)
        let firstOpID = try await store.enqueueMutation(
            entity: .activities,
            entityId: UUID(),
            mutationType: .upsert,
            baseVersion: 0,
            payload: ["name": .string("Warm Up")]
        )
        let secondOpID = try await store.enqueueMutation(
            entity: .activities,
            entityId: UUID(),
            mutationType: .upsert,
            baseVersion: 0,
            payload: ["name": .string("Strength")]
        )

        let response = SyncPushResponse(
            acknowledgedOpIds: [firstOpID.uuidString.lowercased()],
            conflicts: [],
            failed: [SyncPushFailure(opId: secondOpID.uuidString.lowercased(), reason: "insert_failed")],
            newCursor: "2026-02-10T20:00:00Z"
        )

        let result = try await store.processPushResponse(response)
        XCTAssertEqual(result.acknowledged, 1)
        XCTAssertEqual(result.failures, 1)

        let pending = try await store.fetchPendingMutations(limit: 10)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.opId, secondOpID)
        XCTAssertEqual(pending.first?.attempts, 1)
    }

    func testProcessPushResponseRecordsConflictAndResolutionKeepsMine() async throws {
        let store = SyncStoreActor(modelContainer: container)
        let opID = try await store.enqueueMutation(
            entity: .plans,
            entityId: UUID(),
            mutationType: .upsert,
            baseVersion: 1,
            payload: ["name": .string("Conflict Plan")]
        )

        let response = SyncPushResponse(
            acknowledgedOpIds: [],
            conflicts: [
                SyncPushConflict(
                    opId: opID.uuidString.lowercased(),
                    entity: .plans,
                    entityId: UUID().uuidString.lowercased(),
                    reason: "version_mismatch",
                    serverVersion: 7,
                    serverDoc: nil
                )
            ],
            failed: [],
            newCursor: "2026-02-10T20:00:00Z"
        )

        let result = try await store.processPushResponse(response)
        XCTAssertEqual(result.conflicts, 1)

        var pending = try await store.fetchPendingMutations(limit: 10)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.attempts, 1)
        XCTAssertEqual(pending.first?.baseVersion, 1)

        let resolved = try await store.resolveConflictKeepMine(
            opId: opID.uuidString.lowercased(),
            serverVersion: 7
        )
        XCTAssertTrue(resolved)

        pending = try await store.fetchPendingMutations(limit: 10)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.baseVersion, 7)
        XCTAssertEqual(pending.first?.attempts, 0)
    }

    func testResolveConflictKeepMineForTimerLapMutationRebasesVersion() async throws {
        let store = SyncStoreActor(modelContainer: container)
        let opID = try await store.enqueueMutation(
            entity: .timerLaps,
            entityId: UUID(),
            mutationType: .upsert,
            baseVersion: 2,
            payload: [
                "timer_session_id": .string(UUID().uuidString.lowercased()),
                "lap_number": .number(1),
                "timestamp": .string("2026-02-14T10:00:00.000Z"),
                "elapsed_seconds": .number(30)
            ]
        )

        let response = SyncPushResponse(
            acknowledgedOpIds: [],
            conflicts: [
                SyncPushConflict(
                    opId: opID.uuidString.lowercased(),
                    entity: .timerLaps,
                    entityId: UUID().uuidString.lowercased(),
                    reason: "version_mismatch",
                    serverVersion: 9,
                    serverDoc: nil
                )
            ],
            failed: [],
            newCursor: "2026-02-14T10:10:00.000Z"
        )

        _ = try await store.processPushResponse(response)
        let resolved = try await store.resolveConflictKeepMine(
            opId: opID.uuidString.lowercased(),
            serverVersion: 9
        )
        XCTAssertTrue(resolved)

        let pending = try await store.fetchPendingMutations(limit: 10)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.entity, .timerLaps)
        XCTAssertEqual(pending.first?.baseVersion, 9)
        XCTAssertEqual(pending.first?.attempts, 0)
    }

    func testResolveConflictKeepMineWithMissingServerRowRebasesToZero() async throws {
        let store = SyncStoreActor(modelContainer: container)
        let opID = try await store.enqueueMutation(
            entity: .plans,
            entityId: UUID(),
            mutationType: .upsert,
            baseVersion: 12,
            payload: ["name": .string("Bootstrap Plan")]
        )

        let response = SyncPushResponse(
            acknowledgedOpIds: [],
            conflicts: [
                SyncPushConflict(
                    opId: opID.uuidString.lowercased(),
                    entity: .plans,
                    entityId: UUID().uuidString.lowercased(),
                    reason: "version_mismatch",
                    serverVersion: nil,
                    serverDoc: nil
                )
            ],
            failed: [],
            newCursor: "2026-02-14T19:00:00.000Z"
        )

        _ = try await store.processPushResponse(response)
        let resolved = try await store.resolveConflictKeepMine(
            opId: opID.uuidString.lowercased(),
            serverVersion: nil
        )
        XCTAssertTrue(resolved)

        let pending = try await store.fetchPendingMutations(limit: 10)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.baseVersion, 0)
    }

    func testSetSyncEnabledSwitchingUserResetsCursorAndClearsOutbox() async throws {
        let store = SyncStoreActor(modelContainer: container)

        try await store.setSyncEnabled(true, userId: "user-a")
        _ = try await store.enqueueMutation(
            entity: .plans,
            entityId: UUID(),
            mutationType: .upsert,
            baseVersion: 0,
            payload: ["name": .string("Account A Plan")]
        )
        try await store.applyPullResponse(
            SyncPullResponse(
                changes: [],
                nextCursor: "2026-02-14T20:00:00.000Z|plans|abc",
                hasMore: false
            )
        )

        let beforeSwitch = try await store.loadOrCreateSyncState()
        let pendingBeforeSwitch = try await store.fetchPendingMutations(limit: 10)
        XCTAssertEqual(beforeSwitch.userId, "user-a")
        XCTAssertEqual(beforeSwitch.lastCursor, "2026-02-14T20:00:00.000Z|plans|abc")
        XCTAssertEqual(pendingBeforeSwitch.count, 1)

        try await store.setSyncEnabled(true, userId: "user-b")

        let afterSwitch = try await store.loadOrCreateSyncState()
        let pendingAfterSwitch = try await store.fetchPendingMutations(limit: 10)
        XCTAssertEqual(afterSwitch.userId, "user-b")
        XCTAssertNil(afterSwitch.lastCursor)
        XCTAssertTrue(pendingAfterSwitch.isEmpty)
    }

    func testApplyPullResponseUpsertsAndDeletesActivity() async throws {
        let store = SyncStoreActor(modelContainer: container)
        let activityID = UUID()

        let upsert = SyncPullResponse(
            changes: [
                SyncPullChange(
                    entity: .activities,
                    type: .upsert,
                    entityId: nil,
                    version: nil,
                    doc: [
                        "id": .string(activityID.uuidString.lowercased()),
                        "name": .string("Power"),
                        "version": .number(3),
                        "updated_at_client": .string("2026-02-10T20:10:00.123Z"),
                        "is_deleted": .bool(false)
                    ]
                )
            ],
            nextCursor: "2026-02-10T20:10:00.123Z",
            hasMore: false
        )

        try await store.applyPullResponse(upsert)
        let verificationContext = ModelContext(container)

        let inserted = try verificationContext.fetch(
            FetchDescriptor<Activity>(predicate: #Predicate { $0.id == activityID })
        ).first
        XCTAssertEqual(inserted?.name, "Power")
        XCTAssertEqual(inserted?.syncVersion, 3)
        XCTAssertEqual(inserted?.isSoftDeleted, false)

        let delete = SyncPullResponse(
            changes: [
                SyncPullChange(
                    entity: .activities,
                    type: .delete,
                    entityId: activityID.uuidString.lowercased(),
                    version: 4,
                    doc: nil
                )
            ],
            nextCursor: "2026-02-10T20:11:00.000Z",
            hasMore: false
        )

        try await store.applyPullResponse(delete)
        let deleted = try await store.activityState(id: activityID)
        XCTAssertNotNil(deleted)
    }

    func testApplyPullResponseUpsertsSessionAndItem() async throws {
        let store = SyncStoreActor(modelContainer: container)
        let sessionID = UUID()
        let itemID = UUID()

        let response = SyncPullResponse(
            changes: [
                SyncPullChange(
                    entity: .sessions,
                    type: .upsert,
                    entityId: nil,
                    version: nil,
                    doc: [
                        "id": .string(sessionID.uuidString.lowercased()),
                        "session_date": .string("2026-02-14T10:00:00.000Z"),
                        "version": .number(2),
                        "updated_at_client": .string("2026-02-14T10:00:00.000Z"),
                        "is_deleted": .bool(false)
                    ]
                ),
                SyncPullChange(
                    entity: .sessionItems,
                    type: .upsert,
                    entityId: nil,
                    version: nil,
                    doc: [
                        "id": .string(itemID.uuidString.lowercased()),
                        "session_id": .string(sessionID.uuidString.lowercased()),
                        "exercise_name": .string("Campus Board"),
                        "sort_order": .number(1),
                        "reps": .number(8),
                        "sets": .number(3),
                        "version": .number(2),
                        "updated_at_client": .string("2026-02-14T10:00:00.000Z"),
                        "is_deleted": .bool(false)
                    ]
                )
            ],
            nextCursor: "2026-02-14T10:00:00.000Z|session_items|\(itemID.uuidString.lowercased())",
            hasMore: false
        )

        try await store.applyPullResponse(response)

        let verificationContext = ModelContext(container)
        let sessions = try verificationContext.fetch(FetchDescriptor<Session>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.syncVersion, 2)
        XCTAssertEqual(sessions.first?.items.count, 1)
        XCTAssertEqual(sessions.first?.items.first?.exerciseName, "Campus Board")
    }

    func testApplyPullResponseUpsertsTimerTemplateAndInterval() async throws {
        let store = SyncStoreActor(modelContainer: container)
        let templateID = UUID()
        let intervalID = UUID()

        let response = SyncPullResponse(
            changes: [
                SyncPullChange(
                    entity: .timerTemplates,
                    type: .upsert,
                    entityId: nil,
                    version: nil,
                    doc: [
                        "id": .string(templateID.uuidString.lowercased()),
                        "name": .string("Power Intervals"),
                        "created_date": .string("2026-02-14T10:00:00.000Z"),
                        "is_repeating": .bool(true),
                        "use_count": .number(4),
                        "version": .number(1),
                        "is_deleted": .bool(false)
                    ]
                ),
                SyncPullChange(
                    entity: .timerIntervals,
                    type: .upsert,
                    entityId: nil,
                    version: nil,
                    doc: [
                        "id": .string(intervalID.uuidString.lowercased()),
                        "timer_template_id": .string(templateID.uuidString.lowercased()),
                        "name": .string("40/20"),
                        "work_time_seconds": .number(40),
                        "rest_time_seconds": .number(20),
                        "repetitions": .number(6),
                        "display_order": .number(0),
                        "version": .number(1),
                        "is_deleted": .bool(false)
                    ]
                )
            ],
            nextCursor: "2026-02-14T10:00:00.000Z|timer_intervals|\(intervalID.uuidString.lowercased())",
            hasMore: false
        )

        try await store.applyPullResponse(response)

        let verificationContext = ModelContext(container)
        let templates = try verificationContext.fetch(FetchDescriptor<TimerTemplate>())
        XCTAssertEqual(templates.count, 1)
        XCTAssertEqual(templates.first?.name, "Power Intervals")
        XCTAssertEqual(templates.first?.intervals.count, 1)
        XCTAssertEqual(templates.first?.intervals.first?.name, "40/20")
    }

    func testApplyPullResponseUpsertsClimbEntry() async throws {
        let store = SyncStoreActor(modelContainer: container)
        let climbID = UUID()

        let response = SyncPullResponse(
            changes: [
                SyncPullChange(
                    entity: .climbEntries,
                    type: .upsert,
                    entityId: nil,
                    version: nil,
                    doc: [
                        "id": .string(climbID.uuidString.lowercased()),
                        "climb_type": .string("Boulder"),
                        "grade": .string("V5"),
                        "style": .string("Technical"),
                        "gym": .string("Ostbloc"),
                        "date_logged": .string("2026-02-14T10:00:00.000Z"),
                        "is_work_in_progress": .bool(false),
                        "version": .number(2),
                        "is_deleted": .bool(false)
                    ]
                )
            ],
            nextCursor: "2026-02-14T10:00:00.000Z|climb_entries|\(climbID.uuidString.lowercased())",
            hasMore: false
        )

        try await store.applyPullResponse(response)

        let verificationContext = ModelContext(container)
        let climbs = try verificationContext.fetch(FetchDescriptor<ClimbEntry>())
        XCTAssertEqual(climbs.count, 1)
        XCTAssertEqual(climbs.first?.grade, "V5")
        XCTAssertTrue(climbs.first?.media.isEmpty ?? true)
    }

    func testPendingMutationPreservesUpdatedAtClientTimestamp() async throws {
        let store = SyncStoreActor(modelContainer: container)
        let timestamp = Date(timeIntervalSince1970: 1_707_000_000)

        _ = try await store.enqueueMutation(
            entity: .plans,
            entityId: UUID(),
            mutationType: .upsert,
            baseVersion: 3,
            payload: ["name": .string("Timestamped Plan")],
            updatedAtClient: timestamp
        )

        let pending = try await store.fetchPendingMutations(limit: 1)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.updatedAtClient, timestamp)
    }

    func testApplyPullDeleteRemovesBoulderCombinationExerciseLinkByDeterministicID() async throws {
        let store = SyncStoreActor(modelContainer: container)
        let trainingTypeID = UUID()
        let combinationID = UUID()
        let exerciseID = UUID()

        let context = ModelContext(container)
        let type = TrainingType(id: trainingTypeID, name: "Boulder")
        let combination = BoulderCombination(id: combinationID, name: "4x4")
        let exercise = Exercise(id: exerciseID, name: "Limit")
        combination.exercises.append(exercise)
        type.combinations.append(combination)
        context.insert(type)
        context.insert(combination)
        context.insert(exercise)
        try context.save()

        let linkID = SyncStoreActor.boulderCombinationExerciseLinkID(
            combinationID: combinationID,
            exerciseID: exerciseID
        )
        let response = SyncPullResponse(
            changes: [
                SyncPullChange(
                    entity: .boulderCombinationExercises,
                    type: .delete,
                    entityId: linkID.uuidString.lowercased(),
                    version: 2,
                    doc: nil
                )
            ],
            nextCursor: "2026-02-15T10:00:00.000Z|boulder_combination_exercises|\(linkID.uuidString.lowercased())",
            hasMore: false
        )

        try await store.applyPullResponse(response)

        let verifyContext = ModelContext(container)
        let combinations = try verifyContext.fetch(FetchDescriptor<BoulderCombination>())
        XCTAssertEqual(combinations.count, 1)
        XCTAssertTrue(combinations[0].exercises.isEmpty)
    }

    func testPostBootstrapLocalEditPushPullParityForActivity() async throws {
        let store = SyncStoreActor(modelContainer: container)
        let activityID = UUID()
        let bootstrapTimestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let seedContext = ModelContext(container)
        let activity = Activity(id: activityID, name: "Campus Board")
        activity.syncVersion = 2
        activity.updatedAtClient = bootstrapTimestamp
        seedContext.insert(activity)
        try seedContext.save()

        try await store.setSyncEnabled(true, userId: "user-a")
        let bootstrapped = try await store.enqueueLocalSnapshotIfNeeded()
        XCTAssertTrue(bootstrapped)

        var pending = try await store.fetchPendingMutations(limit: 10)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].entity, .activities)
        XCTAssertEqual(pending[0].payload["name"], .string("Campus Board"))

        let firstAck = SyncPushResponse(
            acknowledgedOpIds: [pending[0].opId.uuidString.lowercased()],
            conflicts: [],
            failed: [],
            newCursor: "2026-02-15T11:00:00.000Z|activities|\(activityID.uuidString.lowercased())"
        )
        _ = try await store.processPushResponse(firstAck)

        try await store.applyPullResponse(
            SyncPullResponse(
                changes: [
                    SyncPullChange(
                        entity: .activities,
                        type: .upsert,
                        entityId: nil,
                        version: nil,
                        doc: [
                            "id": .string(activityID.uuidString.lowercased()),
                            "name": .string("Campus Board"),
                            "version": .number(3),
                            "updated_at_client": .string("2026-02-15T11:00:00.000Z"),
                            "is_deleted": .bool(false)
                        ]
                    )
                ],
                nextCursor: "2026-02-15T11:00:00.000Z|activities|\(activityID.uuidString.lowercased())",
                hasMore: false
            )
        )

        let editContext = ModelContext(container)
        let edited = try editContext.fetch(FetchDescriptor<Activity>(predicate: #Predicate { $0.id == activityID })).first
        XCTAssertNotNil(edited)
        edited?.name = "Campus Board Advanced"
        if let edited {
            SyncLocalMutation.touch(edited)
        }
        try editContext.save()

        let postEditEnqueue = try await store.enqueueLocalSnapshotIfNeeded()
        XCTAssertTrue(postEditEnqueue)

        pending = try await store.fetchPendingMutations(limit: 10)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].baseVersion, 3)
        XCTAssertEqual(pending[0].payload["name"], .string("Campus Board Advanced"))

        let secondAck = SyncPushResponse(
            acknowledgedOpIds: [pending[0].opId.uuidString.lowercased()],
            conflicts: [],
            failed: [],
            newCursor: "2026-02-15T11:05:00.000Z|activities|\(activityID.uuidString.lowercased())"
        )
        _ = try await store.processPushResponse(secondAck)

        try await store.applyPullResponse(
            SyncPullResponse(
                changes: [
                    SyncPullChange(
                        entity: .activities,
                        type: .upsert,
                        entityId: nil,
                        version: nil,
                        doc: [
                            "id": .string(activityID.uuidString.lowercased()),
                            "name": .string("Campus Board Advanced"),
                            "version": .number(4),
                            "updated_at_client": .string("2026-02-15T11:05:00.000Z"),
                            "is_deleted": .bool(false)
                        ]
                    )
                ],
                nextCursor: "2026-02-15T11:05:00.000Z|activities|\(activityID.uuidString.lowercased())",
                hasMore: false
            )
        )

        let verifyContext = ModelContext(container)
        let synced = try verifyContext.fetch(FetchDescriptor<Activity>(predicate: #Predicate { $0.id == activityID })).first
        XCTAssertEqual(synced?.name, "Campus Board Advanced")
        XCTAssertEqual(synced?.syncVersion, 4)
        let remainingPending = try await store.fetchPendingMutations(limit: 10)
        XCTAssertTrue(remainingPending.isEmpty)
    }

    func testSetSyncEnabledSameUserKeepsCursorAndPendingMutations() async throws {
        let store = SyncStoreActor(modelContainer: container)
        let activityID = UUID()

        try await store.setSyncEnabled(true, userId: "user-a")
        _ = try await store.enqueueMutation(
            entity: .activities,
            entityId: activityID,
            mutationType: .upsert,
            baseVersion: 0,
            payload: ["name": .string("Pending")]
        )
        try await store.applyPullResponse(
            SyncPullResponse(
                changes: [],
                nextCursor: "2026-02-15T13:00:00.000Z|activities|\(activityID.uuidString.lowercased())",
                hasMore: false
            )
        )

        let before = try await store.loadOrCreateSyncState()
        let pendingBefore = try await store.fetchPendingMutations(limit: 10)
        XCTAssertEqual(before.userId, "user-a")
        XCTAssertEqual(before.lastCursor, "2026-02-15T13:00:00.000Z|activities|\(activityID.uuidString.lowercased())")
        XCTAssertEqual(pendingBefore.count, 1)

        try await store.setSyncEnabled(true, userId: "user-a")

        let after = try await store.loadOrCreateSyncState()
        let pendingAfter = try await store.fetchPendingMutations(limit: 10)
        XCTAssertEqual(after.userId, "user-a")
        XCTAssertEqual(after.lastCursor, before.lastCursor)
        XCTAssertEqual(pendingAfter.count, 1)
    }

    func testApplyPullUpsertAddsBoulderCombinationExerciseRelation() async throws {
        let store = SyncStoreActor(modelContainer: container)
        let trainingTypeID = UUID()
        let combinationID = UUID()
        let exerciseID = UUID()
        let linkID = SyncStoreActor.boulderCombinationExerciseLinkID(
            combinationID: combinationID,
            exerciseID: exerciseID
        )

        let context = ModelContext(container)
        let type = TrainingType(id: trainingTypeID, name: "Boulder")
        let combination = BoulderCombination(id: combinationID, name: "4x4")
        let exercise = Exercise(id: exerciseID, name: "Limit")
        type.combinations.append(combination)
        type.exercises.append(exercise)
        context.insert(type)
        context.insert(combination)
        context.insert(exercise)
        try context.save()

        let response = SyncPullResponse(
            changes: [
                SyncPullChange(
                    entity: .boulderCombinationExercises,
                    type: .upsert,
                    entityId: nil,
                    version: nil,
                    doc: [
                        "id": .string(linkID.uuidString.lowercased()),
                        "boulder_combination_id": .string(combinationID.uuidString.lowercased()),
                        "exercise_id": .string(exerciseID.uuidString.lowercased()),
                        "display_order": .number(0),
                        "version": .number(1),
                        "is_deleted": .bool(false)
                    ]
                )
            ],
            nextCursor: "2026-02-15T14:00:00.000Z|boulder_combination_exercises|\(linkID.uuidString.lowercased())",
            hasMore: false
        )

        try await store.applyPullResponse(response)

        let verifyContext = ModelContext(container)
        let combinations = try verifyContext.fetch(FetchDescriptor<BoulderCombination>())
        XCTAssertEqual(combinations.count, 1)
        XCTAssertEqual(combinations[0].exercises.count, 1)
        XCTAssertEqual(combinations[0].exercises[0].id, exerciseID)
    }

    func testApplyPullPlanDayUpsertDoesNotCreateMissingPlan() async throws {
        let store = SyncStoreActor(modelContainer: container)
        let planID = UUID()
        let dayID = UUID()

        let response = SyncPullResponse(
            changes: [
                SyncPullChange(
                    entity: .planDays,
                    type: .upsert,
                    entityId: nil,
                    version: nil,
                    doc: [
                        "id": .string(dayID.uuidString.lowercased()),
                        "plan_id": .string(planID.uuidString.lowercased()),
                        "day_date": .string("2026-02-17T20:00:00.000Z"),
                        "is_deleted": .bool(false),
                        "version": .number(3)
                    ]
                )
            ],
            nextCursor: "2026-02-17T20:00:00.000Z|plan_days|\(dayID.uuidString.lowercased())",
            hasMore: false
        )

        try await store.applyPullResponse(response)

        let verifyContext = ModelContext(container)
        let plans = try verifyContext.fetch(FetchDescriptor<Plan>())
        XCTAssertTrue(plans.isEmpty)

        let days = try verifyContext.fetch(FetchDescriptor<PlanDay>())
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].id, dayID)
    }

    func testEnqueueSnapshotAfterPlanDeleteEmitsDeleteForPlanAndDays() async throws {
        let store = SyncStoreActor(modelContainer: container)
        let context = ModelContext(container)
        let plan = Plan(name: "Delete Me", kind: nil, startDate: .now)
        let dayOne = PlanDay(date: .now)
        let dayTwo = PlanDay(date: .now.addingTimeInterval(86_400))
        plan.days = [dayOne, dayTwo]
        context.insert(plan)
        context.insert(dayOne)
        context.insert(dayTwo)
        try context.save()

        try await store.setSyncEnabled(true, userId: "user-a")

        let planID = plan.id
        let editablePlan = try context.fetch(
            FetchDescriptor<Plan>(predicate: #Predicate { $0.id == planID })
        ).first
        XCTAssertNotNil(editablePlan)
        guard let editablePlan else {
            XCTFail("Expected plan to exist before delete.")
            return
        }

        SyncLocalMutation.softDelete(editablePlan)
        for day in editablePlan.days {
            SyncLocalMutation.softDelete(day)
        }
        XCTAssertEqual(editablePlan.isSoftDeleted, true)
        try context.save()

        let sameContextPlan = try context.fetch(
            FetchDescriptor<Plan>(predicate: #Predicate { $0.id == planID })
        ).first
        XCTAssertEqual(sameContextPlan?.isSoftDeleted, true)

        let verificationContext = ModelContext(container)
        let allPersistedPlans = try verificationContext.fetch(FetchDescriptor<Plan>())
        XCTAssertEqual(allPersistedPlans.count, 1)
        let persistedPlan = try verificationContext.fetch(
            FetchDescriptor<Plan>(predicate: #Predicate { $0.id == planID })
        ).first
        XCTAssertEqual(persistedPlan?.isSoftDeleted, true)

        _ = try await store.enqueueLocalSnapshotIfNeeded()
        let pending = try await store.fetchPendingMutations(limit: 20)
        let planDelete = pending.first(where: { $0.entity == .plans && $0.entityId == plan.id })
        XCTAssertEqual(planDelete?.mutationType, .delete)

        let dayMutations = pending.filter {
            $0.entity == .planDays && ($0.entityId == dayOne.id || $0.entityId == dayTwo.id)
        }
        XCTAssertEqual(dayMutations.count, 2)
        XCTAssertTrue(dayMutations.allSatisfy { $0.mutationType == .delete })
    }

    func testEnqueueSnapshotIncludesDeleteWhenWatermarkMissing() async throws {
        let store = SyncStoreActor(modelContainer: container)
        let context = ModelContext(container)
        let plan = Plan(name: "Watermark Case", kind: nil, startDate: .now)
        plan.syncVersion = 4
        context.insert(plan)
        try context.save()

        try await store.setSyncEnabled(true, userId: "user-a")

        let state = try context.fetch(FetchDescriptor<SyncState>()).first
        XCTAssertNotNil(state)
        state?.didBootstrapLocalSnapshot = true
        state?.lastSuccessfulSyncAt = nil
        try context.save()

        let planID = plan.id
        let editablePlan = try context.fetch(
            FetchDescriptor<Plan>(predicate: #Predicate { $0.id == planID })
        ).first
        XCTAssertNotNil(editablePlan)
        guard let editablePlan else {
            XCTFail("Expected plan to exist before delete.")
            return
        }

        SyncLocalMutation.softDelete(editablePlan)
        XCTAssertEqual(editablePlan.isSoftDeleted, true)
        try context.save()

        let sameContextPlan = try context.fetch(
            FetchDescriptor<Plan>(predicate: #Predicate { $0.id == planID })
        ).first
        XCTAssertEqual(sameContextPlan?.isSoftDeleted, true)

        let verificationContext = ModelContext(container)
        let allPersistedPlans = try verificationContext.fetch(FetchDescriptor<Plan>())
        XCTAssertEqual(allPersistedPlans.count, 1)
        let persistedPlan = try verificationContext.fetch(
            FetchDescriptor<Plan>(predicate: #Predicate { $0.id == planID })
        ).first
        XCTAssertEqual(persistedPlan?.isSoftDeleted, true)

        _ = try await store.enqueueLocalSnapshotIfNeeded()
        let pending = try await store.fetchPendingMutations(limit: 10)
        let mutation = pending.first(where: { $0.entity == .plans && $0.entityId == plan.id })
        XCTAssertEqual(mutation?.mutationType, .delete)
    }

    func testFetchPendingMutationsPrioritizesDeleteOverOlderUpsert() async throws {
        let store = SyncStoreActor(modelContainer: container)
        let upsertId = UUID()
        let deleteId = UUID()

        _ = try await store.enqueueMutation(
            entity: .plans,
            entityId: upsertId,
            mutationType: .upsert,
            baseVersion: 1,
            payload: ["name": .string("Older Upsert")]
        )
        _ = try await store.enqueueMutation(
            entity: .plans,
            entityId: deleteId,
            mutationType: .delete,
            baseVersion: 1,
            payload: [:]
        )

        let pending = try await store.fetchPendingMutations(limit: 1)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].entityId, deleteId)
        XCTAssertEqual(pending[0].mutationType, .delete)
    }
}
