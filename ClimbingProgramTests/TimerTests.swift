//
//  TimerTests.swift
//  ClimbingProgram Tests
//
//  Created by AI Assistant on 25.08.25.
//

import XCTest
import SwiftData
import SwiftUI
@testable import ClimbingProgram

/**
 * Comprehensive Timer Tests
 *
 * Tests timer template CRUD operations, timer execution logic, and UI consistency
 */
class TimerTests: ClimbingProgramTestSuite {
    
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
    
    // MARK: - Timer Template CRUD Tests
    
    func testAddNewTimerTemplate() {
        // Given: A new timer template with specific configuration
        let templateName = "Test Interval Training"
        let templateDescription = "High intensity interval training"
        
        // Create interval
        let interval = TimerInterval(
            name: "Work Interval",
            workTimeSeconds: 30,
            restTimeSeconds: 15,
            repetitions: 3,
            order: 0
        )
        
        // When: Creating and saving the template
        let template = TimerTemplate(
            name: templateName,
            templateDescription: templateDescription,
            isRepeating: true,
            repeatCount: 2,
            restTimeBetweenIntervals: 60
        )
        template.intervals.append(interval)
        context.insert(template)
        
        do {
            try context.save()
        } catch {
            XCTFail("Failed to save timer template: \(error)")
        }
        
        // Then: Template should be saved with correct properties
        XCTAssertEqual(template.name, templateName)
        XCTAssertEqual(template.templateDescription, templateDescription)
        XCTAssertTrue(template.isRepeating)
        XCTAssertEqual(template.repeatCount, 2)
        XCTAssertEqual(template.restTimeBetweenIntervals, 60)
        XCTAssertEqual(template.intervals.count, 1)
        XCTAssertEqual(template.intervals.first?.workTimeSeconds, 30)
        XCTAssertEqual(template.intervals.first?.restTimeSeconds, 15)
        XCTAssertEqual(template.intervals.first?.repetitions, 3)
        XCTAssertEqual(template.useCount, 0)
        XCTAssertNotNil(template.createdDate)
        XCTAssertNil(template.lastUsedDate)
    }
    
    func testDeleteTimerTemplate() {
        // Given: An existing timer template
        let template = createTestTimerTemplate(name: "Template to Delete")
        
        // Verify template exists initially
        let templateId = template.persistentModelID
        
        // When: Deleting the template
        context.delete(template)
        
        do {
            try context.save()
        } catch {
            XCTFail("Failed to delete timer template: \(error)")
            return
        }
        
        // Then: Template should be removed from context
        // Use a fetch request instead of model(for:) for in-memory context
        let fetchRequest = FetchDescriptor<TimerTemplate>(
            predicate: #Predicate<TimerTemplate> { $0.persistentModelID == templateId }
        )
        
        do {
            let templates = try context.fetch(fetchRequest)
            XCTAssertTrue(templates.isEmpty, "Template should be deleted from context")
        } catch {
            XCTFail("Failed to fetch templates after deletion: \(error)")
        }
    }
    
    func testEditTimerTemplate() {
        // Given: An existing timer template
        let template = createTestTimerTemplate(name: "Original Template")
        let originalId = template.id
        
        // When: Editing template properties
        template.name = "Updated Template"
        template.templateDescription = "Updated description"
        template.isRepeating = false
        template.repeatCount = nil
        template.restTimeBetweenIntervals = 30
        
        // Add a new interval
        let newInterval = TimerInterval(
            name: "New Interval",
            workTimeSeconds: 45,
            restTimeSeconds: 20,
            repetitions: 2,
            order: 1
        )
        template.intervals.append(newInterval)
        
        do {
            try context.save()
        } catch {
            XCTFail("Failed to save edited timer template: \(error)")
        }
        
        // Then: Template should have updated properties
        XCTAssertEqual(template.id, originalId) // ID should remain the same
        XCTAssertEqual(template.name, "Updated Template")
        XCTAssertEqual(template.templateDescription, "Updated description")
        XCTAssertFalse(template.isRepeating)
        XCTAssertNil(template.repeatCount)
        XCTAssertEqual(template.restTimeBetweenIntervals, 30)
        XCTAssertEqual(template.intervals.count, 2)
        XCTAssertEqual(template.intervals.last?.name, "New Interval")
    }
    
    // MARK: - Timer Execution Tests
    
