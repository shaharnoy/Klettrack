//  AppIntegrationTests.swift
//  klettrack tests
//  Created by Shahar Noy on 28.08.25.
//

import XCTest
import SwiftUI
import SwiftData
@testable import klettrack

final class AppIntegrationTests: BaseSwiftDataTestCase {
    
    // MARK: - App Lifecycle / Schema
    
    func testAppInitialization() {
        // App struct should be constructible
        let app = ClimbingProgramApp()
        XCTAssertNotNil(app)
        
        // SwiftData in-memory container from BaseSwiftDataTestCase should be ready
        XCTAssertNotNil(container)
        XCTAssertNotNil(context)
    }
    
    func testModelContainerConfiguration() {
        let modelTypes = Set(container.schema.entities.map { $0.name })
        
        // Core catalog
        XCTAssertTrue(modelTypes.contains("Activity"))
        XCTAssertTrue(modelTypes.contains("TrainingType"))
        XCTAssertTrue(modelTypes.contains("Exercise"))
        XCTAssertTrue(modelTypes.contains("BoulderCombination"))
        
        // Plans
        XCTAssertTrue(modelTypes.contains("Plan"))
        XCTAssertTrue(modelTypes.contains("PlanDay"))
        
        // Sessions (log)
        XCTAssertTrue(modelTypes.contains("Session"))
        XCTAssertTrue(modelTypes.contains("SessionItem"))
        
        // Timer
        XCTAssertTrue(modelTypes.contains("TimerTemplate"))
        XCTAssertTrue(modelTypes.contains("TimerInterval"))
        XCTAssertTrue(modelTypes.contains("TimerSession"))
        XCTAssertTrue(modelTypes.contains("TimerLap"))
        
        // Climbing log
        XCTAssertTrue(modelTypes.contains("ClimbEntry"))
        XCTAssertTrue(modelTypes.contains("ClimbStyle"))
        XCTAssertTrue(modelTypes.contains("ClimbGym"))
    }
    
    // MARK: - Navigation/Data readiness smoke
    
    func testTabDataReadinessSmoke() {
        // Seed catalog and related data
        SeedData.loadIfNeeded(context)
        
        // Create a plan and a session so tabs have content
        let plan = createTestPlan(name: "Plan A", kindKey: "weekly", start: Date())
        _ = createTestSession(date: plan.startDate)
        try? context.save()
        
        // Catalog (activities)
        let activities = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        XCTAssertFalse(activities.isEmpty, "Catalog tab should have data")
        
        // Plans
        let plans = (try? context.fetch(FetchDescriptor<Plan>())) ?? []
        XCTAssertFalse(plans.isEmpty, "Plans tab should have data")
        
        // Log (sessions)
        let sessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        XCTAssertFalse(sessions.isEmpty, "Log tab should have data")
    }
    
    // MARK: - Cross-feature data flow
    
    func testDataFlowBetweenFeatures() throws {
        // 1. Catalog data
        let activity = createTestActivity(name: "Integration Activity")
        let trainingType = createTestTrainingType(activity: activity, name: "Integration Type")
        let exercise = createTestExercise(trainingType: trainingType, name: "Integration Exercise")
        
        // 2. Plan using exercise
        let plan = createTestPlan(name: "Integration Plan", kindKey: "weekly", start: Date())
        guard let planDay = plan.days.first else {
            XCTFail("Plan should have at least one day")
            return
        }
        planDay.chosenExercises.append(exercise.name)
        
        // 3. Log session item derived from plan
        let session = createTestSession(date: planDay.date)
        let sessionItem = SessionItem(
            exerciseName: exercise.name,
            planSourceId: plan.id,
            planName: plan.name,
            reps: 10,
            sets: 3
        )
        session.items.append(sessionItem)
        
        try context.save()
        
        // 4. Verify for analytics/export
        let loggedItems = (try? context.fetch(FetchDescriptor<SessionItem>())) ?? []
        XCTAssertEqual(loggedItems.count, 1)
        XCTAssertEqual(loggedItems.first?.exerciseName, exercise.name)
        XCTAssertEqual(loggedItems.first?.planSourceId, plan.id)
    }
    
