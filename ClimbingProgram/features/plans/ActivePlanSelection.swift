//
//  ActivePlanSelection.swift
//  Klettrack
//

import SwiftUI
import SwiftData

enum ActivePlanPreference {
    static let userDefaultsKey = "klettrack.activePlanID"
    static let optedOutKey = "klettrack.activePlanOptedOut"

    static func planID(from defaults: UserDefaults = .standard) -> UUID? {
        guard let rawValue = defaults.string(forKey: userDefaultsKey) else { return nil }
        return UUID(uuidString: rawValue)
    }

    static func save(planID: UUID, to defaults: UserDefaults = .standard) {
        defaults.set(planID.uuidString, forKey: userDefaultsKey)
        defaults.set(false, forKey: optedOutKey)
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsKey)
    }

    static func isOptedOut(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: optedOutKey)
    }

    static func setOptedOut(_ optedOut: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(optedOut, forKey: optedOutKey)
    }
}

struct ActivePlanResolver {
    enum Resolution: Equatable {
        case active(UUID)
        case choose
        case none
    }

    static func resolve(
        plans: [Plan],
        storedPlanID: UUID?,
        isOptedOut: Bool = false,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> Resolution {
        if isOptedOut {
            return .none
        }

        if let storedPlanID, plans.contains(where: { $0.id == storedPlanID }) {
            return .active(storedPlanID)
        }

        let matchingPlanIDs = plans
            .filter { plan in
                plan.days.contains { calendar.isDate($0.date, inSameDayAs: today) }
            }
            .map(\.id)

        switch matchingPlanIDs.count {
        case 0:
            return .none
        case 1:
            return .active(matchingPlanIDs[0])
        default:
            return .choose
        }
    }
}

struct ActivePlanSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor<Plan>(\.startDate, order: .reverse)]) private var plans: [Plan]

    let initialSelectionID: UUID?
    let onSelectionComplete: (UUID?) -> Void

    @State private var selectedPlanID: UUID?
    @State private var showingNotInterestedConfirmation = false

    init(
        initialSelectionID: UUID? = nil,
        onSelectionComplete: @escaping (UUID?) -> Void
    ) {
        self.initialSelectionID = initialSelectionID
        self.onSelectionComplete = onSelectionComplete
        _selectedPlanID = State(initialValue: initialSelectionID)
    }

    var body: some View {
        List {
            if plans.isEmpty {
                ContentUnavailableView(
                    "No Plans",
                    systemImage: "calendar.badge.plus",
                    description: Text("Create a plan before selecting an active plan.")
                )
            } else {
                Section {
                    ForEach(plans) { plan in
                        Button {
                            selectedPlanID = plan.id
                        } label: {
                            HStack(spacing: 12) {
                                PlanRow(plan: plan, isActive: selectedPlanID == plan.id)
                                Spacer()
                                if selectedPlanID == plan.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .accessibilityLabel("Selected active plan")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Choose your current active plan")
                }

                Section {
                    HStack {
                        Spacer()
                        Button("Not interested") {
                            showingNotInterestedConfirmation = true
                        }
                        .foregroundStyle(.blue.opacity(0.8))
                        Spacer()
                    }
                } footer: {
                    Text("You can set a plan as active at any time using the ")
                    + Text(Image(systemName: "bolt.badge.clock.fill"))
                    + Text(" button.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    guard let selectedPlanID else { return }
                    ActivePlanPreference.save(planID: selectedPlanID)
                    onSelectionComplete(selectedPlanID)
                    dismiss()
                }
                .disabled(selectedPlanID == nil)
            }
        }
        .task {
            guard selectedPlanID == nil,
                  let storedPlanID = ActivePlanPreference.planID(),
                  plans.contains(where: { $0.id == storedPlanID }) else { return }
            selectedPlanID = storedPlanID
        }
        .alert("Continue without an active plan?", isPresented: $showingNotInterestedConfirmation) {
            Button("Understood", role: .destructive) {
                ActivePlanPreference.clear()
                ActivePlanPreference.setOptedOut(true)
                onSelectionComplete(nil)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your plans will continue to work as before. The Plans module will now show all your plans instead of opening the active plan by default")
        }
    }
}
