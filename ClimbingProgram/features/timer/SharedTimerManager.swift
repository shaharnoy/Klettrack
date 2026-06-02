//
//  SharedTimerManager.swift
//  Klettrack
//  Created by Shahar Noy on 28.08.25.
//

import Foundation
import SwiftUI

// Global shared timer manager to persist across app lifecycle
@MainActor
@Observable
class SharedTimerManager {
    static let shared = SharedTimerManager()
    
    var timerManager = TimerManager()
    
    private init() {
    }

    var isTimerActive: Bool {
        timerManager.state == .running || timerManager.state == .paused
    }
}
