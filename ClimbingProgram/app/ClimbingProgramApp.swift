//
//  ClimbingProgramApp.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import SwiftUI
import SwiftData

@main
struct ClimbingProgramApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var authManager = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .onAppear {
                    // Seeding happens when the view appears with proper context
                }
        }
        .backgroundTask(.appRefresh(SyncBackgroundRefresh.taskIdentifier)) {
            await authManager.handleBackgroundRefreshTask()
            SyncBackgroundRefreshScheduler.scheduleNextRefresh()
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            switch newPhase {
            case .active:
                SyncBackgroundRefreshScheduler.scheduleNextRefresh()
                Task { await authManager.handleAppDidBecomeActive() }
            case .background:
                SyncBackgroundRefreshScheduler.scheduleNextRefresh()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .modelContainer(for: [
            Activity.self, TrainingType.self, Exercise.self,
            SyncState.self, SyncMutation.self,
            Session.self, SessionItem.self,
            Plan.self, PlanDay.self,
            TimerTemplate.self, TimerInterval.self, TimerSession.self, TimerLap.self,
            ClimbEntry.self, ClimbStyle.self, ClimbGym.self, ClimbMedia.self
        ])
    }
}
