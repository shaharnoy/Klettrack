import XCTest
import SwiftData
@testable import klettrack

@MainActor
final class SyncMigrationTests: BaseSwiftDataTestCase {
    func testBackfillPlanDaySyncFieldsMapsNameBasedValues() throws {
        let activity = createTestActivity(name: "Test Activity")
        let type = createTestTrainingType(activity: activity, name: "Strength")
        let pullUp = createTestExercise(trainingType: type, name: "Pull-up")
        let plank = createTestExercise(trainingType: type, name: "Plank")

        let kind = PlanKindModel(key: "weekly", name: "Weekly", isRepeating: true, order: 0)
        context.insert(kind)

        let plan = Plan(name: "Plan", kind: kind, startDate: .now)
        let day = PlanDay(date: .now)
        day.chosenExercises = ["Pull-up", "Plank"]
        day.exerciseOrder = ["Pull-up": 0, "Plank": 1]
        plan.days = [day]

        context.insert(plan)
        try context.save()

        backfillPlanDaySyncFields(context)

        XCTAssertEqual(day.chosenExerciseIDs, [pullUp.id, plank.id])
        XCTAssertEqual(day.exerciseOrderByID[pullUp.id.uuidString], 0)
        XCTAssertEqual(day.exerciseOrderByID[plank.id.uuidString], 1)
    }

    func testSyncModelsPersistInSwiftData() throws {
        let state = SyncState()
        state.userId = "user-1"
        state.lastCursor = "2026-02-10T19:20:00Z"
        state.isSyncEnabled = true

        let mutation = SyncMutation()
        mutation.entityName = "plans"
        mutation.baseVersion = 2
        mutation.payloadJSON = #"{"name":"Board Cycle"}"#

        context.insert(state)
        context.insert(mutation)
        try context.save()

        let states = try context.fetch(FetchDescriptor<SyncState>())
        let mutations = try context.fetch(FetchDescriptor<SyncMutation>())

        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states.first?.userId, "user-1")
        XCTAssertEqual(mutations.count, 1)
        XCTAssertEqual(mutations.first?.entityName, "plans")
        XCTAssertEqual(mutations.first?.baseVersion, 2)
    }

    func testBackfillSyncV2RelationshipsPreservesRowCountsAndLinksChildren() throws {
        let session = Session(date: .now)
        let item = SessionItem(exerciseName: "Moonboard")
        session.items = [item]

        let template = TimerTemplate(
            name: "Intervals",
            isRepeating: false
        )
        let interval = TimerInterval(
            name: "30/30",
            workTimeSeconds: 30,
            restTimeSeconds: 30,
            repetitions: 3
        )
        template.intervals = [interval]

        let timerSession = TimerSession()
        let lap = TimerLap(lapNumber: 1, elapsedSeconds: 30)
        timerSession.laps = [lap]

        let climb = ClimbEntry(
            climbType: .boulder,
            grade: "V4",
            style: "Technical",
            gym: "Test Gym"
        )
        let media = ClimbMedia(
            assetLocalIdentifier: "asset-1",
            type: .photo,
            climb: climb
        )
        climb.media = [media]

        context.insert(session)
        context.insert(item)
        context.insert(template)
        context.insert(interval)
        context.insert(timerSession)
        context.insert(lap)
        context.insert(climb)
        context.insert(media)
        try context.save()

        let sessionCountBefore = try context.fetchCount(FetchDescriptor<Session>())
        let itemCountBefore = try context.fetchCount(FetchDescriptor<SessionItem>())
        let templateCountBefore = try context.fetchCount(FetchDescriptor<TimerTemplate>())
        let intervalCountBefore = try context.fetchCount(FetchDescriptor<TimerInterval>())
        let timerSessionCountBefore = try context.fetchCount(FetchDescriptor<TimerSession>())
        let lapCountBefore = try context.fetchCount(FetchDescriptor<TimerLap>())
        let climbCountBefore = try context.fetchCount(FetchDescriptor<ClimbEntry>())
        let mediaCountBefore = try context.fetchCount(FetchDescriptor<ClimbMedia>())

        backfillSyncV2RelationshipsAndMetadata(context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Session>()), sessionCountBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionItem>()), itemCountBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimerTemplate>()), templateCountBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimerInterval>()), intervalCountBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimerSession>()), timerSessionCountBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimerLap>()), lapCountBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ClimbEntry>()), climbCountBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ClimbMedia>()), mediaCountBefore)

        XCTAssertEqual(session.items.first?.session?.id, session.id)
        XCTAssertEqual(template.intervals.first?.updatedAtClient.timeIntervalSinceNow ?? -1, 0, accuracy: 5)
        XCTAssertEqual(timerSession.laps.first?.updatedAtClient.timeIntervalSinceNow ?? -1, 0, accuracy: 5)
        XCTAssertEqual(climb.media.first?.climb.id, climb.id)
    }
}