    @MainActor
    func testLoadAndRunTimerTemplate_ScenarioOne() {
        // Scenario: 2s work, 2s rest, 1 time total, 10s rest between, repeat 3 times
        
        // Given: A timer template with specific configuration
        let template = TimerTemplate(
            name: "Scenario One",
            isRepeating: true,
            repeatCount: 3,
            restTimeBetweenIntervals: 10
        )
        
        let interval = TimerInterval(
            name: "Work/Rest Cycle",
            workTimeSeconds: 2,
            restTimeSeconds: 2,
            repetitions: 1,
            order: 0
        )
        template.intervals.append(interval)
        context.insert(template)
        
        let configuration = TimerConfiguration(
            totalTimeSeconds: nil,
            intervals: template.intervals.map { interval in
                IntervalConfiguration(
                    name: interval.name,
                    workTimeSeconds: interval.workTimeSeconds,
                    restTimeSeconds: interval.restTimeSeconds,
                    repetitions: interval.repetitions
                )
            },
            isRepeating: template.isRepeating,
            repeatCount: template.repeatCount,
            restTimeBetweenIntervals: template.restTimeBetweenIntervals
        )
        
        // When: Starting the timer
        timerManager.start(with: configuration)
        
        // Then: Initial state should be correct
        XCTAssertTrue(timerManager.isRunning)
        XCTAssertEqual(timerManager.currentPhase, .work)
        XCTAssertEqual(timerManager.currentInterval, 0)
        XCTAssertEqual(timerManager.currentSequenceRepeat, 0)
        XCTAssertEqual(timerManager.totalTimeRemaining, 32) // 12s intervals + 20s rest
        
        // Simulate timer progression by manually updating the internal time
        // This tests the actual timer logic without waiting for real time
        
        // After 2 seconds: Should transition from work to rest
        timerManager.currentTime = 2
        timerManager.totalElapsedTime = 2
        timerManager.updateIntervalProgress()
        
        XCTAssertEqual(timerManager.currentPhase, .rest, "Should be in rest phase after 2s work")
        XCTAssertEqual(timerManager.currentInterval, 0)
        XCTAssertEqual(timerManager.currentSequenceRepeat, 0)
        
        // After 4 seconds: Should finish first sequence and start rest between sequences
        timerManager.currentTime = 4
        timerManager.totalElapsedTime = 4
        timerManager.updateIntervalProgress()
        timerManager.checkForCompletion()
        
        XCTAssertTrue(timerManager.isInBetweenIntervalRest, "Should be in rest between sequences")
        XCTAssertEqual(timerManager.currentPhase, .rest)
        XCTAssertEqual(timerManager.currentSequenceRepeat, 1, "Should have completed first sequence")
        
        // After 14 seconds: Should finish rest and start second sequence
        timerManager.currentTime = 14
        timerManager.totalElapsedTime = 14
        timerManager.updateIntervalProgress()
        
        XCTAssertFalse(timerManager.isInBetweenIntervalRest, "Should have finished rest between sequences")
        XCTAssertEqual(timerManager.currentPhase, .work, "Should be in work phase of second sequence")
        XCTAssertEqual(timerManager.currentInterval, 0, "Should be back to first interval")
        XCTAssertEqual(timerManager.currentSequenceRepeat, 1)
        
        // After 32 seconds: Should complete all sequences
        timerManager.currentTime = 32
        timerManager.totalElapsedTime = 32
        timerManager.updateIntervalProgress()
        timerManager.checkForCompletion()
        
        XCTAssertTrue(timerManager.isCompleted, "Should be completed after 32 seconds")
        XCTAssertEqual(timerManager.totalTimeRemaining, 0)
    }
    
