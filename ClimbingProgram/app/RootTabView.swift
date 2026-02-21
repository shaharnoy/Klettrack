//
//  RootTabView.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import SwiftUI
import SwiftData

// Shared timer state to ensure only one timer instance
@MainActor
@Observable
class TimerAppState {
    var selectedTab: Int = 1
    var currentPlanDay: PlanDay? = nil
    
    // Navigation path storage for each tab to preserve navigation state
    var catalogNavigationPath = NavigationPath()
    var plansNavigationPath = NavigationPath()
    var climbNavigationPath = NavigationPath()
    var logNavigationPath = NavigationPath()
    var progressNavigationPath = NavigationPath()
    var settingsNavigationPath = NavigationPath()
    
    // Reference to shared timer manager
    private let sharedTimerManager = SharedTimerManager.shared
    
    func switchToTimer(with planDay: PlanDay? = nil) {
        currentPlanDay = planDay
        selectedTab = 5 // Timer tab index
    }
    
    var isTimerActive: Bool {
        sharedTimerManager.isTimerActive
    }
}

// MARK: - Navigation Types for Plans
struct PlanNavigationItem: Hashable {
    let planId: UUID

    init(plan: Plan) {
        self.planId = plan.id
    }
}


struct PlanDayNavigationItem: Hashable {
    let planDayId: UUID
    
    init(planDayId: UUID) {
        self.planDayId = planDayId
    }
    
    init(planDay: PlanDay) {
        self.planDayId = planDay.id
    }
}

struct RootTabView: View {
    private enum SheetRoute: String, Identifiable {
        case settings
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @State private var isDataReady = false
    @State private var timerAppState = TimerAppState()
    @State private var authManager = AuthManager.shared
    @State private var sheetRoute: SheetRoute?
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            Group {
                switch timerAppState.selectedTab {
                case 0:
                    NavigationStack(path: $timerAppState.settingsNavigationPath) {
                        SettingsSheet()
                    }
                case 1:
                    NavigationStack(path: $timerAppState.climbNavigationPath) {
                        ClimbView()
                    }
                    // Ensure ModelContext has a working UndoManager for the Climb tab
                    .attachUndoManager()
                case 2:
                    NavigationStack(path: $timerAppState.plansNavigationPath) {
                        PlansListView()
                    }
                case 3:
                    NavigationStack(path: $timerAppState.logNavigationPath) {
                        LogView()
                    }
                case 4:
                    NavigationStack(path: $timerAppState.progressNavigationPath) {
                        ProgressViewScreen()
                    }
                case 5:
                    TimerView(planDay: timerAppState.currentPlanDay)
                default:
                    NavigationStack(path: $timerAppState.catalogNavigationPath) {
                        ClimbView()
                    }
                }
            }
            
            // Custom tab bar with Settings button
            CustomTabBar(selectedTab: $timerAppState.selectedTab, onSettingsTapped: {
                sheetRoute = .settings
            })
        }
        // Inject shared environment once for the whole subtree
        .environment(\.isDataReady, isDataReady)
        .environment(timerAppState)
        .task {
            await initializeData()
            //SeedData.nukeAndReseed(context) // Uncomment this line to reset data during development
            //SeedTimerTemplates.nukeAndReseed(context) // Uncomment this line to reset data during development
            //SeedClimbingData.nukeAndReseed(context) // Uncomment this line to reset data during development
        }
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .settings:
                SettingsSheet()
            }
        }
    }
    
    @MainActor
    private func initializeData() async {
        defer {
            // Ensure isDataReady is always set to true, even if there are errors
            isDataReady = true
        }
        
        do {
            // Longer delay to ensure SwiftData container is fully ready
            try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

            //runDayTypesRepairIfNeeded(context)  // delete duplicate days and reseed
            SeedData.loadIfNeeded(context)      // Always seed - logic in place to not overwrite existing data
            
        
            runOnce(per: "session_item_sort_backfill_2025-10-20") {
                backfillSessionItemSort(context)
            }
            runOnce(per: "plan_day_exercise_order_backfill_2025-10-20") {
                let days = (try? context.fetch(FetchDescriptor<PlanDay>())) ?? []
                for d in days {
                    // Only set if missing to preserve any existing manual order
                    if d.exerciseOrder.isEmpty {
                        for (idx, name) in d.chosenExercises.enumerated() {
                            d.exerciseOrder[name] = idx
                        }
                    }
                }
            }
            runOnce(per: "plan_day_sync_id_backfill_2026-02-10") {
                backfillPlanDaySyncFields(context)
            }
            runOnce(per: "sync_v2_relationship_backfill_2026-02-14") {
                backfillSyncV2RelationshipsAndMetadata(context)
            }
            runOnce(per: "daytypedefaultflags_backfill_2025-11-08") {
                backfillDefaultFlags(context)
            }
            runOnce(per: "isPreviouslyClimbed_backfill_2025-11-09") {
                backfillIsWorkInProgressIfNeeded(context)
            }
            
            //run migration to backfill "previously climbed" using the new rule (uuid + angle + prior non-WIP)
            runOnce(per: "tb2_backfill_previously_climbed_v2_2026-01-07") {
                backfillPreviouslyClimbedFlags(context)
            }
            
            runOnce(per: "catalog_remove_bouldering_se_combos_v1_2026-01-08") {
                removeLegacyBoulderingSECombos(context)
            }

            // Ensure all changes are committed
            try context.save()

            authManager.configureIfNeeded(modelContainer: context.container)
            await authManager.restoreSession()
            
            // Additional delay to ensure everything is settled
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            
        } catch {
            print("Error during data initialization: \(error)")
            // Don't prevent the app from continuing even if there's an error
        }
    }
}

