//
//  SharedTimerManager.swift
//  Klettrack
//  Created by Shahar Noy on 28.08.25.
//

import Foundation
import SwiftUI
import Combine

// Global shared timer manager to persist across app lifecycle
@MainActor
class SharedTimerManager: ObservableObject {
    static let shared = SharedTimerManager()
    
    @Published var timerManager = TimerManager()
    @Published var isTimerActive: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupTimerObservation()
    }
    
    private func setupTimerObservation() {
        // Monitor timer state changes
        timerManager.$state
            .map { $0 == .running || $0 == .paused }
            .receive(on: DispatchQueue.main)
            .assign(to: \.isTimerActive, on: self)
            .store(in: &cancellables)
        
        // Forward all timer manager property changes to trigger UI updates
        timerManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