    @MainActor
    func testLoadAndRunTimerTemplate_ScenarioTwo() {
        // Scenario: 2s work, 2s rest, 3 times (no sequence repeats)
        
        // Given: A timer template with specific configuration
        let template = TimerTemplate(
            name: "Scenario Two",
            isRepeating: false,
            repeatCount: nil,
            restTimeBetweenIntervals: nil
        )
        
        let interval = TimerInterval(
            name: "Work/Rest Cycle",
            workTimeSeconds: 2,
            restTimeSeconds: 2,
            repetitions: 3,
            order: 0
        )
        template.intervals.append(interval)
        context.insert(template)
        
        let configuration = TimerConfiguration(
            totalTimeSeconds: nil,
            intervals: template.intervals.map { interval in
                IntervalConfiguration(
                    name: interval.name,
                    workTimeSeconds: interval.workTimeSeconds,
                    restTimeSeconds: interval.restTimeSeconds,
                    repetitions: interval.repetitions
                )
            },
            isRepeating: template.isRepeating,
            repeatCount: template.repeatCount,
            restTimeBetweenIntervals: template.restTimeBetweenIntervals
        )
        
        // When: Starting the timer
        timerManager.start(with: configuration)
        
        // Then: Initial state should be correct
        XCTAssertTrue(timerManager.isRunning)
        XCTAssertEqual(timerManager.currentPhase, .work)
        XCTAssertEqual(timerManager.currentRepetition, 0)
        XCTAssertEqual(timerManager.totalTimeRemaining, 12) // (2+2) * 3 = 12 seconds
        
        // Test progression through all 3 repetitions
        let phases: [(time: Int, expectedPhase: IntervalPhase, expectedRep: Int, description: String)] = [
            (2, .rest, 0, "First rest after 2s work"),
            (4, .work, 1, "Second work phase after 4s"),
            (6, .rest, 1, "Second rest phase after 6s"),
            (8, .work, 2, "Third work phase after 8s"),
            (10, .rest, 2, "Third rest phase after 10s"),
            (12, .work, 3, "Completed all repetitions after 12s")
        ]
        
        for (time, expectedPhase, expectedRep, description) in phases {
            timerManager.currentTime = time
            timerManager.totalElapsedTime = time
            timerManager.updateIntervalProgress()
            timerManager.checkForCompletion()
            
            if time < 12 {
                XCTAssertEqual(timerManager.currentPhase, expectedPhase, description)
                XCTAssertEqual(timerManager.currentRepetition, expectedRep, description)
                XCTAssertTrue(timerManager.isRunning, "\(description) - should still be running")
            } else {
                XCTAssertTrue(timerManager.isCompleted, "Should be completed after 12 seconds")
            }
        }
    }
    
    @MainActor
    func testTimerExecution_PhaseProgression() {
        // Test detailed phase progression with a simple configuration
        let configuration = TimerConfiguration(
            totalTimeSeconds: nil,
            intervals: [
                IntervalConfiguration(
                    name: "Test Interval",
                    workTimeSeconds: 3,
                    restTimeSeconds: 2,
                    repetitions: 2
                )
            ],
            isRepeating: false,
            repeatCount: nil,
            restTimeBetweenIntervals: nil
        )
        
        // When: Starting the timer
        timerManager.start(with: configuration)
        
        // Test each second of progression
        let progressions: [(time: Int, phase: IntervalPhase, rep: Int, remaining: Int)] = [
            (0, .work, 0, 3),    // Start: 3s work remaining
            (1, .work, 0, 2),    // 1s: 2s work remaining
            (2, .work, 0, 1),    // 2s: 1s work remaining
            (3, .rest, 0, 2),    // 3s: transition to rest, 2s rest remaining
            (4, .rest, 0, 1),    // 4s: 1s rest remaining
            (5, .work, 1, 3),    // 5s: second rep work, 3s remaining
            (6, .work, 1, 2),    // 6s: 2s work remaining
            (7, .work, 1, 1),    // 7s: 1s work remaining
            (8, .rest, 1, 2),    // 8s: second rep rest, 2s remaining
            (9, .rest, 1, 1),    // 9s: 1s rest remaining
        ]
        
        for (time, expectedPhase, expectedRep, expectedRemaining) in progressions {
            timerManager.currentTime = time
            timerManager.totalElapsedTime = time
            timerManager.updateIntervalProgress()
            
            XCTAssertEqual(timerManager.currentPhase, expectedPhase,
                          "At \(time)s: expected phase \(expectedPhase)")
            XCTAssertEqual(timerManager.currentRepetition, expectedRep,
                          "At \(time)s: expected repetition \(expectedRep)")
            XCTAssertEqual(timerManager.currentPhaseTimeRemaining, expectedRemaining,
                          "At \(time)s: expected \(expectedRemaining)s remaining in phase")
        }
        
        // After 10 seconds: Should be completed
        timerManager.currentTime = 10
        timerManager.totalElapsedTime = 10
        timerManager.updateIntervalProgress()
        timerManager.checkForCompletion()
        
        XCTAssertTrue(timerManager.isCompleted, "Should be completed after 10 seconds")
    }
    