func runDayTypesRepairIfNeeded(_ context: ModelContext) {
    //Delete all DayTypeModel rows
    try? context.delete(model: DayTypeModel.self)
    try? context.save()
    seedDayTypes(context)
}

// MARK: - Environment Key for Data Ready State
private struct DataReadyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isDataReady: Bool {
        get { self[DataReadyKey.self] }
        set { self[DataReadyKey.self] = newValue }
    }
}

// MARK: - Migration of sorted session items
private func backfillSessionItemSort(_ context: ModelContext) {
    do {
        let sessions = try context.fetch(FetchDescriptor<Session>())
        for session in sessions {
            // Use current array order as the canonical order.
            // Always normalize to contiguous 0...N-1 to avoid duplicates/gaps.
            let items = session.items
            for (idx, item) in items.enumerated() where item.sort != idx {
                item.sort = idx
            }
        }
        // Save is handled by initializeData();
    } catch {
        print("backfillSessionItemSort failed: \(error.localizedDescription)")
    }
}
//one time migration to add isDefault flags to existing day types
func backfillDefaultFlags(_ context: ModelContext) {
    let seedKeys: Set<String> = [
        "climbingFull","climbingSmall","climbingReduced","Perclimbing",
        "core","antagonist","rest","vacation","sick"
    ]

    let all: [DayTypeModel] = (try? context.fetch(FetchDescriptor<DayTypeModel>())) ?? []
    var touched = 0
    for d in all where seedKeys.contains(d.key) && d.isdefault == false {
        d.isdefault = true
        touched += 1
    }
    if touched > 0 { try? context.save() }
}
//migration to move isPreviouslyClimbed to non-optional with default false
  func backfillIsWorkInProgressIfNeeded(_ context: ModelContext) {
      do {
          let descriptor = FetchDescriptor<ClimbEntry>()
          let entries = try context.fetch(descriptor)
          var updatedCount = 0
          for entry in entries {
              if entry.isPreviouslyClimbed == false {
                  continue
              }
              updatedCount += 1
          }
          if updatedCount > 0 {
              try context.save()
              print("Backfilled \(updatedCount) ClimbEntry records with isPreviouslyClimbed = false")
          } else {
              print("No missing isPreviouslyClimbed values found — migration not needed")
          }
      } catch {
          print("backfillIsWorkInProgressIfNeeded failed: \(error.localizedDescription)")
      }
  }

//one time migration to remove legacy "Strength-Endurance" combos that are now standalone exercises
@MainActor
func removeLegacyBoulderingSECombos(_ context: ModelContext) {
    func norm(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // Names currently seeded as combos in SeedData.swift (and their older legacy placeholders)
    let legacyNames: Set<String> = Set([
        "Classic 4X4",
        "Big moves 4×4s",
        "Board 3×6 combo",
        "Combination 1",
        "Combination 2",
        "Combination 4",
    ].map(norm))

    do {
        // 1) Detach from any TrainingType.combinations (safe even if SwiftData would cascade)
        let allTypes: [TrainingType] = try context.fetch(FetchDescriptor<TrainingType>())
        var detached = 0
        for t in allTypes {
            let before = t.combinations.count
            t.combinations.removeAll { legacyNames.contains(norm($0.name)) }
            detached += (before - t.combinations.count)
        }

        // 2) Hard-delete the combinations
        let allCombos: [BoulderCombination] = try context.fetch(FetchDescriptor<BoulderCombination>())
        let toDelete = allCombos.filter { legacyNames.contains(norm($0.name)) }

        toDelete.forEach { context.delete($0) }

        if detached > 0 || !toDelete.isEmpty {
            try? context.save()
            print("Removed legacy bouldering SE combos: deleted=\(toDelete.count), detached=\(detached)")
        }
    } catch {
        print("removeLegacyBoulderingSECombos failed: \(error.localizedDescription)")
    }
}


//one time migration to backfill isPreviouslyClimbed based on:
// - same tb2ClimbUUID
// - same angleDegrees
// - only counts if there was a prior non-WIP entry (i.e. a real ascent)
// WIP entries can still become isPreviouslyClimbed=true if there was a prior ascent.
@MainActor
func backfillPreviouslyClimbedFlags(_ context: ModelContext) {
    struct Key: Hashable {
        let uuid: String
        let angle: Int?
    }

    do {
        // Process chronologically so "prior" is meaningful
        let descriptor = FetchDescriptor<ClimbEntry>(
            predicate: #Predicate { $0.tb2ClimbUUID != nil },
            sortBy: [SortDescriptor(\ClimbEntry.dateLogged)]
        )
        let entries = try context.fetch(descriptor)
        guard !entries.isEmpty else { return }

        var completedSeen = Set<Key>()
        var changed = 0

        for e in entries {
            guard let uuid = e.tb2ClimbUUID else { continue }
            let key = Key(uuid: uuid, angle: e.angleDegrees)

            // Previously climbed iff we've seen a prior completed ascent for this (uuid, angle)
            let shouldBePreviously = completedSeen.contains(key)
            if e.isPreviouslyClimbed != shouldBePreviously {
                e.isPreviouslyClimbed = shouldBePreviously
                changed += 1
            }

            // Only a non-WIP row counts as a completed climb for future entries
            if e.isWorkInProgress == false {
                completedSeen.insert(key)
            }
        }

        if changed > 0 {
            // You already save in initializeData(), but saving here is fine & keeps this migration self-contained.
            try? context.save()
            print("Backfilled isPreviouslyClimbed for \(changed) ClimbEntry rows (uuid+angle, prior non-WIP).")
        } else {
            print("No isPreviouslyClimbed changes needed.")
        }
    } catch {
        print("backfillPreviouslyClimbedFlags failed: \(error.localizedDescription)")
    }
}
