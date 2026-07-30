//
//  TimerTests.swift
//  klettrack Tests
//  Created by Shahar Noy on 30.09.25
//

import XCTest
import SwiftData
import SwiftUI
@testable import klettrack

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

    /// exerciseName is a new optional on TimerSession (lightweight migration);
    /// make sure it persists and that omitting it still yields nil.
    func testTimerSessionPersistsExerciseName() throws {
        let withExercise = TimerSession(planDayId: UUID(), exerciseName: "Boulder Project")
        let withoutExercise = TimerSession()
        context.insert(withExercise)
        context.insert(withoutExercise)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimerSession>())
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(fetched.first { $0.id == withExercise.id }?.exerciseName, "Boulder Project")
        XCTAssertNil(fetched.first { $0.id == withoutExercise.id }?.exerciseName)
    }
}