    @MainActor
    func testTimerExecution_RestBetweenSequences() {
        // Test specifically the rest periods between sequence repeats
        let configuration = TimerConfiguration(
            totalTimeSeconds: nil,
            intervals: [
                IntervalConfiguration(
                    name: "Quick Interval",
                    workTimeSeconds: 1,
                    restTimeSeconds: 1,
                    repetitions: 1
                )
            ],
            isRepeating: true,
            repeatCount: 2,
            restTimeBetweenIntervals: 3
        )
        
        timerManager.start(with: configuration)
        
        // Sequence 1: 1s work + 1s rest = 2s total
        timerManager.currentTime = 2
        timerManager.totalElapsedTime = 2
        timerManager.updateIntervalProgress()
        timerManager.checkForCompletion()
        
        // Should now be in rest between sequences
        XCTAssertTrue(timerManager.isInBetweenIntervalRest, "Should be in rest between sequences")
        XCTAssertEqual(timerManager.currentPhase, .rest)
        XCTAssertEqual(timerManager.currentSequenceRepeat, 1, "Should have completed first sequence")
        XCTAssertEqual(timerManager.currentPhaseTimeRemaining, 3, "Should have 3s rest remaining")
        
        // During rest between sequences
        timerManager.currentTime = 4
        timerManager.totalElapsedTime = 4
        timerManager.updateIntervalProgress()
        
        XCTAssertTrue(timerManager.isInBetweenIntervalRest, "Should still be in rest between sequences")
        XCTAssertEqual(timerManager.currentPhaseTimeRemaining, 1, "Should have 1s rest remaining")
        
        // After rest period completes
        timerManager.currentTime = 5
        timerManager.totalElapsedTime = 5
        timerManager.updateIntervalProgress()
        
        XCTAssertFalse(timerManager.isInBetweenIntervalRest, "Should have finished rest between sequences")
        XCTAssertEqual(timerManager.currentPhase, .work, "Should be in work phase of second sequence")
        XCTAssertEqual(timerManager.currentInterval, 0, "Should be back to interval 0")
        XCTAssertEqual(timerManager.currentSequenceRepeat, 1)
        
        // Complete second sequence
        timerManager.currentTime = 7
        timerManager.totalElapsedTime = 7
        timerManager.updateIntervalProgress()
        timerManager.checkForCompletion()
        
        XCTAssertTrue(timerManager.isCompleted, "Should be completed after second sequence")
        XCTAssertEqual(timerManager.totalElapsedTime, 7)
    }
    
    // MARK: - UI Consistency Tests
    
    func testUIConsistency_TemplateListViews() {
        // Given: Multiple timer templates
        let template1 = createTestTimerTemplate(name: "Template 1")
        let template2 = createTestTimerTemplate(name: "Template 2")
        let template3 = createTestTimerTemplate(name: "Template 3")
        
        // Set different last used dates to test sorting
        template1.lastUsedDate = Date().addingTimeInterval(-86400) // 1 day ago
        template2.lastUsedDate = Date().addingTimeInterval(-3600)  // 1 hour ago
        template3.lastUsedDate = Date() // now
        
        do {
            try context.save()
        } catch {
            XCTFail("Failed to save templates: \(error)")
        }
        
        // When: Fetching templates for different views
        let allTemplatesRequest = FetchDescriptor<TimerTemplate>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        let recentTemplatesRequest = FetchDescriptor<TimerTemplate>(
            sortBy: [SortDescriptor(\.lastUsedDate, order: .reverse)]
        )
        
        let allTemplates = try! context.fetch(allTemplatesRequest)
        let recentTemplates = try! context.fetch(recentTemplatesRequest)
        
        // Then: Templates should be sorted differently but contain same data
        XCTAssertEqual(allTemplates.count, 3)
        XCTAssertEqual(recentTemplates.count, 3)
        
        // All templates sorted by name
        XCTAssertEqual(allTemplates[0].name, "Template 1")
        XCTAssertEqual(allTemplates[1].name, "Template 2")
        XCTAssertEqual(allTemplates[2].name, "Template 3")
        
        // Recent templates sorted by last used date (most recent first)
        XCTAssertEqual(recentTemplates[0].name, "Template 3")
        XCTAssertEqual(recentTemplates[1].name, "Template 2")
        XCTAssertEqual(recentTemplates[2].name, "Template 1")
        
        // Verify same templates exist in both lists (same IDs)
        let allIds = Set(allTemplates.map { $0.id })
        let recentIds = Set(recentTemplates.map { $0.id })
        XCTAssertEqual(allIds, recentIds)
    }
    
