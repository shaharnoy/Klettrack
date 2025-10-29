//
//  RootTabView.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import SwiftUI
import SwiftData
import Combine

// Shared timer state to ensure only one timer instance
@MainActor
class TimerAppState: ObservableObject {
    @Published var selectedTab: Int = 1
    @Published var currentPlanDay: PlanDay? = nil
    
    // Navigation path storage for each tab to preserve navigation state
    @Published var catalogNavigationPath = NavigationPath()
    @Published var plansNavigationPath = NavigationPath()
    @Published var climbNavigationPath = NavigationPath()
    @Published var logNavigationPath = NavigationPath()
    @Published var progressNavigationPath = NavigationPath()
    @Published var settingsNavigationPath = NavigationPath()
    
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
    
    init(planId: UUID) {
        self.planId = planId
    }
    
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
    @Environment(\.modelContext) private var context
    @State private var isDataReady = false
    @StateObject private var timerAppState = TimerAppState()
    @State private var showingSettings = false
    
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
                showingSettings = true
            })
        }
        // Inject shared environment once for the whole subtree
        .environment(\.isDataReady, isDataReady)
        .environmentObject(timerAppState)
        .task {
            await initializeData()
            //SeedData.nukeAndReseed(context) // Uncomment this line to reset data during development
            //SeedTimerTemplates.nukeAndReseed(context) // Uncomment this line to reset data during development
            //SeedClimbingData.nukeAndReseed(context) // Uncomment this line to reset data during development
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet()
                .environmentObject(timerAppState)
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

            //runDayTypesRepairIfNeeded(context)  // delete duplicates, reseed
            //SeedData.loadIfNeeded(context)      // after repair, reseed
            
            // Seed timer templates 
            SeedTimerTemplates.loadIfNeeded(context)
            
            // Non-destructive catalog deltas migration (run once per key)
            runOnce(per: "catalog_2025-10-11_bouldering") {
                applyCatalogUpdates(context)
            }
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
            // Ensure all changes are committed
            try context.save()
            
            // Additional delay to ensure everything is settled
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            
        } catch {
            print("Error during data initialization: \(error)")
            // Don't prevent the app from continuing even if there's an error
        }
    }
}

// MARK: - Environment Key for Data Ready State
func runDayTypesRepairIfNeeded(_ context: ModelContext) {
    // 1) Delete all DayTypeModel rows
    try? context.delete(model: DayTypeModel.self)
    try? context.save()

    // 2) Reseed just the day types
    seedDayTypes(context)
}
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
        // Save is handled by initializeData(); keep this idempotent.
    } catch {
        print("⚠️ backfillSessionItemSort failed: \(error.localizedDescription)")
    }
}
