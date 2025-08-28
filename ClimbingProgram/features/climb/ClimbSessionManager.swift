//
//  ClimbSessionManager.swift
//  ClimbingProgram
//
//  Created by AI Assistant on 28.08.25.
//

import Foundation
import SwiftUI
import SwiftData

/// Manages session memory for climb logging to remember type and gym within a session
@Observable
final class ClimbSessionManager {
    static let shared = ClimbSessionManager()
    
    // Session memory for current climbing session
    private(set) var lastClimbType: ClimbType?
    private(set) var lastGym: String?
    private(set) var sessionDate: Date?
    
    private init() {}
    
    /// Updates the session memory with the latest climb info
    func updateSession(climbType: ClimbType, gym: String) {
        let today = Calendar.current.startOfDay(for: Date())
        
        // If it's a new day, reset session memory
        if let sessionDate = sessionDate,
           Calendar.current.startOfDay(for: sessionDate) != today {
            resetSession()
        }
        
        lastClimbType = climbType
        lastGym = gym.isEmpty || gym == "Unknown" ? nil : gym
        sessionDate = Date()
    }
    
    /// Gets the remembered climb type for the current session, with fallback to recent climbs
    func getSessionClimbType(from modelContext: ModelContext? = nil) -> ClimbType? {
        guard isSessionValid() else {
            resetSession()
            // Try to infer from today's climbs if model context is available
            if let modelContext = modelContext {
                return inferClimbTypeFromToday(modelContext: modelContext)
            }
            return nil
        }
        return lastClimbType
    }
    
    /// Gets the remembered gym for the current session, with fallback to recent climbs
    func getSessionGym(from modelContext: ModelContext? = nil) -> String? {
        guard isSessionValid() else {
            resetSession()
            // Try to infer from today's climbs if model context is available
            if let modelContext = modelContext {
                return inferGymFromToday(modelContext: modelContext)
            }
            return nil
        }
        return lastGym
    }
    
    /// Initializes session from today's climbs if no session exists
    func initializeFromTodaysClimbs(modelContext: ModelContext) {
        guard !isSessionValid() else { return }
        
        if let recentClimbType = inferClimbTypeFromToday(modelContext: modelContext),
           let recentGym = inferGymFromToday(modelContext: modelContext) {
            lastClimbType = recentClimbType
            lastGym = recentGym
            sessionDate = Date()
        }
    }
    
    /// Infers the most common climb type from today's climbs
    private func inferClimbTypeFromToday(modelContext: ModelContext) -> ClimbType? {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        
        let descriptor = FetchDescriptor<ClimbEntry>(
            predicate: #Predicate<ClimbEntry> { climb in
                climb.dateLogged >= today && climb.dateLogged < tomorrow
            },
            sortBy: [SortDescriptor(\.dateLogged, order: .reverse)]
        )
        
        do {
            let todaysClimbs = try modelContext.fetch(descriptor)
            guard !todaysClimbs.isEmpty else { return nil }
            
            // Get the most recent climb type
            return todaysClimbs.first?.climbType
        } catch {
            print("Error fetching today's climbs: \(error)")
            return nil
        }
    }
    
    /// Infers the most common gym from today's climbs
    private func inferGymFromToday(modelContext: ModelContext) -> String? {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        
        let descriptor = FetchDescriptor<ClimbEntry>(
            predicate: #Predicate<ClimbEntry> { climb in
                climb.dateLogged >= today && climb.dateLogged < tomorrow
            },
            sortBy: [SortDescriptor(\.dateLogged, order: .reverse)]
        )
        
        do {
            let todaysClimbs = try modelContext.fetch(descriptor)
            guard !todaysClimbs.isEmpty else { return nil }
            
            // Get the most recent gym that isn't "Unknown"
            for climb in todaysClimbs {
                if climb.gym != "Unknown" && !climb.gym.isEmpty {
                    return climb.gym
                }
            }
            return nil
        } catch {
            print("Error fetching today's climbs: \(error)")
            return nil
        }
    }
    
    /// Checks if current session is still valid (same day)
    private func isSessionValid() -> Bool {
        guard let sessionDate = sessionDate else { return false }
        let today = Calendar.current.startOfDay(for: Date())
        let sessionDay = Calendar.current.startOfDay(for: sessionDate)
        return sessionDay == today
    }
    
    /// Resets the session memory
    private func resetSession() {
        lastClimbType = nil
        lastGym = nil
        sessionDate = nil
    }
    
    /// Manually clear session (for testing or user preference)
    func clearSession() {
        resetSession()
    }
}
