//
//  TimerEngine.swift
//  ClimbingProgram
//
//  Created by Shahar Noy on 27.10.25.
//

import Foundation

public enum SegmentKind: String, CaseIterable, Codable, Hashable {
    case getReady
    case work
    case rest
    case betweenSets
}

public struct Segment: Hashable, Codable {
    public let kind: SegmentKind
    public let duration: TimeInterval
    public let countsTowardTotal: Bool
}

public struct Timeline: Hashable, Codable {
    public let segments: [Segment]
    /// Cumulative ends in absolute seconds from t0 (including getReady)
    public let cumulativeEnds: [TimeInterval]
    /// Cumulative ends counting ONLY segments that count toward total (excludes getReady)
    public let countedCumulativeEnds: [TimeInterval]

    public let totalDuration: TimeInterval
    public let totalCountedDuration: TimeInterval

    // Interval meta (for Live Activity labels, etc.)
    public let totalSets: Int
    public let repsPerSet: Int
    public let segmentSetIndex: [Int]      // per segment, 0‑based set index (−1 for getReady if you prefer)
    public let segmentRepIndex: [Int]      // per segment, 0‑based rep index (−1 when N/A)

    public init(segments: [Segment],
                cumulativeEnds: [TimeInterval],
                countedCumulativeEnds: [TimeInterval],
                totalSets: Int,
                repsPerSet: Int,
                segmentSetIndex: [Int],
                segmentRepIndex: [Int]) {
        self.segments = segments
        self.cumulativeEnds = cumulativeEnds
        self.countedCumulativeEnds = countedCumulativeEnds
        self.totalDuration = cumulativeEnds.last ?? 0
        self.totalCountedDuration = countedCumulativeEnds.last ?? 0
        self.totalSets = totalSets
        self.repsPerSet = repsPerSet
        self.segmentSetIndex = segmentSetIndex
        self.segmentRepIndex = segmentRepIndex
    }
}

public struct Snapshot: Hashable {
    public let isRunning: Bool
    public let isPaused: Bool
    public let isCompleted: Bool

    public let absoluteElapsed: TimeInterval       // includes getReady
    public let countedElapsed: TimeInterval        // excludes getReady

    public let segmentIndex: Int?                  // nil if completed
    public let segment: Segment?                   // nil if completed
    public let segmentElapsed: TimeInterval        // 0 if completed
    public let segmentRemaining: TimeInterval      // 0 if completed

    public let overallProgress: Double             // countedElapsed / totalCountedDuration (0…1)

    // Interval meta for convenience (−1 if N/A)
    public let currentSetIndex: Int
    public let currentRepIndex: Int
}

public protocol Clock {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}

public final class TimerEngine {
    public let timeline: Timeline
    public let clock: Clock

    private var startDate: Date?
    private var pausedAt: Date?
    private var pausedAccumulation: TimeInterval = 0

    public init(timeline: Timeline, clock: Clock = SystemClock()) {
        self.timeline = timeline
        self.clock = clock
    }

    // MARK: - Control
    public func start(at date: Date? = nil) {
        let t = date ?? clock.now()
        startDate = t
        pausedAt = nil
        pausedAccumulation = 0
    }

    public func reset() {
        startDate = nil
        pausedAt = nil
        pausedAccumulation = 0
    }

    public func pause(at date: Date? = nil) {
        guard pausedAt == nil else { return }
        guard startDate != nil else { return }
        pausedAt = date ?? clock.now()
    }

    public func resume(at date: Date? = nil) {
        guard let p = pausedAt else { return }
        let t = date ?? clock.now()
        pausedAccumulation += max(0, t.timeIntervalSince(p))
        pausedAt = nil
    }

    public var isRunning: Bool { startDate != nil && !isCompleted(now: clock.now()) }
    public var isPaused: Bool { pausedAt != nil }

    private func isCompleted(now: Date) -> Bool {
        return absoluteElapsed(now: now) >= timeline.totalDuration
    }
    // MARK: - Snapshot
    public func snapshot(at date: Date? = nil) -> Snapshot {
        let t = date ?? clock.now()
        let absElapsed = absoluteElapsed(now: t)
        let completed = absElapsed >= timeline.totalDuration

        if completed || startDate == nil {
            let countedElapsed = min(absElapsed - countedOffsetForTime(absElapsed), timeline.totalCountedDuration)
            let progress = timeline.totalCountedDuration > 0 ? countedElapsed / timeline.totalCountedDuration : 0
            return Snapshot(isRunning: startDate != nil && !isPaused && !completed,
                            isPaused: isPaused,
                            isCompleted: completed,
                            absoluteElapsed: min(absElapsed, timeline.totalDuration),
                            countedElapsed: max(0, countedElapsed),
                            segmentIndex: nil,
                            segment: nil,
                            segmentElapsed: 0,
                            segmentRemaining: 0,
                            overallProgress: progress,
                            currentSetIndex: -1,
                            currentRepIndex: -1)
        }

        // Find segment index by binary search over cumulativeEnds
        let idx = binarySearchIndex(for: absElapsed, in: timeline.cumulativeEnds)
        let seg = timeline.segments[idx]
        let segStart = idx == 0 ? 0 : timeline.cumulativeEnds[idx - 1]
        let segElapsed = absElapsed - segStart
        let segRemaining = max(0, seg.duration - segElapsed)

        // Counted elapsed up to this point
        let countedBefore = countedUpToSegment(index: idx) - (seg.countsTowardTotal ? seg.duration : 0)
        let countedNow = countedBefore + (seg.countsTowardTotal ? min(segElapsed, seg.duration) : 0)
        let progress = timeline.totalCountedDuration > 0 ? countedNow / timeline.totalCountedDuration : 0

        return Snapshot(isRunning: !isPaused,
                        isPaused: isPaused,
                        isCompleted: false,
                        absoluteElapsed: absElapsed,
                        countedElapsed: countedNow,
                        segmentIndex: idx,
                        segment: seg,
                        segmentElapsed: segElapsed,
                        segmentRemaining: segRemaining,
                        overallProgress: progress,
                        currentSetIndex: timeline.segmentSetIndex[idx],
                        currentRepIndex: timeline.segmentRepIndex[idx])
    }

