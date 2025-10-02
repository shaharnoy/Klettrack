//  TimerTemplateTests.swift
//  klettrack Tests
//
//  Created by Shahar Noy on 30.09.25

import XCTest
import SwiftData
@testable import klettrack

final class TimerTemplateTests: BaseSwiftDataTestCase {
    func testEffectiveTotalTimeSeconds_ComputedFromIntervalsAndRepeats() {
        // One interval: (work+rest) * reps = (10+20) * 6 = 180
        // Repeating 5 times with 60s rest between intervals:
        // base per cycle = 180, rest between intervals = 4 * 60 = 240
        // total = (180 * 5) + 240 = 900 + 240 = 1140
        let tmpl = TimerTemplate(
            name: "One-Arm, One-Leg",
            templateDescription: nil,
            totalTimeSeconds: nil,
            isRepeating: true,
            repeatCount: 5,
            restTimeBetweenIntervals: 60
        )
        
        let tmplinterval = TimerInterval(
            name: "One-Arm Hold",
            workTimeSeconds: 10,
            restTimeSeconds: 20,
            repetitions: 6,
            order: 0
        )
        tmpl.intervals.append(tmplinterval)

        context.insert(tmpl)
        XCTAssertEqual(tmpl.effectiveTotalTimeSeconds, 1140)
    }
    
    func testEffectiveTotalTimeSeconds_UsesExplicitTotalIfProvided() {
        let tmpl = TimerTemplate(
            name: "Fixed",
            templateDescription: nil,
            totalTimeSeconds: 180,
            isRepeating: false,
            repeatCount: nil,
            restTimeBetweenIntervals: nil
        )
        context.insert(tmpl)
        XCTAssertEqual(tmpl.effectiveTotalTimeSeconds, 180)
    }
}

