//
//  ClimbingProgramApp.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import SwiftUI
import SwiftData

@main
struct ClimbingProgramApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .onAppear {
                    // Seeding happens when the view appears with proper context
                }
        }
        .modelContainer(for: [
            Activity.self, TrainingType.self, Exercise.self,
            Session.self, SessionItem.self,
            Plan.self, PlanDay.self,
            TimerTemplate.self, TimerInterval.self, TimerSession.self, TimerLap.self,
            ClimbEntry.self, ClimbStyle.self, ClimbGym.self
        ])
    }
}