    // MARK: - Builders
    public static func buildTotalTimer(work: TimeInterval, getReady: TimeInterval = 5) -> Timeline {
        var segments: [Segment] = []
        var cum: [TimeInterval] = []
        var counted: [TimeInterval] = []
        var running: TimeInterval = 0
        var countedRunning: TimeInterval = 0

        func push(_ s: Segment, setIndex: Int, repIndex: Int,
                  segSet: inout [Int], segRep: inout [Int]) {
            segments.append(s)
            running += s.duration
            cum.append(running)
            if s.countsTowardTotal { countedRunning += s.duration }
            counted.append(countedRunning)
            segSet.append(setIndex)
            segRep.append(repIndex)
        }

        var segSet: [Int] = []
        var segRep: [Int] = []

        // getReady (not counted)
        if getReady > 0 {
            push(Segment(kind: .getReady, duration: getReady, countsTowardTotal: false),
                 setIndex: -1, repIndex: -1, segSet: &segSet, segRep: &segRep)
        }
        // single work block
        push(Segment(kind: .work, duration: max(0, work), countsTowardTotal: true),
             setIndex: 0, repIndex: 0, segSet: &segSet, segRep: &segRep)

        return Timeline(segments: segments,
                        cumulativeEnds: cum,
                        countedCumulativeEnds: counted,
                        totalSets: 1,
                        repsPerSet: 1,
                        segmentSetIndex: segSet,
                        segmentRepIndex: segRep)
    }

    public static func buildIntervals(work: TimeInterval,
                                      rest: TimeInterval,
                                      repsPerSet: Int,
                                      sets: Int,
                                      restBetweenSets: TimeInterval = 0,
                                      getReady: TimeInterval = 5) -> Timeline {
        let reps = max(1, repsPerSet)
        let setCount = max(1, sets)

        var segments: [Segment] = []
        var cum: [TimeInterval] = []
        var counted: [TimeInterval] = []
        var running: TimeInterval = 0
        var countedRunning: TimeInterval = 0
        var segSet: [Int] = []
        var segRep: [Int] = []

        func push(_ s: Segment, setIndex: Int, repIndex: Int) {
            segments.append(s)
            running += s.duration
            cum.append(running)
            if s.countsTowardTotal { countedRunning += s.duration }
            counted.append(countedRunning)
            segSet.append(setIndex)
            segRep.append(repIndex)
        }

        // getReady (not counted)
        if getReady > 0 {
            push(Segment(kind: .getReady, duration: getReady, countsTowardTotal: false), setIndex: -1, repIndex: -1)
        }

        for setIdx in 0..<setCount {
            for repIdx in 0..<reps {
                // WORK always
                if work > 0 {
                    push(Segment(kind: .work, duration: work, countsTowardTotal: true), setIndex: setIdx, repIndex: repIdx)
                }
                // REST only if not the last repetition in the set
                if repIdx < reps - 1, rest > 0 {
                    push(Segment(kind: .rest, duration: rest, countsTowardTotal: true), setIndex: setIdx, repIndex: repIdx)
                }
            }
            // BETWEEN SETS only between sets
            if setIdx < setCount - 1, restBetweenSets > 0 {
                push(Segment(kind: .betweenSets, duration: restBetweenSets, countsTowardTotal: true), setIndex: setIdx, repIndex: -1)
            }
        }

        return Timeline(segments: segments,
                        cumulativeEnds: cum,
                        countedCumulativeEnds: counted,
                        totalSets: setCount,
                        repsPerSet: reps,
                        segmentSetIndex: segSet,
                        segmentRepIndex: segRep)
    }

    private func absoluteElapsed(now: Date) -> TimeInterval {
        guard let start = startDate else { return 0 }
        let reference = pausedAt ?? now
        let base = reference.timeIntervalSince(start) - pausedAccumulation
        let clamped = max(0, base)
        return min(clamped, timeline.totalDuration)
    }


    private func countedOffsetForTime(_ t: TimeInterval) -> TimeInterval {
        // how much of t is in non-counted segments at the front (only getReady in this model)
        // If there is a getReady, it’s the first segment and not counted.
        if let first = timeline.segments.first, first.kind == .getReady { return min(t, first.duration) }
        return 0
    }

    private func countedUpToSegment(index i: Int) -> TimeInterval {
        // cumulative counted end for segment i
        return timeline.countedCumulativeEnds[i]
    }

    private func binarySearchIndex(for value: TimeInterval, in cumulativeEnds: [TimeInterval]) -> Int {
        // returns the first index whose cumulativeEnd >= value
        var low = 0
        var high = cumulativeEnds.count - 1
        while low < high {
            let mid = (low + high) / 2
            if cumulativeEnds[mid] > value {
                high = mid
            } else if cumulativeEnds[mid] < value {
                low = mid + 1
            } else {
                return mid
            }
        }
        return low
    }
}