    func testUIConsistency_TemplateDataIntegrity() {
        // Given: A template accessed from different views
        let template = createTestTimerTemplate(name: "Consistency Test")
        let templateId = template.persistentModelID
        
        // When: Modifying template through one view
        template.name = "Modified Name"
        template.templateDescription = "Modified Description"
        
        do {
            try context.save()
        } catch {
            XCTFail("Failed to save template modifications: \(error)")
        }
        
        // Then: Changes should be reflected across all views
        let fetchedTemplate = context.model(for: templateId) as! TimerTemplate
        XCTAssertEqual(fetchedTemplate.name, "Modified Name")
        XCTAssertEqual(fetchedTemplate.templateDescription, "Modified Description")
        
        // Verify template properties are consistent
        XCTAssertEqual(fetchedTemplate.id, template.id)
        XCTAssertEqual(fetchedTemplate.intervals.count, template.intervals.count)
        XCTAssertEqual(fetchedTemplate.isRepeating, template.isRepeating)
        XCTAssertEqual(fetchedTemplate.repeatCount, template.repeatCount)
        XCTAssertEqual(fetchedTemplate.restTimeBetweenIntervals, template.restTimeBetweenIntervals)
    }
    
    func testUIConsistency_TemplateSelection() {
        // Given: Templates with different configurations
        let simpleTemplate = TimerTemplate(
            name: "Simple Timer",
            totalTimeSeconds: 300 // 5 minutes
        )
        
        _ = createTestTimerTemplate(name: "Interval Timer")
        
        context.insert(simpleTemplate)
        
        do {
            try context.save()
        } catch {
            XCTFail("Failed to save templates: \(error)")
        }
        
        // When: Templates are displayed in both "All Templates" and "Load Template" views
        let templates = try! context.fetch(FetchDescriptor<TimerTemplate>())
        
        // Then: Both views should show consistent template information
        for template in templates {
            // Verify essential properties are accessible
            XCTAssertFalse(template.name.isEmpty)
            XCTAssertNotNil(template.id)
            XCTAssertNotNil(template.createdDate)
            
            // Verify timer type can be determined
            let hasIntervals = !template.intervals.isEmpty
            let hasTotalTime = template.totalTimeSeconds != nil && template.totalTimeSeconds! > 0
            
            XCTAssertTrue(hasIntervals || hasTotalTime, "Template should have either intervals or total time")
        }
    }
    
    // MARK: - Integration Tests
    
    func testTimerSessionCreation() {
        // Given: A timer template
        let template = createTestTimerTemplate(name: "Session Test")
        
        // When: Creating a timer session
        let session = TimerSession(
            templateId: template.id,
            templateName: template.name
        )
        context.insert(session)
        
        do {
            try context.save()
        } catch {
            XCTFail("Failed to save timer session: \(error)")
        }
        
        // Then: Session should be created with correct properties
        XCTAssertEqual(session.templateId, template.id)
        XCTAssertEqual(session.templateName, template.name)
        XCTAssertNotNil(session.startDate)
        XCTAssertNil(session.endDate)
        XCTAssertEqual(session.totalElapsedSeconds, 0)
        XCTAssertEqual(session.completedIntervals, 0)
        XCTAssertFalse(session.wasCompleted)
        XCTAssertTrue(session.laps.isEmpty)
    }
    
    func testTimerLapRecording() {
        // Given: A timer session
        let session = TimerSession(templateName: "Lap Test")
        context.insert(session)
        
        // When: Adding laps
        let lap1 = TimerLap(lapNumber: 1, elapsedSeconds: 30, notes: "First lap")
        let lap2 = TimerLap(lapNumber: 2, elapsedSeconds: 65, notes: "Second lap")
        
        session.laps.append(lap1)
        session.laps.append(lap2)
        
        do {
            try context.save()
        } catch {
            XCTFail("Failed to save timer laps: \(error)")
        }
        
        // Then: Laps should be recorded correctly
        XCTAssertEqual(session.laps.count, 2)
        XCTAssertEqual(session.laps[0].lapNumber, 1)
        XCTAssertEqual(session.laps[0].elapsedSeconds, 30)
        XCTAssertEqual(session.laps[0].notes, "First lap")
        XCTAssertEqual(session.laps[1].lapNumber, 2)
        XCTAssertEqual(session.laps[1].elapsedSeconds, 65)
        XCTAssertEqual(session.laps[1].notes, "Second lap")
    }
}
