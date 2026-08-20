import XCTest
@testable import klettrack

final class ActivePlanResolverTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func plan(
        id: UUID = UUID(),
        days: [Date]
    ) -> Plan {
        let plan = Plan(id: id, name: "Plan", kind: nil, startDate: days[0])
        plan.days = days.map { PlanDay(date: $0) }
        return plan
    }

    func testExactlyOnePlanContainingTodayIsSelected() {
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
        let matching = plan(days: [today])
        let other = plan(days: [today.addingTimeInterval(86_400)])

        let result = ActivePlanResolver.resolve(
            plans: [matching, other],
            storedPlanID: nil,
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(result, .active(matching.id))
    }

    func testMultiplePlansContainingTodayRequireSelectionFromAllPlans() {
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
        let first = plan(days: [today])
        let second = plan(days: [today])
        let future = plan(days: [today.addingTimeInterval(86_400)])

        let result = ActivePlanResolver.resolve(
            plans: [first, second, future],
            storedPlanID: nil,
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(result, .choose)
        XCTAssertEqual(Set([first.id, second.id, future.id]).count, 3)
    }

    func testNoPlanContainingTodayFallsBackToNone() {
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
        let plan = plan(days: [today.addingTimeInterval(86_400)])

        let result = ActivePlanResolver.resolve(
            plans: [plan],
            storedPlanID: nil,
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(result, .none)
    }

    func testOptedOutStatePreventsAutomaticSelection() {
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
        let matching = plan(days: [today])

        let result = ActivePlanResolver.resolve(
            plans: [matching],
            storedPlanID: nil,
            isOptedOut: true,
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(result, .none)
    }

    func testValidPersistedSelectionOverridesDateMatching() {
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
        let automatic = plan(days: [today])
        let persisted = plan(days: [today.addingTimeInterval(86_400)])

        let result = ActivePlanResolver.resolve(
            plans: [automatic, persisted],
            storedPlanID: persisted.id,
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(result, .active(persisted.id))
    }

    func testDeletedPersistedSelectionIsReResolved() {
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
        let replacement = plan(days: [today])

        let result = ActivePlanResolver.resolve(
            plans: [replacement],
            storedPlanID: UUID(),
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(result, .active(replacement.id))
    }

    func testActivePlanPreferencePersistsAndClearsSelection() {
        let suiteName = "ActivePlanResolverTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let id = UUID()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        ActivePlanPreference.save(planID: id, to: defaults)
        XCTAssertEqual(ActivePlanPreference.planID(from: defaults), id)

        ActivePlanPreference.setOptedOut(true, in: defaults)
        ActivePlanPreference.save(planID: id, to: defaults)
        XCTAssertFalse(ActivePlanPreference.isOptedOut(from: defaults))

        ActivePlanPreference.clear(from: defaults)
        XCTAssertNil(ActivePlanPreference.planID(from: defaults))
    }
}
