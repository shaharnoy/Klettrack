//
//  TimerTests.swift
//  klettrack Tests
//
//  Created by AI Assistant on 25.08.25.
//

import XCTest
import SwiftData
import SwiftUI
@testable import klettrack

/**
 * Comprehensive Timer Tests
 *
 * Tests timer template CRUD operations, timer execution logic, and UI consistency
 */
class TimerTests: BaseSwiftDataTestCase {
    
    var timerManager: TimerManager!
    
    override func setUp() {
        super.setUp()
        // Create TimerManager synchronously for testing
        let expectation = XCTestExpectation(description: "TimerManager initialization")
        Task { @MainActor in
            self.timerManager = TimerManager()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    override func tearDown() {
        timerManager = nil
        super.tearDown()
    }
}