    // MARK: - User journeys (model-level)
    
    func testCompleteExerciseSelectionJourney() throws {
        // Start → Catalog → Activity → TrainingType → Exercise → Plan (model-level)
        SeedData.loadIfNeeded(context)
        
        let activities = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        XCTAssertFalse(activities.isEmpty)
        
        // Use a known seeded activity if available
        let core = activities.first(where: { $0.name == "Core" }) ?? activities.first
        guard let coreActivity = core else {
            return XCTFail("Expected to find at least one activity")
        }
        
        let types = coreActivity.types
        XCTAssertFalse(types.isEmpty)
        let firstType = types.first!
        let exercises = firstType.exercises
        XCTAssertFalse(exercises.isEmpty)
        
        let exercise = exercises.first!
        let startDate = Date()
        
        // Resolve kind model for weekly
        let kindFetch = FetchDescriptor<PlanKindModel>(predicate: #Predicate { $0.key == "weekly" })
        let weeklyKind = try XCTUnwrap((try? context.fetch(kindFetch))?.first)
        let plan = PlanFactory.create(name: "Journey Plan", kind: weeklyKind, start: startDate, in: context)
        
        plan.days.first?.chosenExercises.append(exercise.name)
        
        try context.save()
        XCTAssertTrue(plan.days.first?.chosenExercises.contains(exercise.name) == true)
    }
    
    func testCompleteLoggingJourney() throws {
        // Plans → Select Plan → Select Day → Log Exercises (model-level)
        let plan = createTestPlan(name: "Logging Plan", kindKey: "weekly", start: Date())
        let planDay = try XCTUnwrap(plan.days.first)
        planDay.chosenExercises.append(contentsOf: ["Push-ups", "Pull-ups", "Squats"])
        
        let session = createTestSession(date: planDay.date)
        for name in planDay.chosenExercises {
            session.items.append(SessionItem(
                exerciseName: name,
                planSourceId: plan.id,
                planName: plan.name,
                reps: 10,
                sets: 3
            ))
        }
        
        try context.save()
        
        XCTAssertEqual(session.items.count, 3)
        XCTAssertTrue(session.items.allSatisfy { $0.planSourceId == plan.id })
    }
    
    // create a plan with a day and chosen exercises, log them all in a session
    // delete one logged item the same way the UI does (remove from array, delete child, save)
    // verify count is N-1 and the removed child no longer exists
    func testDeleteOneLoggedItemReducesCount() throws {
        // Arrange: create a plan with a day and chosen exercises
        let date = Calendar.current.startOfDay(for: Date())
        
        let kindFetch = FetchDescriptor<PlanKindModel>(predicate: #Predicate { $0.key == "weekly" })
        let weeklyKind = (try? context.fetch(kindFetch))?.first ?? PlanKindModel(key: "weekly", name: "Weekly", totalWeeks: nil, isRepeating: true, order: 1)
        if (try? context.fetch(kindFetch))?.first == nil { context.insert(weeklyKind) }
        
        let plan = Plan(name: "Test Plan", kind: weeklyKind, startDate: date)
        
        let dtFetch = FetchDescriptor<DayTypeModel>(predicate: #Predicate { $0.key == "climbingFull" })
        let dayType = (try? context.fetch(dtFetch))?.first ?? DayTypeModel(key: "climbingFull", name: "Climb + Hi-Vol. exercises", order: 0, colorKey: "green")
        if (try? context.fetch(dtFetch))?.first == nil { context.insert(dayType) }
        
        let day = PlanDay(date: date, type: dayType)
        
        day.chosenExercises = ["Push-ups", "Pull-ups", "Squats"]
        plan.days.append(day)
        context.insert(plan)
        try context.save()
        
        // Find or create a session for that day (startOfDay)
        let cal = Calendar.current
        let start = cal.startOfDay(for: day.date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let fetch = FetchDescriptor<Session>(predicate: #Predicate<Session> {
            $0.date >= start && $0.date < end
        })
        let session: Session
        if let existing = try context.fetch(fetch).first {
            session = existing
        } else {
            let s = Session(date: start)
            context.insert(s)
            try context.save()
            session = s
        }
        
        // Log all chosen exercises for that day
        for name in day.chosenExercises {
            let item = SessionItem(
                exerciseName: name,
                planSourceId: plan.id,
                planName: plan.name,
                reps: 10,
                sets: 3,
                weightKg: nil,
                grade: nil,
                notes: "Logged from test"
            )
            session.items.append(item)
        }
        try context.save()
        
        // Sanity check
        XCTAssertEqual(session.items.count, day.chosenExercises.count)
        
        // Act: delete one item the same way the UI does (remove from array, delete child, save)
        let removed = session.items.remove(at: 1)
        context.delete(removed)
        try context.save()
        
        // Refresh and assert: count is N-1
        let sessionID = session.id
        let refetchSession = try context.fetch(
            FetchDescriptor<Session>(predicate: #Predicate<Session> { $0.id == sessionID })
        ).first
        let countAfter = refetchSession?.items.count ?? -1
        XCTAssertEqual(countAfter, day.chosenExercises.count - 1)
        
        // And the removed child no longer exists
        let removedID = removed.id
        let removedFetch = try context.fetch(
            FetchDescriptor<SessionItem>(predicate: #Predicate<SessionItem> { $0.id == removedID })
        )
        XCTAssertTrue(removedFetch.isEmpty)
    }
    
    // MARK: - Error handling / recovery
    
    func testModelContextReinitializationSmoke() {
        // Create some data
        _ = createTestActivity(name: "Restart Test Activity")
        _ = createTestActivity(name: "Another Activity")
        try? context.save()
        
        // Recreate an in-memory container with same schema (simulated restart)
        let config = ModelConfiguration(schema: container.schema, isStoredInMemoryOnly: true)
        XCTAssertNoThrow(try ModelContainer(for: container.schema, configurations: [config]))
    }
    
    func testGracefulErrorHandling() {
        // Minimal validation: empty activity name currently allowed by model
        let invalidActivity = Activity(name: "")
        context.insert(invalidActivity)
        XCTAssertNoThrow(try context.save())
        
        // CSV export should not throw even with odd data
        XCTAssertNoThrow(LogCSV.makeExportCSV(context: context))
    }
    
    // MARK: - Seeding integration
    
    func testSeedDataIntegration() throws {
        SeedData.loadIfNeeded(context)
        
        // Catalog seeded
        let activities = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        XCTAssertFalse(activities.isEmpty)
        
        // Each training type should have exercises or combinations
        for activity in activities {
            for tt in activity.types {
                XCTAssertFalse(tt.exercises.isEmpty && tt.combinations.isEmpty, "Training type '\(tt.name)' should have exercises or combinations")
            }
        }
        
        // Climbing styles and gyms seeded
        let stylesCount = (try? context.fetchCount(FetchDescriptor<ClimbStyle>())) ?? 0
        let gymsCount = (try? context.fetchCount(FetchDescriptor<ClimbGym>())) ?? 0
        XCTAssertGreaterThan(stylesCount, 0)
        XCTAssertGreaterThan(gymsCount, 0)
        
        // Timer templates seeded
        let templatesCount = (try? context.fetchCount(FetchDescriptor<TimerTemplate>())) ?? 0
        XCTAssertGreaterThan(templatesCount, 0)
    }
    
    // MARK: - Performance
    
    func testAppPerformanceWithLargeDataset() {
        measure {
            for i in 0..<20 {
                let activity = createTestActivity(name: "Activity \(i)")
                for j in 0..<5 {
                    let tt = createTestTrainingType(activity: activity, name: "Type \(i)-\(j)")
                    for k in 0..<10 {
                        _ = createTestExercise(trainingType: tt, name: "Exercise \(i)-\(j)-\(k)")
                    }
                }
            }
            for i in 0..<50 {
                let session = createTestSession()
                session.items.append(SessionItem(exerciseName: "Exercise \(i)"))
            }
            for i in 0..<10 {
                _ = createTestPlan(name: "Plan \(i)", kindKey: "weekly", start: Date())
            }
            try? context.save()
        }
    }
}

