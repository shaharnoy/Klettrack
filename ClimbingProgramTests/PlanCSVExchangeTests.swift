import XCTest
import SwiftData
@testable import klettrack

@MainActor
final class PlanCSVExchangeTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema([
            Activity.self, TrainingType.self, BoulderCombination.self, Exercise.self,
            Plan.self, PlanDay.self, PlanKindModel.self, DayTypeModel.self, PlanExerciseDefinition.self,
            Session.self, SessionItem.self, DayLog.self, DayTag.self,
            ClimbEntry.self, ClimbStyle.self, ClimbGym.self, ClimbMedia.self,
            TB2ClimbMetadata.self, TB2ClimbStatsMetadata.self
        ])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    override func tearDownWithError() throws {
        container = nil
    }

    func testExportRoundTripIncludesEmptyDaysAndPlanFields() throws {
        let kind = PlanKindModel(key: "weekly", name: "Weekly", isRepeating: true)
        let type = DayTypeModel(key: "strength", name: "Strength", colorKey: "purple")
        context.insert(kind)
        context.insert(type)

        let plan = Plan(name: "Exchange Plan", kind: kind, startDate: Date(timeIntervalSince1970: 1_700_000_000))
        let firstDay = PlanDay(date: plan.startDate, type: type)
        firstDay.dailyNotes = "Keep quality high"
        firstDay.chosenExercises = ["Imported Drill"]
        let emptyDay = PlanDay(date: Calendar.current.date(byAdding: .day, value: 1, to: plan.startDate) ?? plan.startDate, type: type)
        plan.days = [firstDay, emptyDay]
        context.insert(plan)
        try context.save()

        let csv = PlanCSVExchange.export(plan: plan, in: context).csv
        let parsed = try PlanCSVExchange.parse(csv)

        XCTAssertTrue(csv.contains("row_type"))
        XCTAssertEqual(parsed.plan.name, "Exchange Plan")
        XCTAssertEqual(parsed.days.count, 2)
        XCTAssertEqual(parsed.exercises.count, 1)
        XCTAssertEqual(parsed.exercises.first?.name, "Imported Drill")
    }

    func testParseAcceptsUTF8ByteOrderMarkAndCRLFLineEndings() throws {
        let plan = Plan(name: "BOM Plan", kind: nil, startDate: Date())
        context.insert(plan)
        try context.save()

        let csv = "\u{FEFF}" + PlanCSVExchange.export(plan: plan, in: context).csv
            .replacingOccurrences(of: "\n", with: "\r\n")
        let parsed = try PlanCSVExchange.parse(csv)

        XCTAssertEqual(parsed.plan.name, "BOM Plan")
    }

    func testImportGeneratesPlanIDWhenPlanIDIsMissing() throws {
        let source = Plan(name: "External Plan", kind: nil, startDate: Date())
        context.insert(source)
        try context.save()

        let csv = PlanCSVExchange.export(plan: source, in: context).csv
            .replacingOccurrences(of: "plan,\(source.id.uuidString),", with: "plan,,")
        let parsed = try PlanCSVExchange.parse(csv)

        XCTAssertNotEqual(parsed.plan.id, source.id)
        XCTAssertTrue(parsed.warnings.contains { $0.localizedStandardContains("new ID") })

        _ = try PlanCSVExchange.apply(parsed, mode: .newPlan, in: context)
        let plans = try context.fetch(FetchDescriptor<Plan>())
        XCTAssertTrue(plans.contains { $0.id == parsed.plan.id && $0.name == "External Plan" })
    }

    func testPlanExportFilenameUsesSanitizedPlanNameAndDate() {
        let plan = Plan(name: "My Plan / Strength", kind: nil, startDate: Date())
        let filename = PlanCSVExchange.exportFilename(
            for: plan,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertNotNil(filename.range(of: #"^klettrack_My_Plan_Strength_\d{4}-\d{2}-\d{2}$"#, options: .regularExpression))
    }

    func testImportNewPlanBackfillsMissingExerciseUnderImportedCatalog() throws {
        let source = Plan(name: "Imported Plan", kind: nil, startDate: Date())
        let day = PlanDay(date: source.startDate)
        day.chosenExercises = ["New Outside Exercise"]
        source.days = [day]
        context.insert(source)
        try context.save()

        let parsed = try PlanCSVExchange.parse(PlanCSVExchange.export(plan: source, in: context).csv)
        let summary = try PlanCSVExchange.apply(parsed, mode: .newPlan, in: context)

        XCTAssertEqual(summary.planName, "Imported Plan")
        let activities = try context.fetch(FetchDescriptor<Activity>())
        let imported = try XCTUnwrap(activities.first { $0.name == "Imported" })
        let importedType = try XCTUnwrap(imported.types.first { $0.name == "Imported Plans" })
        XCTAssertEqual(importedType.exercises.map(\.name), ["New Outside Exercise"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Plan>()).count, 2)
    }

    func testExistingImportPreservesLoggedItemAndRemovesUnloggedDay() throws {
        let plan = Plan(name: "Existing", kind: nil, startDate: Date())
        let loggedDay = PlanDay(date: plan.startDate)
        loggedDay.chosenExercises = ["Logged Exercise"]
        let unloggedDay = PlanDay(date: Calendar.current.date(byAdding: .day, value: 1, to: plan.startDate) ?? plan.startDate)
        unloggedDay.chosenExercises = ["Remove Me"]
        plan.days = [loggedDay, unloggedDay]
        context.insert(plan)

        let session = Session(date: plan.startDate)
        let item = SessionItem(exerciseName: "Logged Exercise", planSourceId: plan.id, planName: plan.name, planDayId: loggedDay.id, reps: 5, notes: "Original")
        session.items = [item]
        context.insert(session)
        try context.save()

        var edited = try PlanCSVExchange.parse(PlanCSVExchange.export(plan: plan, in: context).csv)
        edited.days.removeAll { Calendar.current.isDate($0.date, inSameDayAs: unloggedDay.date) }
        edited.plan.name = "Edited Existing"

        _ = try PlanCSVExchange.apply(edited, mode: .existing(plan), in: context)

        XCTAssertEqual(item.reps, 5)
        XCTAssertEqual(item.notes, "Original")
        XCTAssertTrue(plan.days.contains { $0.id == loggedDay.id })
        XCTAssertFalse(plan.days.contains { $0.id == unloggedDay.id })
        XCTAssertEqual(plan.name, "Edited Existing")
    }

    func testExistingImportAppliesScheduleMetadataAroundProtectedRecords() throws {
        let plan = Plan(name: "Existing", kind: nil, startDate: Date())
        let day = PlanDay(date: plan.startDate)
        day.chosenExercises = ["Logged Exercise", "Remove Me"]
        plan.days = [day]
        context.insert(plan)

        let session = Session(date: plan.startDate)
        let loggedItem = SessionItem(
            exerciseName: "Logged Exercise",
            planSourceId: plan.id,
            planName: plan.name,
            planDayId: day.id,
            reps: 5,
            notes: "Original"
        )
        session.items = [loggedItem]
        context.insert(session)
        try context.save()

        var edited = try PlanCSVExchange.parse(PlanCSVExchange.export(plan: plan, in: context).csv)
        let loggedID = try XCTUnwrap(edited.exercises.first { $0.name == "Logged Exercise" }?.id)
        let newID = UUID()
        edited.exercises.append(.init(id: newID, catalogID: nil, name: "New Exercise", area: nil, description: nil, reps: nil, sets: nil, duration: nil, rest: nil, notes: nil))
        edited.days[0].dayTypeKey = "updated"
        edited.days[0].dayTypeName = "Updated"
        edited.days[0].dayTypeColor = "purple"
        edited.days[0].dailyNotes = "Updated notes"
        edited.days[0].exerciseRefs = [(newID, 0), (loggedID, 1)]

        _ = try PlanCSVExchange.apply(edited, mode: .existing(plan), in: context)

        XCTAssertEqual(day.type?.key, "updated")
        XCTAssertEqual(day.dailyNotes, "Updated notes")
        XCTAssertEqual(day.chosenExercises, ["New Exercise", "Logged Exercise"])
        XCTAssertEqual(day.exerciseOrder["New Exercise"], 0)
        XCTAssertEqual(day.exerciseOrder["Logged Exercise"], 1)
        XCTAssertEqual(loggedItem.reps, 5)
        XCTAssertEqual(loggedItem.notes, "Original")
    }

    func testExistingImportCanOverwriteDayContextByExplicitChoice() throws {
        let plan = Plan(name: "Context Plan", kind: nil, startDate: Date())
        plan.days = [PlanDay(date: plan.startDate)]
        context.insert(plan)
        let dayLog = try XCTUnwrap(DayLogStore.dayLog(for: plan.startDate, in: context))
        DayLogStore.setNote("Original context", for: dayLog)
        let originalTag = try XCTUnwrap(DayLogStore.createTag(name: "Original", colorKey: "red", in: context))
        DayLogStore.setTag(originalTag, assigned: true, to: dayLog)
        try context.save()

        var edited = try PlanCSVExchange.parse(PlanCSVExchange.export(plan: plan, in: context).csv)
        edited.contexts[0].note = "CSV context"
        edited.contexts[0].tags = [.init(name: "CSV", colorKey: "blue")]

        _ = try PlanCSVExchange.apply(edited, mode: .existing(plan), in: context)
        XCTAssertEqual(dayLog.note, "Original context")
        XCTAssertEqual(DayLogStore.activeTags(from: dayLog).map(\.name), ["Original"])

        _ = try PlanCSVExchange.apply(edited, mode: .existing(plan), overwriteDayContext: true, in: context)
        XCTAssertEqual(dayLog.note, "CSV context")
        XCTAssertEqual(DayLogStore.activeTags(from: dayLog).map(\.name), ["CSV"])
    }

    func testRepeatedImportDoesNotDuplicateLogs() throws {
        let source = Plan(name: "Repeatable", kind: nil, startDate: Date())
        let day = PlanDay(date: source.startDate)
        day.chosenExercises = ["Exercise"]
        source.days = [day]
        context.insert(source)
        let session = Session(date: source.startDate)
        session.items = [SessionItem(exerciseName: "Exercise", planSourceId: source.id, planName: source.name, planDayId: day.id)]
        context.insert(session)
        try context.save()

        let parsed = try PlanCSVExchange.parse(PlanCSVExchange.export(plan: source, in: context).csv)
        let first = try PlanCSVExchange.apply(parsed, mode: .existing(source), in: context)
        let second = try PlanCSVExchange.apply(parsed, mode: .existing(source), in: context)

        XCTAssertEqual(first.logCount, 0)
        XCTAssertEqual(second.logCount, 0)
        XCTAssertEqual(session.items.count, 1)
    }

    func testImportedExerciseMovePreservesIdentity() throws {
        let importedActivity = Activity(name: "Imported")
        let importedType = TrainingType(name: "Imported Plans")
        let exercise = Exercise(name: "Move Me")
        importedType.exercises.append(exercise)
        importedActivity.types.append(importedType)

        let destinationActivity = Activity(name: "Strength")
        let destinationType = TrainingType(name: "Pull")
        destinationActivity.types.append(destinationType)
        context.insert(importedActivity)
        context.insert(destinationActivity)
        context.insert(exercise)
        try context.save()

        let destination = try XCTUnwrap(CatalogReassignment.destinations(in: context).first { $0.type.id == destinationType.id })
        let originalID = exercise.id
        try CatalogReassignment.move(exercise, from: importedType, sourceCombination: nil, to: destination, in: context)

        XCTAssertEqual(exercise.id, originalID)
        XCTAssertFalse(importedType.exercises.contains { $0.id == originalID })
        XCTAssertTrue(destinationType.exercises.contains { $0.id == originalID })
        XCTAssertNil(try context.fetch(FetchDescriptor<Activity>()).first { $0.id == importedActivity.id })
        XCTAssertNil(try context.fetch(FetchDescriptor<TrainingType>()).first { $0.id == importedType.id })
    }

    func testNonEmptyNodeRequiresConfirmationBeforeDeletion() throws {
        let activity = Activity(name: "Imported")
        let type = TrainingType(name: "Imported Plans")
        let exercise = Exercise(name: "Keep Until Confirmed")
        type.exercises.append(exercise)
        activity.types.append(type)
        context.insert(activity)
        context.insert(type)
        context.insert(exercise)
        try context.save()

        let request = CatalogDeletion.request(for: .activity(activity), in: context)
        XCTAssertFalse(request.impact.isEmpty)
        XCTAssertEqual(type.exercises.count, 1)

        try CatalogDeletion.delete(request, in: context)

        XCTAssertNil(try context.fetch(FetchDescriptor<Activity>()).first { $0.id == activity.id })
        XCTAssertNil(try context.fetch(FetchDescriptor<Exercise>()).first { $0.id == exercise.id })
    }

    func testBulkMovePreservesAllExerciseIdentitiesAndCleansImportedContainers() throws {
        let importedActivity = Activity(name: "Imported")
        let importedType = TrainingType(name: "Imported Plans")
        let firstExercise = Exercise(name: "Bulk One")
        let secondExercise = Exercise(name: "Bulk Two")
        importedType.exercises = [firstExercise, secondExercise]
        importedActivity.types.append(importedType)

        let destinationActivity = Activity(name: "Core")
        let destinationType = TrainingType(name: "Anterior Core")
        destinationActivity.types.append(destinationType)
        context.insert(importedActivity)
        context.insert(importedType)
        context.insert(firstExercise)
        context.insert(secondExercise)
        context.insert(destinationActivity)
        context.insert(destinationType)
        try context.save()

        let destination = try XCTUnwrap(CatalogReassignment.destinations(in: context).first { $0.type.id == destinationType.id })
        let originalIDs = Set([firstExercise.id, secondExercise.id])
        try CatalogReassignment.move(
            [firstExercise, secondExercise],
            from: importedType,
            sourceCombination: nil,
            to: destination,
            in: context
        )

        XCTAssertEqual(Set(destinationType.exercises.map(\.id)), originalIDs)
        XCTAssertTrue(importedType.exercises.isEmpty)
        XCTAssertNil(try context.fetch(FetchDescriptor<Activity>()).first { $0.id == importedActivity.id })
    }

    func testEmptyCatalogNodesDeleteWithoutChildData() throws {
        let emptyActivity = Activity(name: "Empty Activity")
        let typeActivity = Activity(name: "Type Activity")
        let emptyType = TrainingType(name: "Empty Type")
        typeActivity.types.append(emptyType)

        let combinationActivity = Activity(name: "Combination Activity")
        let combinationType = TrainingType(name: "Combination Type")
        let emptyCombination = BoulderCombination(name: "Empty Combination")
        combinationType.combinations.append(emptyCombination)
        combinationActivity.types.append(combinationType)

        context.insert(emptyActivity)
        context.insert(typeActivity)
        context.insert(emptyType)
        context.insert(combinationActivity)
        context.insert(combinationType)
        context.insert(emptyCombination)
        try context.save()

        XCTAssertTrue(CatalogDeletion.request(for: .activity(emptyActivity), in: context).impact.isEmpty)
        XCTAssertTrue(CatalogDeletion.request(for: .trainingType(emptyType), in: context).impact.isEmpty)
        XCTAssertTrue(CatalogDeletion.request(for: .combination(emptyCombination), in: context).impact.isEmpty)

        try CatalogDeletion.delete(.activity(emptyActivity), in: context)
        try CatalogDeletion.delete(.trainingType(emptyType), in: context)
        try CatalogDeletion.delete(.combination(emptyCombination), in: context)

        XCTAssertNil(try context.fetch(FetchDescriptor<Activity>()).first { $0.id == emptyActivity.id })
        XCTAssertNil(try context.fetch(FetchDescriptor<TrainingType>()).first { $0.id == emptyType.id })
        XCTAssertNil(try context.fetch(FetchDescriptor<BoulderCombination>()).first { $0.id == emptyCombination.id })
        XCTAssertNotNil(try context.fetch(FetchDescriptor<Activity>()).first { $0.id == combinationActivity.id })
    }

    func testDeletingTrainingTypePreservesExerciseSharedByAnotherNode() throws {
        let activity = Activity(name: "Shared Activity")
        let firstType = TrainingType(name: "First")
        let secondType = TrainingType(name: "Second")
        let sharedExercise = Exercise(name: "Shared Exercise")
        firstType.exercises.append(sharedExercise)
        secondType.exercises.append(sharedExercise)
        activity.types = [firstType, secondType]
        context.insert(activity)
        context.insert(firstType)
        context.insert(secondType)
        context.insert(sharedExercise)
        try context.save()

        try CatalogDeletion.delete(.trainingType(firstType), in: context)

        XCTAssertTrue(secondType.exercises.contains { $0.id == sharedExercise.id })
        XCTAssertNotNil(try context.fetch(FetchDescriptor<Exercise>()).first { $0.id == sharedExercise.id })
        XCTAssertNil(try context.fetch(FetchDescriptor<TrainingType>()).first { $0.id == firstType.id })
    }

    func testFinalCatalogPlacementClearsPlanLinkButPreservesPlanAndLogs() throws {
        let activity = Activity(name: "Catalog Activity")
        let type = TrainingType(name: "Catalog Type")
        let exercise = Exercise(name: "Plan Exercise")
        type.exercises.append(exercise)
        activity.types.append(type)
        context.insert(activity)
        context.insert(type)
        context.insert(exercise)

        let plan = Plan(name: "Preserved Plan", kind: nil, startDate: Date())
        let day = PlanDay(date: plan.startDate)
        let definition = PlanExerciseDefinition(catalogExerciseID: exercise.id, name: exercise.name, repsText: "5", notes: "Keep guidance")
        day.chosenExercises = [exercise.name]
        day.chosenExerciseIDs = [exercise.id]
        day.planExerciseIDs = [definition.id]
        day.exerciseOrderByID = [exercise.id.uuidString: 0]
        day.exerciseOrder = [exercise.name: 0]
        plan.days = [day]
        plan.exerciseDefinitions = [definition]
        context.insert(plan)
        context.insert(day)
        context.insert(definition)

        let session = Session(date: plan.startDate)
        let item = SessionItem(exerciseName: exercise.name, planSourceId: plan.id, planDayId: day.id, planExerciseID: definition.id, reps: 5, notes: "Logged")
        session.items = [item]
        context.insert(session)

        let climb = ClimbEntry(climbType: .boulder, grade: "V3", style: "Flash", gym: "Test Gym", dateLogged: plan.startDate, planSourceId: plan.id, planDayId: day.id)
        context.insert(climb)
        try context.save()

        try CatalogDeletion.delete(.trainingType(type), in: context)

        XCTAssertEqual(plan.name, "Preserved Plan")
        XCTAssertEqual(day.chosenExercises, [exercise.name])
        XCTAssertEqual(day.planExerciseIDs, [definition.id])
        XCTAssertEqual(day.exerciseOrder, [exercise.name: 0])
        XCTAssertTrue(day.chosenExerciseIDs.isEmpty)
        XCTAssertTrue(day.exerciseOrderByID.isEmpty)
        XCTAssertNil(definition.catalogExerciseID)
        XCTAssertEqual(item.notes, "Logged")
        XCTAssertEqual(climb.grade, "V3")
        XCTAssertNil(try context.fetch(FetchDescriptor<Exercise>()).first { $0.id == exercise.id })
    }

    func testDeletingActivityRecursivelyRemovesTypesCombinationsAndExercises() throws {
        let activity = Activity(name: "Recursive Activity")
        let type = TrainingType(name: "Recursive Type")
        let combination = BoulderCombination(name: "Recursive Combination")
        let directExercise = Exercise(name: "Direct")
        let combinationExercise = Exercise(name: "Combination")
        type.exercises.append(directExercise)
        combination.exercises.append(combinationExercise)
        type.combinations.append(combination)
        activity.types.append(type)
        context.insert(activity)
        context.insert(type)
        context.insert(combination)
        context.insert(directExercise)
        context.insert(combinationExercise)
        try context.save()

        try CatalogDeletion.delete(.activity(activity), in: context)

        XCTAssertNil(try context.fetch(FetchDescriptor<Activity>()).first { $0.id == activity.id })
        XCTAssertNil(try context.fetch(FetchDescriptor<TrainingType>()).first { $0.id == type.id })
        XCTAssertNil(try context.fetch(FetchDescriptor<BoulderCombination>()).first { $0.id == combination.id })
        XCTAssertTrue(try context.fetch(FetchDescriptor<Exercise>()).isEmpty)
    }
}
