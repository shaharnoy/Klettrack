//
//  ProgressViewScreen.swift
//  Klettrack
//  Created by Shahar Noy on 21.08.25.
//

import SwiftUI
import SwiftData
import Charts
import StoreKit
import UIKit


// MARK: - Layout Grid

fileprivate enum LayoutGrid {
    //Distance from screen edges / main content column
    static let outerHorizontal: CGFloat = 16
    //Padding inside cards (material backgrounds)
    static let cardInner: CGFloat = 12
    // Vertical spacing between major sections within a stats view
    static let sectionSpacing: CGFloat = 16
}

// MARK: - Entry (keeps your existing type name)
public struct ProgressViewScreen: View {
    // Live data via SwiftData
    @Query(sort: \Session.date) private var allSessions: [Session]
    @Query(sort: \ClimbEntry.dateLogged) private var allClimbEntries: [ClimbEntry]
    @Query(sort: \Plan.startDate) private var allPlans: [Plan]
    
    @State private var tab: Tab = .climb
    @StateObject private var climbVM  = ClimbStatsVM(input: .init(sessions: [], climbs: [], plans: []))
    @StateObject private var exerciseVM = ExerciseStatsVM(input: .init(sessions: [], climbs: [], plans: []))
    @State private var hasRequestedReviewThisSession = false
    @AppStorage("filterReviewTriggerCount") private var filterCount = 0


    public init() {}
    
    public var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    // Segmented tab selector
                    Picker("", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { tabCase in
                            Text(tabCase.rawValue).tag(tabCase)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, LayoutGrid.outerHorizontal)
                    .padding(.top, 8)

                    Divider()
                        .padding(.horizontal, LayoutGrid.outerHorizontal)
                        .padding(.top, 8)

                    Group {
                        if tab == .climb {
                            ClimbStatsView(vm: climbVM)
                        } else {
                            ExerciseStatsView(vm: exerciseVM)
                        }
                    }
                }
                .frame(width: geo.size.width, alignment: .topLeading)
            }
            .frame(width: geo.size.width)
        }
        .navigationTitle("PROGRESS")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            let data = StatsInputData(
                sessions: allSessions,
                climbs: allClimbEntries,
                plans: allPlans
            )
            climbVM.updateInput(data)
            exerciseVM.updateInput(data)
        }
        .onChange(of: allSessions) { _, _ in
            let data = StatsInputData(sessions: allSessions, climbs: allClimbEntries, plans: allPlans)
            climbVM.updateInput(data)
            exerciseVM.updateInput(data)
        }
        .onChange(of: allClimbEntries) { _, _ in
            let data = StatsInputData(sessions: allSessions, climbs: allClimbEntries, plans: allPlans)
            climbVM.updateInput(data)
            exerciseVM.updateInput(data)
        }
        .onChange(of: allPlans) { _, _ in
            let data = StatsInputData(sessions: allSessions, climbs: allClimbEntries, plans: allPlans)
            climbVM.updateInput(data)
            exerciseVM.updateInput(data)
        }
    }
}

fileprivate enum Tab: String, CaseIterable { case climb = "Climb",exercise = "Exercise"  }

// MARK: - Shared data container passed into VMs
fileprivate struct StatsInputData { let sessions: [Session]; let climbs: [ClimbEntry]; let plans: [Plan] }

// MARK: - Common small types
fileprivate struct MultiPickOption: Identifiable, Hashable {
    let id: String
    let label: String
}
fileprivate struct TimePoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Int       // original point value
    let cumulative: Int  // running total up to this date
}
fileprivate struct StackedBar<X: Hashable, Stack: Hashable>: Identifiable {
    let id = UUID()
    let x: X
    let stacks: [Stack: Int]
}
fileprivate struct SeasonalitySlice: Identifiable {
    let id = UUID()
    let month: Int /*1...12*/
    let style: String
    let value: Double
}

// MARK: - Date Range
struct DateRange: Equatable {
    var customStart: Date? = nil
    var customEnd: Date? = nil
}

// MARK: - Exercise VM
fileprivate final class ExerciseStatsVM: ObservableObject {
    private var input: StatsInputData
    @Published var dateRange = DateRange(
            customStart: Calendar.current.startOfDay(for: Date()),
            customEnd:   Calendar.current.startOfDay(for: Date())
        )
    @Published var trainingPlanIDs: Set<String> = []
    @Published var exerciseNames: Set<String> = []

    @Published var totalSessions: Int = 0
    @Published var totalExercises: Int = 0

    @Published var availableTrainingPlans: [MultiPickOption] = []
    @Published var availableExercises: [MultiPickOption] = []

    @Published var distWeight: [(String, Int)] = []
    @Published var distReps: [(String, Int)] = []
    @Published var distSets: [(String, Int)] = []
    @Published var distDuration: [(String, Int)] = []
    @Published var weightBreakdown: [String: [(String, Int)]] = [:] // bin → [(value, count)]
    @Published var repsBreakdown:   [String: [(String, Int)]] = [:]
    @Published var setsBreakdown:   [String: [(String, Int)]] = [:]
    @Published var durationBreakdown:  [String: [(String, Int)]] = [:]


    @Published var timeSeries: [TimePoint] = []

    init(input: StatsInputData) {
        self.input = input
        buildCatalogs()
        resetDateRangeToData()
        recomputeAll()
    }
    func clearAll() {
        trainingPlanIDs.removeAll()
        exerciseNames.removeAll()
        resetDateRangeToData()
        recomputeAll()
    }
    private func resetDateRangeToData() {
        let cal = Calendar.current
        let today = Date()
        let earliest = input.sessions.map(\.date).min() ?? today
        let latest  = input.sessions.map(\.date).max() ?? today
        dateRange.customStart = cal.startOfDay(for: earliest)
        dateRange.customEnd   = cal.date(byAdding: .second, value: -1,
                               to: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: latest))!)!
    }


    private func filterByDate(_ sessions: [Session]) -> [Session] {
        let cal = Calendar.current
        let today = Date()
        let rawStart = dateRange.customStart ?? input.sessions.map(\.date).min() ?? today
        let rawEnd   = dateRange.customEnd   ?? input.sessions.map(\.date).max() ?? today
        let start = cal.startOfDay(for: rawStart)
        let end   = cal.date(byAdding: .second, value: -1,
                     to: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: rawEnd))!)!
        return sessions.filter { $0.date >= start && $0.date <= end }
    }


    func updateInput(_ input: StatsInputData) {
        self.input = input
        buildCatalogs()
        resetDateRangeToData()
        recomputeAll()
    }
    // Catalogs
    private func buildCatalogs() {
        availableTrainingPlans = input.plans.map { .init(id: $0.id.uuidString, label: $0.name) }
        let names = Set(input.sessions.flatMap { $0.items.map { $0.exerciseName } })
        availableExercises = names.sorted().map { .init(id: $0, label: $0) }
    }

    // Recompute pipeline
    func recomputeAll() {
        // 1) Date filter
        let s1 = filterByDate(input.sessions)
        let s2 = filterByPlans(s1)

        // Use lightweight value type to avoid SwiftData cloning issues
        let s3: [SessionLite]
        if exerciseNames.isEmpty {
            s3 = s2.map { SessionLite(id: $0.id, date: $0.date, items: $0.items) }
        } else {
            s3 = s2.compactMap { session in
                let filteredItems = session.items.filter { exerciseNames.contains($0.exerciseName) }
                guard !filteredItems.isEmpty else { return nil }
                return SessionLite(id: session.id, date: session.date, items: filteredItems)
            }
        }

        // KPIs (now based on filtered items)
        totalSessions  = s3.count
        totalExercises = s3.reduce(0) { $0 + $1.items.count }

        // Distributions
        let d = aggregateDistributionsLite(s3)
        distWeight = d.weight; distReps = d.reps; distSets = d.sets; distDuration = d.duration
        weightBreakdown = d.wbd; repsBreakdown = d.rbd; setsBreakdown = d.sbd; durationBreakdown = d.dbd

        // Time series (count exercises per session date bucket)
        timeSeries = aggregateTimeSeriesLite(s3)

    }

    // Filters
    private func filterByPlans(_ sessions: [Session]) -> [Session] {
        guard !trainingPlanIDs.isEmpty else { return sessions }
        var ranges: [(Date, Date)] = []
        for p in input.plans where trainingPlanIDs.contains(p.id.uuidString) {
            let dates = p.days.map { $0.date }
            if let minD = dates.min(), let maxD = dates.max() { ranges.append((minD, maxD)) }
        }
        guard !ranges.isEmpty else { return sessions }
        return sessions.filter { s in ranges.contains { s.date >= $0.0 && s.date <= $0.1 } }
    }
    
    fileprivate struct SessionLite {
        let id: UUID
        let date: Date
        let items: [SessionItem]
    }
    // --- helpers for numeric binning ---
    private func niceStep(_ raw: Double) -> Double {
        guard raw > 0 else { return 1 }
        let exp10 = pow(10.0, floor(log10(raw)))
        let frac = raw / exp10
        let niceFrac: Double = (frac <= 1) ? 1 : (frac <= 2) ? 2 : (frac <= 5) ? 5 : 10
        return niceFrac * exp10
    }
    private func makeBins(minVal: Double, maxVal: Double, targetBins: Int = 6) -> [ClosedRange<Double>] {
        guard maxVal.isFinite, minVal.isFinite else { return [] }
        if maxVal == minVal {
            let v = minVal
            return [max(0, v - 1)...(v + 1)]
        }

        let rawStep = (maxVal - minVal) / Double(max(1, targetBins))
        let step = Swift.max(1e-9, niceStep(rawStep))
        let start = floor(minVal / step) * step
        let end = ceil(maxVal / step) * step

        var bins: [ClosedRange<Double>] = []
        var cur = start
        while cur < end - 1e-9 {
            let nxt = cur + step
            bins.append(cur...nxt)
            cur = nxt
        }

        // Ensure last bin upper bound includes maxVal
        if bins.last?.upperBound ?? 0 < maxVal {
            bins.append((bins.last?.upperBound ?? end)...maxVal)
        }

        return bins
    }


    private func label(_ r: ClosedRange<Double>, unit: String?) -> String {
        let lo = r.lowerBound, hi = r.upperBound
        let fmt = (lo.rounded() == lo && hi.rounded() == hi) ? "%.0f" : "%.1f"
        let u = unit.map { " \($0)" } ?? ""
        return String(format: "\(fmt)-\(fmt)\(u)", lo, hi)
    }
    
    // Aggregations
    private func aggregateDistributionsLite(_ sessions: [SessionLite])
    -> (weight: [(String,Int)], reps: [(String,Int)], sets: [(String,Int)], duration: [(String,Int)],
        wbd:[String:[(String,Int)]], rbd:[String:[(String,Int)]], sbd:[String:[(String,Int)]], dbd:[String:[(String,Int)]]) {

        let weights:   [Double] = sessions.flatMap { s in s.items.compactMap { $0.weightKg   }.map { Double($0) } }
        let reps:      [Double] = sessions.flatMap { s in s.items.compactMap { $0.reps       }.map { Double($0) } }
        let sets:      [Double] = sessions.flatMap { s in s.items.compactMap { $0.sets       }.map { Double($0) } }
        let durations: [Double] = sessions.flatMap { s in s.items.compactMap { $0.duration   }.map { Double($0) } }

        let wBins = makeBins(minVal: weights.min() ?? 0,   maxVal: weights.max() ?? 0,   targetBins: 6)
        let rBins = makeBins(minVal: reps.min() ?? 0,      maxVal: reps.max() ?? 0,      targetBins: 6)
        let sBins = makeBins(minVal: sets.min() ?? 0,      maxVal: sets.max() ?? 0,      targetBins: 6)
        let dBins = makeBins(minVal: durations.min() ?? 0, maxVal: durations.max() ?? 0, targetBins: 6)


        func binCounts(values: [Double], bins: [ClosedRange<Double>], unit: String?) -> (rows:[(String,Int)], breakdown:[String:[(String,Int)]]) {
            var counts: [String:Int] = [:]
            var breakdown: [String:[Double:Int]] = [:]
            for v in values {
                guard let r = bins.first(where: { $0.contains(v) || (v == bins.last?.upperBound && $0.upperBound == v) }) else { continue }
                let key = label(r, unit: unit)
                counts[key, default: 0] += 1
                var inner = breakdown[key] ?? [:]
                inner[v, default: 0] += 1
                breakdown[key] = inner
            }
            let rows = counts.map { ($0.key, $0.value) }.sorted {
                extractLowerBound($0.0) < extractLowerBound($1.0)
            }
            let pretty: [String:[(String,Int)]] = breakdown.mapValues { dict in
                dict.map { kv in
                    let v = kv.key
                    let valLabel = unit == nil
                        ? (v.rounded() == v ? String(format: "%.0f", v) : String(format: "%.1f", v))
                        : (v.rounded() == v ? String(format: "%.0f%@", v, " \(unit!)") : String(format: "%.1f%@", v, " \(unit!)"))
                    return (valLabel, kv.value)
                }
                .sorted { $0.0 < $1.0 }
            }
            return (rows, pretty)
        }

        let w = binCounts(values: weights,   bins: wBins, unit: "kg")
        let r = binCounts(values: reps,      bins: rBins, unit: nil)
        let s = binCounts(values: sets,      bins: sBins, unit: nil)
        let d = binCounts(values: durations, bins: dBins, unit: nil)

        return (w.rows, r.rows, s.rows, d.rows, w.breakdown, r.breakdown, s.breakdown, d.breakdown)
    }
    
    private func extractLowerBound(_ label: String) -> Double {
        // try to read a number from the beginning of the bin label (e.g. "10–20 kg")
        let num = label
            .split(whereSeparator: { !$0.isNumber && $0 != "." && $0 != "," })
            .first
            .flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) } ?? 0
        return num
    }
    
    private func aggregateTimeSeriesLite(_ sessions: [SessionLite]) -> [TimePoint] {
        guard !sessions.isEmpty else { return [] }
        let dates = sessions.map { $0.date }
        let minD = dates.min()!; let maxD = dates.max()!
        let days = Calendar.current.dateComponents([.day], from: minD, to: maxD).day ?? 0
        let bucket = TimeBucketer.auto(daysSpan: days)
        var dict: [Date: Int] = [:]
        for s in sessions {
            let k = TimeBucketer.bucketDate(s.date, bucket: bucket)
            dict[k, default: 0] += s.items.count
        }
        let sortedDates = dict.keys.sorted()
        var running = 0
        var out: [TimePoint] = []
        for d in sortedDates {
            let v = dict[d] ?? 0
            running += v
            out.append(TimePoint(date: d, value: v, cumulative: running))
        }
        return out
    }
    private func fullDateRange() -> (start: Date, end: Date) {
        let cal = Calendar.current
        let todaySOD = cal.startOfDay(for: Date())
        let start = input.climbs.map { cal.startOfDay(for: $0.dateLogged) }.min() ?? todaySOD
        let latestSOD = input.climbs.map { cal.startOfDay(for: $0.dateLogged) }.max() ?? todaySOD
        let end = cal.date(byAdding: .second, value: -1,
                  to: cal.date(byAdding: .day, value: 1, to: latestSOD)!)!
        return (start, end)
    }

    private func isDateFiltered() -> Bool {
        let (s, e) = fullDateRange()
        return (dateRange.customStart != s) || (dateRange.customEnd != e)
    }
    var hasActiveFilters: Bool {
        isDateFiltered()
        || !trainingPlanIDs.isEmpty
        || !exerciseNames.isEmpty
    }
}

// MARK: - Climb VM
fileprivate final class ClimbStatsVM: ObservableObject {
    private var input: StatsInputData
    enum ClimbType: String, CaseIterable {
        case boulder = "Boulder"
        case sport = "Sport"
    }
    enum SportType: String, CaseIterable { case lead = "Lead", toprope = "Top rope" }
    enum WipFilter: String, CaseIterable { case all = "All", yes = "Yes", no = "No" }


    @Published var dateRange = DateRange(
            customStart: Calendar.current.startOfDay(for: Date()),
            customEnd:   Calendar.current.startOfDay(for: Date())
        )
    @Published var climbType: ClimbType? = nil
    @Published var sportType: SportType? = nil
    @Published var gyms: Set<String> = []
    @Published var grades: Set<String> = []
    @Published var styles: Set<String> = []
    
    @Published var totalClimbs: Int = 0
    @Published var totalAttempts: Int = 0
    @Published var climbsAttemptsRatioText: String = "-"

    @Published var availableGyms: [MultiPickOption] = []
    @Published var availableGrades: [MultiPickOption] = []
    @Published var availableStyles: [MultiPickOption] = []
    @Published var workInProgress: WipFilter = .all

    @Published var distStyle: [(String,Int)] = []
    @Published var distGrade: [(String,Int)] = []
    @Published var distAngle: [(String,Int)] = []

    @Published var timeSeries: [TimePoint] = []
    @Published var attemptsSeries: [TimePoint] = []
    @Published var ratioSeries: [TimePoint] = []

    @Published var styleByGradeStacks: [StackedBar<String,String>] = []
    @Published var seasonality: [SeasonalitySlice] = []
    @Published var gradeByStyleStacks: [StackedBar<String,String>] = []
    @Published var angleByGradeStacks: [StackedBar<String,String>] = []
    @Published var gradeByPrevStacks: [StackedBar<String,String>] = []

    @Published var sendRatioByGradeStyle: [(grade: String, style: String, ratio: Double)] = []
    @Published var sendRatioByGrade: [(grade: String, ratio: Double)] = []
    @Published var sendRatioByStyle: [(style: String, ratio: Double)] = []
    
    @Published var gradeFeelCells: [GradeFeelCell] = []
    @Published var preferFeelsLikeGrade: Bool = false




    init(input: StatsInputData) {
        self.input = input
        buildCatalogs()
        resetDateRangeToData()
        recomputeAll()
    }
    func updateInput(_ input: StatsInputData) {
        self.input = input
        if !input.climbs.isEmpty || !input.sessions.isEmpty || !input.plans.isEmpty {
            buildCatalogs()
            resetDateRangeToData()
            recomputeAll()
        }
    }
    func clearAll() {
        climbType = nil
        sportType = nil
        gyms.removeAll()
        grades.removeAll()
        styles.removeAll()
        workInProgress = .all
        resetDateRangeToData()
        recomputeAll()
    }
    private func resetDateRangeToData() {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let earliest = input.climbs.map(\.dateLogged).min().map { cal.startOfDay(for: $0) } ?? todayStart
        let latestSOD = input.climbs.map(\.dateLogged).max().map { cal.startOfDay(for: $0) } ?? todayStart
        let endOfDay = cal.date(byAdding: .second, value: -1,
                        to: cal.date(byAdding: .day, value: 1, to: latestSOD)!)!
        dateRange.customStart = earliest
        dateRange.customEnd   = endOfDay
    }

    private func filterByDate(_ climbs: [ClimbEntry]) -> [ClimbEntry] {
        let cal = Calendar.current
        let today = Date()
        let rawStart = dateRange.customStart ?? input.climbs.map(\.dateLogged).min() ?? today
        let rawEnd   = dateRange.customEnd   ?? input.climbs.map(\.dateLogged).max() ?? today
        let start = cal.startOfDay(for: rawStart)
        let end   = cal.date(byAdding: .second, value: -1,
                     to: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: rawEnd))!)!
        return climbs.filter { $0.dateLogged >= start && $0.dateLogged <= end }
    }

    
    private func buildCatalogs() {
        let climbs = input.climbs  // no date filtering here
        let gymsSet = Set(climbs.compactMap { e -> String? in
            // Exclude TB2 “fake gym” rows
            if let tb2 = e.tb2ClimbUUID, !tb2.isEmpty {
                if e.gym.isEmpty {
                    return nil
                }
                if e.gym == "Unknown" {
                    return nil
                }
                if let notes = e.notes, e.gym == notes {
                    return nil
                }
            }
            return e.gym
        })
        availableGyms = gymsSet.sorted().map { .init(id: $0, label: $0) }
        
        let gradeOptions: Set<String> = Set(
            climbs.flatMap { e -> [String] in
                var options: [String] = []

                // Normal grade
                let g = e.grade.trimmingCharacters(in: .whitespacesAndNewlines)
                if !g.isEmpty && g.lowercased() != "unknown" {
                    options.append(g)
                }

                // Feels-like grade
                if let feels = e.feelsLikeGrade?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    if !feels.isEmpty && feels.lowercased() != "unknown" {
                        options.append(feels)
                    }
                }

                return options
            }
        )
        availableGrades = gradeOptions.sorted().map { .init(id: $0, label: $0) }

        availableStyles = Set(climbs.map { $0.style }).sorted().map { .init(id: $0, label: $0) }
    }


    func recomputeAll() {
        // Pipeline
        let c1 = filterByDate(input.climbs)
        let c2: [ClimbEntry]
        if let t = climbType {
            // specific type (boulder or sport)
            c2 = c1.filter { $0.climbType.rawValue == t.rawValue }
        } else {
            // nil means both types
            c2 = c1
        }

        let c3: [ClimbEntry]
            if climbType == .sport, let st = sportType?.rawValue {
                c3 = c2.filter { $0.ropeClimbType?.rawValue == st }
            } else {
                c3 = c2
            }
        let c4: [ClimbEntry] = gyms.isEmpty ? c3 : c3.filter { entry in
            let g = entry.gym
            return gyms.contains(g)
        }
        let c5: [ClimbEntry] = styles.isEmpty ? c4 : c4.filter { styles.contains($0.style) }

        var filtered = grades.isEmpty ? c5 : c5.filter { grades.contains(resolvedGrade($0)) }

        switch workInProgress {
        case .all:
            break
        case .yes:
            filtered = filtered.filter { $0.isWorkInProgress }
        case .no:
            filtered = filtered.filter { !$0.isWorkInProgress }
        }

        // KPIs
        let nonWip = filtered.filter { !$0.isWorkInProgress }
        totalClimbs = nonWip.count
        totalAttempts = filtered.reduce(0) { $0 + parseAttempts($1.attempts) }
        if totalAttempts > 0 {
            let ratio = Double(totalClimbs) / Double(totalAttempts)
            climbsAttemptsRatioText = String(format: "%.2f", ratio)
        } else {
            climbsAttemptsRatioText = "-"
        }

        // Distributions
        let sendsBase = filtered.filter { !$0.isWorkInProgress }   // non-WIP “sends”
        
        gradeFeelCells = buildGradeFeelHeatmap(entries: filtered)  //grade vs feels-like matrix

        var style: [String:Int] = [:], grade: [String:Int] = [:], angle: [String:Int] = [:]

        for e in filtered {
            style[e.style, default: 0] += 1
            let a = e.angleDegrees.map { "\($0)°" } ?? "No Angle"; angle[a, default: 0] += 1
        }
        for e in sendsBase {
            let g = resolvedGrade(e)
            grade[g, default: 0] += 1
        }
        
        func sortPairs(_ d: [String:Int]) -> [(String,Int)] { d.map{($0.key,$0.value)}.sorted{ $0.1 > $1.1 } }
        distStyle = sortPairs(style); distGrade = sortPairs(grade); distAngle = sortPairs(angle)
        gradeByPrevStacks = buildGradeByPrevStacks(sends: sendsBase)



        // Time series (auto bucket) — count climbs per bucket
        timeSeries = aggregateTimeSeries(sendsBase)                // sends from non-WIP only

        let attemptsTS = aggregateAttemptsTimeSeries(sendsBase)    // attempts counted only for non-WIP
        attemptsSeries = attemptsTS
        ratioSeries = zip(timeSeries, attemptsTS).map { (sends, attempts) in
            let ratio = attempts.cumulative > 0 ? Double(sends.cumulative) / Double(attempts.cumulative) : 0
            return TimePoint(date: sends.date, value: Int((ratio * 1000).rounded()), cumulative: Int((ratio * 1000).rounded()))
        }

        // Stacked (Style × Grade)
        styleByGradeStacks = buildStacks(styles: style.keys, entries: filtered)
        // Seasonality slices (month x style)
        seasonality = buildSeasonality(entries: filtered)

        gradeByStyleStacks = buildGradeCentricStacks(entries: filtered)
        angleByGradeStacks = buildGradeByAngleStacks(entries: filtered)
        sendRatioByGrade = buildSendRatioPerGrade(sends: sendsBase, attemptsFrom: filtered)
        sendRatioByStyle = buildSendRatioPerStyle(sends: sendsBase, attemptsFrom: filtered)

    }


    private func aggregateTimeSeries(_ climbs: [ClimbEntry]) -> [TimePoint] {
        guard !climbs.isEmpty else { return [] }
        let dates = climbs.map { $0.dateLogged }
        let minD = dates.min()!; let maxD = dates.max()!
        let days = Calendar.current.dateComponents([.day], from: minD, to: maxD).day ?? 0
        let bucket = TimeBucketer.auto(daysSpan: days)
        var dict: [Date: Int] = [:]
        for e in climbs {
            let k = TimeBucketer.bucketDate(e.dateLogged, bucket: bucket)
            dict[k, default: 0] += 1
        }
        let sortedDates = dict.keys.sorted()
        var running = 0
        var out: [TimePoint] = []
        for d in sortedDates {
            let v = dict[d] ?? 0
            running += v
            out.append(TimePoint(date: d, value: v, cumulative: running))
        }
        return out
    }
    
    private func buildSendRatioPerGrade(
        sends: [ClimbEntry],            // non-WIP only
        attemptsFrom: [ClimbEntry]      // all filtered climbs (WIP + non-WIP)
    ) -> [(grade: String, ratio: Double)] {
        var sendCount:[String:Int] = [:]
        var attemptSum:[String:Int] = [:]

        // denominator: climbed (non-WIP)
        for e in sends {
            let g = resolvedGrade(e)
            sendCount[g, default: 0] += 1
        }
        for e in attemptsFrom {
            let g = resolvedGrade(e)
            attemptSum[g, default: 0] += parseAttempts(e.attempts)
        }
        func gkey(_ g:String)->Double { Double(g.replacingOccurrences(of:",", with:".")) ?? .infinity }
        return Set(sendCount.keys).union(attemptSum.keys).map { g in
            let sends = sendCount[g, default: 0]
            let attempts = attemptSum[g, default: 0]
            let ratio = sends == 0 ? 0.0 :  Double(sends) / Double(attempts)   //  sends(non-WIP) / attempts
            return (g, ratio)
        }
        .sorted { gkey($0.0) < gkey($1.0) }
    }


    private func buildSendRatioPerStyle(
        sends: [ClimbEntry],            // non-WIP only
        attemptsFrom: [ClimbEntry]      // all filtered climbs (WIP + non-WIP)
    ) -> [(style: String, ratio: Double)] {
        var sendCount:[String:Int] = [:]
        var attemptSum:[String:Int] = [:]

        // denominator: climbed (non-WIP)
        for e in sends { sendCount[e.style, default: 0] += 1 }

        // numerator: total attempts (all filtered)
        for e in attemptsFrom { attemptSum[e.style, default: 0] += parseAttempts(e.attempts) }

        return Set(sendCount.keys).union(attemptSum.keys).map { s in
            let sends = sendCount[s, default: 0]
            let attempts = attemptSum[s, default: 0]
            let ratio = sends == 0 ? 0.0 : Double(sends) / Double(attempts)    // sends(non-WIP)/ attempts
            return (s, ratio)
        }
        .sorted { $0.style < $1.style }
    }

    
    private func aggregateAttemptsTimeSeries(_ climbs: [ClimbEntry]) -> [TimePoint] {
        guard !climbs.isEmpty else { return [] }
        let dates = climbs.map { $0.dateLogged }
        let minD = dates.min()!; let maxD = dates.max()!
        let days = Calendar.current.dateComponents([.day], from: minD, to: maxD).day ?? 0
        let bucket = TimeBucketer.auto(daysSpan: days)
        var dict: [Date: Int] = [:]
        for e in climbs {
            let k = TimeBucketer.bucketDate(e.dateLogged, bucket: bucket)
            dict[k, default: 0] += parseAttempts(e.attempts)
        }
        let sortedDates = dict.keys.sorted()
        var running = 0
        var out: [TimePoint] = []
        for d in sortedDates {
            let v = dict[d] ?? 0
            running += v
            out.append(TimePoint(date: d, value: v, cumulative: running))
        }
        return out
    }

    private func buildStacks(styles: Dictionary<String,Int>.Keys, entries: [ClimbEntry]) -> [StackedBar<String,String>] {
        var out: [StackedBar<String,String>] = []

        let gradeSet = Set(entries.map { resolvedGrade($0) })

        for s in styles {
            var map: [String:Int] = [:]
            for g in gradeSet { map[g] = 0 }
            for e in entries {
                let g = resolvedGrade(e)
                if gradeSet.contains(g) && e.style == s {
                    map[g, default: 0] += 1
                }
            }
            out.append(.init(x: s, stacks: map))
        }
        out.sort { a,b in (a.stacks.values.reduce(0,+)) > (b.stacks.values.reduce(0,+)) }
        return out
    }




    private func buildGradeCentricStacks(entries: [ClimbEntry]) -> [StackedBar<String,String>] {
        var out: [StackedBar<String,String>] = []

        let grades = Array(Set(entries.map { resolvedGrade($0) }))
        let styles = Array(Set(entries.map { $0.style }))

        for g in grades {
            var map: [String:Int] = [:]
            for s in styles { map[s] = 0 }

            for e in entries {
                if resolvedGrade(e) == g {
                    map[e.style, default: 0] += 1
                }
            }

            out.append(.init(x: g, stacks: map))
        }

        out.sort { a, b in (a.stacks.values.reduce(0,+)) > (b.stacks.values.reduce(0,+)) }
        return out
    }


    private func buildGradeByAngleStacks(entries: [ClimbEntry]) -> [StackedBar<String,String>] {
        var out: [StackedBar<String,String>] = []

        let grades = Array(Set(entries.map { resolvedGrade($0) }))
        let angles = Array(Set(entries.map { $0.angleDegrees.map { "\($0)°" } ?? "No Angle" }))

        for g in grades {
            var map: [String:Int] = [:]
            for a in angles { map[a] = 0 }

            for e in entries {
                guard resolvedGrade(e) == g else { continue }

                let a = e.angleDegrees.map { "\($0)°" } ?? "No Angle"
                map[a, default: 0] += 1
            }

            out.append(.init(x: g, stacks: map))
        }

        out.sort { a,b in (a.stacks.values.reduce(0,+)) > (b.stacks.values.reduce(0,+)) }
        return out
    }


    private func buildGradeByPrevStacks(sends: [ClimbEntry]) -> [StackedBar<String,String>] {
        let prevKey = "Yes"
        let newKey  = "No"

        // consistent set of resolved grades
        let grades = Array(Set(sends.map { resolvedGrade($0) }))

        // initialize rows
        var mapByGrade: [String: [String:Int]] = [:]
        for g in grades {
            mapByGrade[g] = [prevKey: 0, newKey: 0]
        }

        // count sends per previous/new
        for e in sends {
            let g = resolvedGrade(e)
            let wasPrev = (e.isPreviouslyClimbed ?? false)

            if wasPrev {
                mapByGrade[g, default: [prevKey:0, newKey:0]][prevKey, default: 0] += 1
            } else {
                mapByGrade[g, default: [prevKey:0, newKey:0]][newKey, default: 0] += 1
            }
        }

        // turn into rows
        var out: [StackedBar<String,String>] = grades.map { g in
            .init(x: g, stacks: mapByGrade[g] ?? [prevKey:0, newKey:0])
        }

        // order by total desc
        out.sort { a, b in (a.stacks.values.reduce(0,+)) > (b.stacks.values.reduce(0,+)) }
        return out
    }

    
    private func buildSeasonality(entries: [ClimbEntry]) -> [SeasonalitySlice] {
        guard !entries.isEmpty else { return [] }
        var dict: [String: [Int: Double]] = [:] // style -> month -> value
        let cal = Calendar.current
        for e in entries {
            let m = cal.component(.month, from: e.dateLogged)
            dict[e.style, default: [:]][m, default: 0] += 1
        }
        // normalize by style total so shapes are comparable
        var out: [SeasonalitySlice] = []
        for (style, byMonth) in dict {
            let total = max(1.0, byMonth.values.reduce(0,+))
            for m in 1...12 { out.append(.init(month: m, style: style, value: (byMonth[m] ?? 0) / total)) }
        }
        return out
    }

    private func parseAttempts(_ s: String?) -> Int {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return 1 }
        let digits = s.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Int(digits) ?? 1
    }
    private func fullDateRange() -> (start: Date, end: Date) {
        let cal = Calendar.current
        let todaySOD = cal.startOfDay(for: Date())
        let start = input.climbs.map { cal.startOfDay(for: $0.dateLogged) }.min() ?? todaySOD
        let latestSOD = input.climbs.map { cal.startOfDay(for: $0.dateLogged) }.max() ?? todaySOD
        let end = cal.date(byAdding: .second, value: -1,
                  to: cal.date(byAdding: .day, value: 1, to: latestSOD)!)!
        return (start, end)
    }
    

    private func isDateFiltered() -> Bool {
        let (s, e) = fullDateRange()
        return (dateRange.customStart != s) || (dateRange.customEnd != e)
    }
    var hasActiveFilters: Bool {
        isDateFiltered()
        || climbType != nil
        || sportType != nil
        || !gyms.isEmpty
        || !grades.isEmpty
        || !styles.isEmpty
        || workInProgress != .all
    }
    
    private func resolvedGrade(_ e: ClimbEntry) -> String {
        let logged = e.grade.trimmingCharacters(in: .whitespacesAndNewlines)
        let feels  = e.feelsLikeGrade?.trimmingCharacters(in: .whitespacesAndNewlines)

        func isValid(_ s: String?) -> Bool {
            guard let s = s else { return false }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty && t.lowercased() != "unknown"
        }

        if preferFeelsLikeGrade {
            // “Prefer my grade” toggle  = ON → prefer feels-like
            if isValid(feels)  { return feels! }
            if isValid(logged) { return logged }
        } else {
            // “Prefer my grade” toggle = OFF → prefer logged grade
            if isValid(logged) { return logged }
            if isValid(feels)  { return feels! }
        }

        // Fallbacks
        if !logged.isEmpty { return logged }
        if let f = feels, !f.isEmpty { return f }
        return "Unknown"
    }


}

// MARK: - Time bucketing helper
fileprivate enum TimeBucketer { case day, week, month
    static func auto(daysSpan: Int) -> Self { daysSpan <= 30 ? .day : (daysSpan <= 180 ? .week : .month) }
    static func bucketDate(_ d: Date, bucket: Self) -> Date {
        let cal = Calendar.current
        switch bucket { case .day: return cal.startOfDay(for: d)
        case .week:
            let comp = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
            return cal.date(from: comp) ?? cal.startOfDay(for: d)
        case .month:
            let c = cal.dateComponents([.year, .month], from: d)
            return cal.date(from: c) ?? cal.startOfDay(for: d)
        }
    }
    static func formatTick(_ date: Date, bucket: Self) -> String {
        let f = DateFormatter(); f.locale = .current
        switch bucket { case .day: f.dateFormat = "d MMM"; case .week: f.dateFormat = "w''yy"; case .month: f.dateFormat = "MMM yy" }
        return f.string(from: date)
    }
}

// MARK: - Exercise UI
fileprivate struct ExerciseStatsView: View {
    @ObservedObject var vm: ExerciseStatsVM
    @State private var showPlanPicker = false
    @State private var showExercisePicker = false
    @State private var selectedExerciseDist: ExerciseDist = .weight
    @State private var didInit = false
    fileprivate enum ExerciseDist { case weight, reps, sets,duration}

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutGrid.sectionSpacing) {
            SectionDivider(label: "Filters")
            FilterCard {
                VStack(spacing: 8) {
                    HStack {
                        HStack {
                            Text("Date Range")
                            DateRangePicker(range: $vm.dateRange)
                        }
                        ClearAllButton(action: { vm.clearAll() }, isEnabled: vm.hasActiveFilters)
                    }
                    FilterRow(title: "Plans", value: summary(vm.trainingPlanIDs)) { showPlanPicker = true }
                        .sheet(isPresented: $showPlanPicker) {
                            MultiSelectSheet(title: "Plans", options: vm.availableTrainingPlans, selected: $vm.trainingPlanIDs)
                                .onDisappear { vm.recomputeAll()
                                    ReviewTrigger.shared.filtersChanged()}
                        }
                    FilterRow(title: "Exercise", value: summary(vm.exerciseNames)) { showExercisePicker = true }
                        .sheet(isPresented: $showExercisePicker) {
                            MultiSelectSheet(title: "Exercise", options: vm.availableExercises, selected: $vm.exerciseNames)
                                .onDisappear { vm.recomputeAll()
                                    ReviewTrigger.shared.filtersChanged()}
                        }
                }
            }

                KPIRow(left: KPICard(title: "Total sessions", value: vm.totalSessions), right: KPICard(title: "Total exercises", value: vm.totalExercises))

                // Exercise distributions selector
                Picker("", selection: $selectedExerciseDist) {
                    Text("Weight").tag(ExerciseDist.weight)
                    Text("Reps").tag(ExerciseDist.reps)
                    Text("Sets").tag(ExerciseDist.sets)
                    Text("Duration").tag(ExerciseDist.duration)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, LayoutGrid.outerHorizontal)

                switch selectedExerciseDist {
                case .weight:
                    DistributionCards(title: "Weight", rows: vm.distWeight, breakdown: vm.weightBreakdown)
                case .reps:
                    DistributionCards(title: "Reps", rows: vm.distReps, breakdown: vm.repsBreakdown)
                case .sets:
                    DistributionCards(title: "Sets", rows: vm.distSets, breakdown: vm.setsBreakdown)
                case .duration:
                    DistributionCards(title: "Duration", rows: vm.distDuration, breakdown: vm.durationBreakdown)
                }


                ExerciseTimeSeriesSection(title: "Exercise over time", points: vm.timeSeries)

            }
            .padding(.bottom, 24)
            //.frame(maxWidth: .infinity, alignment: .topLeading)
            .onChange(of: vm.dateRange) {
                vm.recomputeAll()
                ReviewTrigger.shared.filtersChanged()
            }
    }

    private func summary(_ set: Set<String>) -> String { set.isEmpty ? "All" : "\(set.count) selected" }
}

// MARK: - Climb UI
fileprivate struct ClimbStatsView: View {
    @ObservedObject var vm: ClimbStatsVM
    @State private var showGymPicker = false
    @State private var showStylePicker = false
    @State private var showGradePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutGrid.sectionSpacing) {
                SectionDivider(label: "Filters")
            FilterCard {
                VStack(spacing: 8) {
                    HStack {
                        HStack {
                            Text("Date Range")
                            DateRangePicker(range: $vm.dateRange)
                        }
                        ClearAllButton(action: { vm.clearAll() }, isEnabled: vm.hasActiveFilters)
                    }
                    
                    // Climb type — segmented with “All”
                    VStack(spacing: 8) {
                        // Climb type picker
                        HStack {
                            Text("Type")
                                .font(.callout)
                                .foregroundStyle(.primary)
                            Picker("", selection: Binding<ClimbStatsVM.ClimbType?>(
                                get: { vm.climbType },
                                set: { vm.climbType = $0 }
                            )) {
                                Text("All").tag(Optional<ClimbStatsVM.ClimbType>.none)
                                ForEach(ClimbStatsVM.ClimbType.allCases, id: \.self) {
                                    Text($0.rawValue).tag(Optional.some($0))
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .pickerStyle(.segmented)
                        
                        // Sport type picker (only when Sport selected)
                        if vm.climbType == .sport {
                            Picker("", selection: Binding<ClimbStatsVM.SportType?>(
                                get: { vm.sportType },
                                set: { vm.sportType = $0 }
                            )) {
                                Text("All").tag(Optional<ClimbStatsVM.SportType>.none)
                                ForEach(ClimbStatsVM.SportType.allCases, id: \.self) {
                                    Text($0.rawValue).tag(Optional.some($0))
                                }
                            }
                            .pickerStyle(.segmented)
                            //.padding(.horizontal)
                        }
                    }
                    .scrollDisabled(true)
                    .onChange(of: vm.climbType) { _, newValue in
                        if newValue != .sport { vm.sportType = nil }
                        vm.recomputeAll()
                    }
                    
                    
                    FilterRow(title: "Gym", value: summary(vm.gyms)) { showGymPicker = true }
                        .sheet(isPresented: $showGymPicker) {
                            MultiSelectSheet(title: "Gym", options: vm.availableGyms, selected: $vm.gyms)
                                .onDisappear { vm.recomputeAll() }
                        }
                    FilterRow(title: "Grade", value: summary(vm.grades)) { showGradePicker = true }
                        .sheet(isPresented: $showGradePicker) {
                            MultiSelectSheet(title: "Grade", options: vm.availableGrades, selected: $vm.grades)
                                .onDisappear { vm.recomputeAll() }
                        }
                    HStack(spacing: 4) {
                        Toggle(isOn: $vm.preferFeelsLikeGrade) {
                            InfoLabel(
                                text: "Prefer My Grade",
                                helpMessage: """
                                    When enabled, analytics prefer “My Grade”:
                                    If both grades exist → “My Grade” is used
                                    If only one exists → that grade is used
                                    """
                            )
                        }
                        .tint(.accentColor)
                    }
                    HStack {
                        Text("WIP?")
                            .font(.callout)
                            .foregroundStyle(.primary)
                        Picker("", selection: $vm.workInProgress) {
                            Text("All").tag(ClimbStatsVM.WipFilter.all)
                            Text("Yes").tag(ClimbStatsVM.WipFilter.yes)
                            Text("No").tag(ClimbStatsVM.WipFilter.no)
                        }
                        .pickerStyle(.segmented)
                    }
                    .pickerStyle(.segmented)
                    FilterRow(title: "Style", value: summary(vm.styles)) { showStylePicker = true }
                        .sheet(isPresented: $showStylePicker) {
                            MultiSelectSheet(title: "Style", options: vm.availableStyles, selected: $vm.styles)
                                .onDisappear { vm.recomputeAll() }
                        }
                }
            }

                HStack(spacing: 12) {
                    KPICard(title: "# sends", value: vm.totalClimbs)
                    KPICard(title: "# attempts", value: vm.totalAttempts)
                    KPITextCard(title: "send ratio", valueText: vm.climbsAttemptsRatioText)
                }
                .padding(.horizontal)

                DistributionCards(title: "Sends by Grade", rows: vm.distGrade, interactionsEnabled: false, vertical: true)
                StackedByIsPreviouslyClimbedSection(title: "Sends by Grade (Resends)",stacks: vm.gradeByPrevStacks)
                SendRatioSwitcherSection(gradeRows: vm.sendRatioByGrade, styleRows: vm.sendRatioByStyle)
                GradeVsFeelsLikeHeatmapSection(cells: vm.gradeFeelCells)
                StackedByGradeSection(title: "Grade by Angle", stacks: vm.angleByGradeStacks)
                ClimbTimeSeriesSection(title: "Climbs over time", sends: vm.timeSeries, attempts: vm.attemptsSeries, ratio: vm.ratioSeries)
                DistributionCards(title: "Sends by Style", rows: vm.distStyle, interactionsEnabled: false, vertical: false)
                StackedByGradeSection(title: "Grade By Style", stacks: vm.gradeByStyleStacks)
                SeasonalitySection(slices: vm.seasonality)
            }
            .padding(.bottom, 24)
            //.frame(maxWidth: .infinity, alignment: .topLeading)
            .onChange(of: vm.dateRange) {
                vm.recomputeAll()
                ReviewTrigger.shared.filtersChanged()
            }
            .onChange(of: vm.climbType) {
                vm.recomputeAll()
                ReviewTrigger.shared.filtersChanged()
            }
            .onChange(of: vm.sportType) {
                vm.recomputeAll()
                ReviewTrigger.shared.filtersChanged()
            }
            .onChange(of: vm.workInProgress) {
                vm.recomputeAll()
                ReviewTrigger.shared.filtersChanged()
            }
            .onChange(of: vm.preferFeelsLikeGrade) {
                vm.recomputeAll()
                ReviewTrigger.shared.filtersChanged()
            }
        }

    private func summary(_ set: Set<String>) -> String { set.isEmpty ? "All" : "\(set.count) selected" }
}

// MARK: - Distribution (horizontal bar )
fileprivate struct DistributionCards: View {
    let title: String
    let rows: [(label: String, count: Int)]
    let breakdown: [String: [(String, Int)]]
    let interactionsEnabled: Bool
    let vertical: Bool

    init(
        title: String,
        rows: [(label: String, count: Int)],
        breakdown: [String: [(String, Int)]] = [:],
        interactionsEnabled: Bool = true,
        vertical: Bool = false
    ) {
        self.title = title
        self.rows = rows
        self.breakdown = breakdown
        self.interactionsEnabled = interactionsEnabled
        self.vertical = vertical
    }

    @State private var selected: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if rows.isEmpty { EmptyStateCard() } else {
                Chart(rows.prefix(15), id: \.label) { row in
                    if vertical {
                        BarMark(x: .value("Category", row.label),
                                y: .value("Count", row.count))
                            .foregroundStyle(.green)
                            .cornerRadius(4)
                            .opacity(interactionsEnabled
                                     ? (selected == nil || selected == row.label ? 1 : 0.35)
                                     : 1)
                            .annotation(position: .top) { Text("\(row.count)").font(.caption).foregroundStyle(.secondary) }
                    } else {
                        BarMark(x: .value("Count", row.count),
                                y: .value("Category", row.label))
                            .cornerRadius(4)
                            .opacity(interactionsEnabled
                                     ? (selected == nil || selected == row.label ? 1 : 0.35)
                                     : 1)
                            .annotation(position: .trailing) { Text("\(row.count)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .frame(minHeight: vertical ? 220 : max(160, CGFloat(min(rows.count, 8)) * 28))
                .chartYAxis { AxisMarks(position: .leading) { AxisGridLine(); AxisTick(); AxisValueLabel().font(.caption) } }
                .if(interactionsEnabled && !breakdown.isEmpty) { view in
                    view.chartOverlay { proxy in
                        GeometryReader { geo in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 8)
                                        .onChanged { value in
                                            guard let plot = proxy.plotFrame else { return }
                                            let frame = geo[plot]
                                            guard frame.contains(value.location) else { return }
                                            if vertical {
                                                let x = value.location.x - frame.origin.x
                                                if let cat: String = proxy.value(atX: x) { selected = cat }
                                            } else {
                                                let y = value.location.y - frame.origin.y
                                                if let cat: String = proxy.value(atY: y) { selected = cat }
                                            }
                                        }
                                        .onEnded { _ in selected = nil }
                                )
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if let s = selected, let items = breakdown[s], !items.isEmpty {
                            // sort by count DESC, take top 3
                            let sorted = items.sorted { $0.1 > $1.1 }
                            let top3   = sorted.prefix(3)
                            let others = sorted.dropFirst(3)
                            let lines  = top3.map { "\($0.0) ×\($0.1)" }
                            let otherLine = others.isEmpty ? nil : "+ \(others.count) others"

                            let multiline = ([s] + lines + (otherLine.map { [$0] } ?? []))
                                .joined(separator: "\n")

                            TooltipPill(text: multiline).padding(8)
                        }
                    }
                }
            }
        }
        .padding(LayoutGrid.cardInner)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LayoutGrid.outerHorizontal)
    }
}

private extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}
fileprivate struct GradeFeelCell: Identifiable, Hashable {
    let id = UUID()
    let grade: String          // logged grade (X)
    let feelsLike: String      // feelsLikeGrade (Y)
    let count: Int
}

private func buildGradeFeelHeatmap(entries: [ClimbEntry]) -> [GradeFeelCell] {
    // Only keep climbs where both grade & feelsLike are non-empty and not "Unknown"
    var counts: [String: [String: Int]] = [:]

    for e in entries {
        let logged = e.grade.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !logged.isEmpty, logged.lowercased() != "unknown" else { continue }

        guard let feelsRaw = e.feelsLikeGrade?.trimmingCharacters(in: .whitespacesAndNewlines),
              !feelsRaw.isEmpty,
              feelsRaw.lowercased() != "unknown"
        else {
            continue
        }

        counts[logged, default: [:]][feelsRaw, default: 0] += 1
    }

    var cells: [GradeFeelCell] = []
    for (g, inner) in counts {
        for (f, c) in inner {
            cells.append(.init(grade: g, feelsLike: f, count: c))
        }
    }

    return cells
}
fileprivate struct GradeVsFeelsLikeHeatmapSection: View {
    let cells: [GradeFeelCell]

    // Distinct ordered axes
    private var xGrades: [String] {
        Array(Set(cells.map { $0.grade }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var yFeels: [String] {
        Array(Set(cells.map { $0.feelsLike }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var maxCount: Double {
        Double(cells.map(\.count).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Grade vs My Grade")
                .font(.headline)

            if cells.isEmpty {
                EmptyStateCard()
            } else {
                Chart(cells) { cell in
                    let intensity = Double(cell.count) / max(1, maxCount)

                    RectangleMark(
                        x: .value("Grade", cell.grade),
                        y: .value("My Grade", cell.feelsLike)
                    )
                    .foregroundStyle(Color.blue.opacity(0.15 + 0.85 * intensity))
                    .cornerRadius(4)
                    .annotation {
                        Text("\(cell.count)")
                            .font(.caption2)
                            .foregroundStyle(.primary)
                    }
                }
                .chartXScale(domain: xGrades)
                .chartYScale(domain: yFeels.reversed())
                .chartXAxisLabel("Grade", alignment: .center)
                .chartYAxisLabel("My Grade")
                .chartXAxis { AxisMarks(position: .bottom) }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: CGFloat(yFeels.count) * 32 + 60)



                .chartXScale(domain: xGrades)
                .chartYScale(domain: yFeels.reversed())
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel().font(.caption2)
                    }
                }

                .frame(height: CGFloat(yFeels.count) * 32 + 60)
            }
        }
        .padding(LayoutGrid.cardInner)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LayoutGrid.outerHorizontal)
    }
}

fileprivate struct SendRatioSwitcherSection: View {
    enum Mode: String, CaseIterable { case grade = "Grade", style = "Style" }
    let gradeRows: [(grade: String, ratio: Double)]
    let styleRows: [(style: String, ratio: Double)]
    @State private var mode: Mode = .grade

    var body: some View {
        VStack(spacing: 8) {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                Spacer()

            VStack(alignment: .leading, spacing: 12) {
                Text("Send Rate").font(.headline)

                if mode == .grade {
                    // Exclude "Unknown" or empty grades
                    let validGrades = gradeRows.filter {
                        !$0.grade.lowercased().contains("unknown") &&
                        !$0.grade.trimmingCharacters(in: .whitespaces).isEmpty
                    }

                    // Sort by send ratio descending
                    let sortedGrades = validGrades.sorted { $0.ratio > $1.ratio }

                    Chart(sortedGrades, id: \.grade) { row in
                        BarMark(
                            x: .value("Grade", row.grade),
                            y: .value("Send Ratio", row.ratio)
                        )
                        .foregroundStyle(.orange)
                        // Add label only if ratio < 1.0
                        if row.ratio < 0.999 {
                                PointMark(
                                    x: .value("Grade", row.grade),
                                    y: .value("Send Ratio", row.ratio)
                                )
                                .opacity(0) // invisible anchor for the annotation
                                .annotation(position: .top) {
                                    Text(String(format: "%.2f", row.ratio))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    .chartXScale(domain: sortedGrades.map { $0.grade })
                    .chartYScale(domain: 0...1)
                    .frame(height: 220)
                } else {
                    // Horizontal bars; order by style name (on Y axis)
                    let styleOrder = Array(Set(styleRows.map { $0.style })).sorted()

                    Chart(styleRows, id: \.style) { row in
                        BarMark(
                            x: .value("send ratio", row.ratio),
                            y: .value("style", row.style)     // horizontal
                        )
                        .foregroundStyle(.orange)
                        .annotation(position: .trailing) {
                            Text(String(format: "%.2f", row.ratio))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .chartYScale(domain: styleOrder)   // order by name
                    .chartXScale(domain: 0...1)
                    .frame(height: max(200, CGFloat(styleOrder.count) * 24 + 40))
                }
            }
            .padding(LayoutGrid.cardInner)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LayoutGrid.outerHorizontal)
        }
    }
}


// ExerciseTimeSeriesSection
fileprivate struct ExerciseTimeSeriesSection: View {
    let title: String
    let points: [TimePoint]                 // original series (monthly-like via auto bucketer)
    @State private var selectedDate: Date? = nil

    private var qPoints: [TimePoint] { groupToQuarters(points: points) }
    private var ticks: [Date] { quarterTicks(points: qPoints) }

    private var tooltipText: String? {
        guard
            let d = selectedDate,
            let nearestPoint = nearest(to: d, in: points)        // <- use ORIGINAL monthly points
        else { return nil }
        return "\(monthYearLabel(nearestPoint.date)) • total: \(nearestPoint.cumulative), here: \(nearestPoint.value)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)

            if qPoints.isEmpty {
                EmptyStateCard()
            } else {
                Chart(qPoints) { p in
                    LineMark(x: .value("Date", p.date),
                             y: .value("Total", p.cumulative))
                    PointMark(x: .value("Date", p.date),
                              y: .value("Total", p.cumulative))
                }
                .frame(height: 220)
                .chartXAxis {
                    AxisMarks(values: ticks) { val in
                        if let d = val.as(Date.self) {
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(quarterLabel(d))
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 8)
                                    .onChanged { value in
                                        guard let plot = proxy.plotFrame else { return }
                                        let frame = geo[plot]
                                        guard frame.contains(value.location) else { return }
                                        let x = value.location.x - frame.origin.x
                                        selectedDate = proxy.value(atX: x)
                                    }
                                    .onEnded { _ in selectedDate = nil }
                            )
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let text = tooltipText {
                        TooltipPill(text: text).padding(8)
                    }
                }
            }
        }
        .padding(LayoutGrid.cardInner)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LayoutGrid.outerHorizontal)
    }

    // quarter aggregation (same approach as climb)
    private func groupToQuarters(points: [TimePoint]) -> [TimePoint] {
        guard !points.isEmpty else { return [] }
        let cal = Calendar.current
        func quarterStart(of d: Date) -> Date {
            let comps = cal.dateComponents([.year, .month], from: d)
            let m = comps.month ?? 1
            let qStartMonth = ((m - 1) / 3) * 3 + 1
            return cal.date(from: DateComponents(year: comps.year, month: qStartMonth, day: 1)) ?? d
        }
        let grouped = Dictionary(grouping: points) { quarterStart(of: $0.date) }
            .mapValues { arr in arr.reduce(0) { $0 + $1.value } }

        let dates = grouped.keys.sorted()
        var running = 0
        return dates.map { d in
            let v = grouped[d] ?? 0
            running += v
            return TimePoint(date: d, value: v, cumulative: running)
        }
    }

    private func nearest(to date: Date, in pts: [TimePoint]) -> TimePoint? {
        pts.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    // same label as climb tooltip
    private func monthYearLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/yy"
        return f.string(from: d)
    }
}



// MARK: - Climb multi-series time series (sends, attempts, ratio)
fileprivate struct ClimbTimeSeriesSection: View {
    let title: String
    let sends: [TimePoint]
    let attempts: [TimePoint]
    let ratio: [TimePoint]      // scaled x1000
    @State private var selectedDate: Date? = nil

    private var qSends: [TimePoint] { groupToQuarters(points: sends) }
    private var qAttempts: [TimePoint] { groupToQuarters(points: attempts) }
    private var qRatio: [TimePoint] { buildQuarterlyCumulativeRatio(sends: qSends, attempts: qAttempts) }

    // Quarterly ticks & labels
    private var ticks: [Date] { quarterTicks(points: qSends) }

    private var tooltipText: String? {
        guard
            let d = selectedDate,
            let s = nearest(to: d, in: sends),
            let a = nearest(to: d, in: attempts),
            let r = nearest(to: d, in: ratio)
        else { return nil }

        let ratioVal = Double(r.cumulative) / 1000.0
        return "\(monthYearLabel(s.date)) • sends: \(s.cumulative), attempts: \(a.cumulative), ratio: \(String(format: "%.2f", ratioVal))"
    }
    // Helper
    private func monthYearLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/yy"
        return f.string(from: d)
    }

    var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline)

                if qSends.isEmpty {
                    EmptyStateCard()
                } else {
                    ClimbChartView(
                        sends: qSends,
                        attempts: qAttempts,
                        ratio: qRatio,
                        ticks: ticks,
                        bucket: .month,               // unused for label now; placeholder
                        onHoverDate: { selectedDate = $0 }
                    )
                    .frame(height: 220)
                    .overlay(alignment: .topTrailing) {
                        if let text = tooltipText {
                            TooltipPill(text: text).padding(8)
                        }
                    }
                }
            }
            .padding(LayoutGrid.cardInner)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LayoutGrid.outerHorizontal)    }

    // MARK: - Helpers
    private func inferBucket(points: [TimePoint]) -> TimeBucketer {
        guard let first = points.first?.date, let last = points.last?.date else { return .week }
        let span = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
        return TimeBucketer.auto(daysSpan: span)
    }
    
    // MARK: - Quarter aggregation helpers (place inside ClimbTimeSeriesSection)

    private func groupToQuarters(points: [TimePoint]) -> [TimePoint] {
        guard !points.isEmpty else { return [] }
        let cal = Calendar.current

        func quarterStart(of d: Date) -> Date {
            let comps = cal.dateComponents([.year, .month], from: d)
            let m = comps.month ?? 1
            let qStartMonth = ((m - 1) / 3) * 3 + 1
            return cal.date(from: DateComponents(year: comps.year, month: qStartMonth, day: 1)) ?? d
        }

        // Sum VALUES per quarter
        let grouped = Dictionary(grouping: points) { quarterStart(of: $0.date) }
            .mapValues { arr in arr.reduce(0) { $0 + $1.value } }

        // Build running cumulative across quarters (sorted by date)
        let dates = grouped.keys.sorted()
        var running = 0
        return dates.map { d in
            let v = grouped[d] ?? 0
            running += v
            return TimePoint(date: d, value: v, cumulative: running)
        }
    }

    private func buildQuarterlyCumulativeRatio(sends: [TimePoint], attempts: [TimePoint]) -> [TimePoint] {
        // assumes both arrays are quarterly & sorted by date
        let byDateS = Dictionary(uniqueKeysWithValues: sends.map { ($0.date, $0.cumulative) })
        let byDateA = Dictionary(uniqueKeysWithValues: attempts.map { ($0.date, $0.cumulative) })
        let allDates = Set(byDateS.keys).union(byDateA.keys).sorted()

        return allDates.map { d in
            let sCum = byDateS[d] ?? 0
            let aCum = byDateA[d] ?? 0
            let ratio = aCum > 0 ? Double(sCum) / Double(aCum) : 0.0
            let scaled = Int((ratio * 1000).rounded())
            return TimePoint(date: d, value: scaled, cumulative: scaled)
        }
    }

    // Quarterly ticks & labels (reuse from previous step)
    private func quarterTicks(points: [TimePoint]) -> [Date] {
        guard let minD = points.first?.date, let maxD = points.last?.date else { return [] }
        let cal = Calendar.current

        func quarterStart(of d: Date) -> Date {
            let comps = cal.dateComponents([.year, .month], from: d)
            let m = comps.month ?? 1
            let qStartMonth = ((m - 1) / 3) * 3 + 1
            return cal.date(from: DateComponents(year: comps.year, month: qStartMonth, day: 1)) ?? d
        }

        var cur = quarterStart(of: minD)
        var out: [Date] = []
        while cur <= maxD {
            out.append(cur)
            cur = cal.date(byAdding: .month, value: 3, to: cur)!
        }
        if out.count <= 8 { return out }
        let step = max(1, out.count / 8)
        return out.enumerated().compactMap { idx, d in (idx % step == 0) ? d : nil }
    }

    private func quarterLabel(_ d: Date) -> String {
        let cal = Calendar.current
        let m = cal.component(.month, from: d)
        let q = ((m - 1) / 3) + 1
        let yy = cal.component(.year, from: d) % 100
        return "Q\(q)/\(String(format: "%02d", yy))"
    }


    private func chooseTicks(points: [TimePoint], bucket: TimeBucketer) -> [Date] {
        let dates = points.map { $0.date }
        guard let minD = dates.min(), let maxD = dates.max() else { return [] }
        let all = strideDates(from: minD, to: maxD, bucket: bucket)
        if all.count <= 7 { return all }
        let step = max(1, all.count / 7)
        return all.enumerated().compactMap { idx, date in (idx % step == 0) ? date : nil }
    }

    private func strideDates(from: Date, to: Date, bucket: TimeBucketer) -> [Date] {
        var out: [Date] = []
        var cur = TimeBucketer.bucketDate(from, bucket: bucket)
        let cal = Calendar.current
        while cur <= to {
            out.append(cur)
            cur = cal.date(byAdding: (bucket == .day ? .day : (bucket == .week ? .weekOfYear : .month)), value: 1, to: cur)!
        }
        return out
    }

    private func nearest(to date: Date, in pts: [TimePoint]) -> TimePoint? {
        pts.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

fileprivate struct ClimbChartView: View {
    let sends: [TimePoint]
    let attempts: [TimePoint]
    let ratio: [TimePoint]      // scaled x1000
    let ticks: [Date]
    let bucket: TimeBucketer
    let onHoverDate: (Date?) -> Void

    var body: some View {
        let leftMax = max(
            sends.map(\.cumulative).max() ?? 1,
            attempts.map(\.cumulative).max() ?? 1
        )
        Chart {
            // Sends & Attempts on left axis
            ForEach(sends, id: \.date) { p in
                LineMark(
                    x: .value("Date", p.date),
                    y: .value("Left", p.cumulative)
                )
                .foregroundStyle(by: .value("Series", "Sends"))
            }
            ForEach(attempts, id: \.date) { p in
                LineMark(
                    x: .value("Date", p.date),
                    y: .value("Left", p.cumulative)
                )
                .foregroundStyle(by: .value("Series", "Attempts"))
            }

            // Ratio scaled to left axis range (0...1 → 0...leftMax)
            ForEach(Array(ratio.enumerated()), id: \.offset) { _, p in
                let r = Double(p.cumulative) / 1000.0
                LineMark(
                    x: .value("Date", p.date),
                    y: .value("Left", r * Double(leftMax))
                )
                .interpolationMethod(.linear)
                .foregroundStyle(by: .value("Series", "Ratio"))
            }
        }
        .chartXAxis {
            AxisMarks(values: ticks) { v in
                if let d = v.as(Date.self) {
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(quarterLabel(d))
                }
            }
        }
        .chartYAxis {
            // LEFT: normal cumulative values
            AxisMarks(position: .leading)

            // RIGHT: scaled 0–1 labels mapped from leftMax
            AxisMarks(position: .trailing) { v in
                AxisTick()
                if let raw = v.as(Double.self) {
                    let val = max(0, min(1, raw / Double(leftMax)))
                    AxisValueLabel(String(format: "%.1f", val))
                }
            }
        }
        .chartForegroundStyleScale([
            "Sends": .green,
            "Attempts": .blue,
            "Ratio": .orange
        ])
        .chartLegend(position: .bottom, alignment: .trailing)

        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                guard let plot = proxy.plotFrame else { return }
                                let frame = geo[plot]
                                guard frame.contains(value.location) else { return }
                                let x = value.location.x - frame.origin.x
                                onHoverDate(proxy.value(atX: x) as Date?)
                            }
                            .onEnded { _ in onHoverDate(nil) }
                    )
            }
        }
    }
}
// Helpers (place near other helpers in ClimbTimeSeriesSection)
private func quarterTicks(points: [TimePoint]) -> [Date] {
    guard let minD = points.first?.date, let maxD = points.last?.date else { return [] }
    let cal = Calendar.current

    func quarterStart(of d: Date) -> Date {
        let comps = cal.dateComponents([.year, .month], from: d)
        let m = comps.month ?? 1
        let qStartMonth = ((m - 1) / 3) * 3 + 1
        return cal.date(from: DateComponents(year: comps.year, month: qStartMonth, day: 1)) ?? d
    }

    var cur = quarterStart(of: minD)
    var out: [Date] = []
    while cur <= maxD {
        out.append(cur)
        cur = cal.date(byAdding: .month, value: 3, to: cur)!
    }

    // thin to ~8 ticks max
    if out.count <= 8 { return out }
    let step = max(1, out.count / 8)
    return out.enumerated().compactMap { idx, d in (idx % step == 0) ? d : nil }
}

private func quarterLabel(_ d: Date) -> String {
    let cal = Calendar.current
    let m = cal.component(.month, from: d)
    let q = ((m - 1) / 3) + 1
    let yy = cal.component(.year, from: d) % 100
    return "Q\(q)/\(String(format: "%02d", yy))"
}


fileprivate struct StackedByIsPreviouslyClimbedSection: View {
    let title: String
    let stacks: [StackedBar<String, String>]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if stacks.isEmpty {
                EmptyStateCard()
            } else {
                let wanted = ["No", "Yes"] // stack order: "No" at bottom, "Yes" on top
                Chart {
                    ForEach(stacks) { row in
                        let total = row.stacks.values.reduce(0, +)

                        ForEach(wanted, id: \.self) { seg in
                            let v = row.stacks[seg] ?? 0
                            BarMark(
                                x: .value("Grade", row.x),
                                y: .value("Count", v),
                                stacking: .standard
                            )
                            .cornerRadius(4)
                            .foregroundStyle(by: .value("Segment", seg))
                            .annotation(position: .top, alignment: .center) {
                                if seg == wanted.last, total > 0 {
                                    Text("\(total)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // consistent green palette like “Sends by Grade”
                .chartForegroundStyleScale([
                    "Yes": Color.yellow,
                    "No": Color.green
                ])
                .chartLegend(.automatic)
                .frame(height: 220)
                .chartXAxis { AxisMarks(position: .bottom) }
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisValueLabel().font(.caption)
                    }
                }
            }
        }
        .padding(LayoutGrid.cardInner)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LayoutGrid.outerHorizontal)
    }
}


// MARK: - Grade stack charts
fileprivate struct StackedByGradeSection: View {
    let title: String
    let stacks: [StackedBar<String,String>]
    @State private var selectedGrade: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if stacks.isEmpty { EmptyStateCard() } else {
                let (compressed, segments) = compressStacks(stacks: stacks, topN: 8)
                let orderedSegments = segments.sorted { $0.localizedStandardCompare($1) == .orderedAscending }

                Chart {
                    ForEach(compressed) { row in
                        ForEach(orderedSegments, id: \.self) { seg in
                            let v = row.stacks[seg] ?? 0
                            BarMark(x: .value("Count", v),
                                    y: .value("Grade", row.x),
                                    stacking: .standard)
                                .foregroundStyle(by: .value("Segment", seg))
                        }
                    }
                }
                .chartLegend(position: .bottom, spacing: 1)
                .frame(height: CGFloat(min(stacks.count, 8)) * 34 + 140)
                .chartXAxis { AxisMarks(position: .bottom) }
                .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel().font(.caption) } }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        ChartTouchOverlay(
                            proxy: proxy,
                            geo: geo,
                            stacks: stacks,
                            selectedGrade: $selectedGrade
                        )
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let g = selectedGrade,
                       let row = stacks.first(where: { $0.x == g }) {
                        // sort by count DESC, take top 3
                        let sorted = row.stacks
                            .filter { $0.value > 0 }
                            .sorted { $0.value > $1.value }

                        let top3   = sorted.prefix(3)
                        let others = sorted.dropFirst(3)

                        let lines = top3.map { "\($0.key) ×\($0.value)" }
                        let otherLine = others.isEmpty ? nil : "+ \(others.count) others"

                        let multiline = ([g] + lines + (otherLine.map { [$0] } ?? []))
                            .joined(separator: "\n")

                        if !lines.isEmpty || otherLine != nil {
                            TooltipPill(text: multiline).padding(8)
                        }
                    }
                }
            }
        }
        .padding(LayoutGrid.cardInner)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LayoutGrid.outerHorizontal)
    }
    
    fileprivate struct ChartTouchOverlay: View {
        let proxy: ChartProxy
        let geo: GeometryProxy
        let stacks: [StackedBar<String,String>]
        @Binding var selectedGrade: String?

        var body: some View {
            guard let plotFrame = proxy.plotFrame else {
                return AnyView(Color.clear)
            }

            let frame = geo[plotFrame]

            return AnyView(
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                handleTouch(value, frame: frame)
                            }
                            .onEnded { _ in
                                // Optional: keep tooltip or clear it
                                // selectedGrade = nil
                            }
                    )
            )
        }

        private func handleTouch(_ value: DragGesture.Value, frame: CGRect) {
            guard frame.contains(value.location) else {
                selectedGrade = nil
                return
            }

            let x = value.location.x - frame.origin.x
            let y = value.location.y - frame.origin.y

            guard
                let g: String = proxy.value(atY: y),
                let xVal: Double = proxy.value(atX: x),
                let row = stacks.first(where: { $0.x == g })
            else {
                selectedGrade = nil
                return
            }

            let total = Double(row.stacks.values.reduce(0, +))
            if total > 0, xVal >= 0, xVal <= total {
                selectedGrade = g
            } else {
                selectedGrade = nil
            }
        }
    }




    // keep only top N segments by total count, group others into "Other"
    private func compressStacks(
        stacks: [StackedBar<String,String>],
        topN: Int = 8
    ) -> ([StackedBar<String,String>], [String]) {
        // 1) Totals per segment across all rows
        var totals: [String:Int] = [:]
        for row in stacks {
            for (k, v) in row.stacks { totals[k, default: 0] += v }
        }

        // 2) Top-N segment keys by total desc
        let topKeys = totals
            .sorted { $0.value > $1.value }
            .prefix(topN)
            .map { $0.key }

        // 3) Rebuild rows: keep top keys, group others into "Other"
        var anyOther = false
        let compressed: [StackedBar<String,String>] = stacks.map { row in
            var map: [String:Int] = [:]
            var otherSum = 0
            for (k, v) in row.stacks {
                if topKeys.contains(k) {
                    map[k, default: 0] += v
                } else {
                    otherSum += v
                }
            }
            if otherSum > 0 {
                map["Other"] = otherSum
                anyOther = true
            }
            return .init(x: row.x, stacks: map)
        }

        // 4) Legend (segments) order: top keys then "Other" if present
        let segments = topKeys + (anyOther ? ["Other"] : [])
        return (compressed, segments)
    }
}

// MARK: - Seasonality
fileprivate struct SeasonalitySection: View {
    let slices: [SeasonalitySlice]
    @State private var focusTopN: Int = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Styles heatmap").font(.headline)

            if slices.isEmpty {
                EmptyStateCard()
            } else {
                SeasonalityHeatmap(slices: slices, topN: focusTopN)
                    .frame(height: 260)
            }
        }
        .padding(LayoutGrid.cardInner)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LayoutGrid.outerHorizontal)
    }
}

fileprivate struct HeatCell: Identifiable, Hashable {
    let id = UUID()
    let style: String
    let month: Int
    let value: Double
}

fileprivate struct SeasonalityHeatmap: View {
    let slices: [SeasonalitySlice]
    let topN: Int

    var body: some View {
        let grouped = Dictionary(grouping: slices, by: { $0.style })
        let ranked = grouped.mapValues { arr in arr.reduce(0) { $0 + $1.value } }
        let styles = Array(ranked.sorted { $0.value > $1.value }.prefix(topN)).map { $0.key }
        let grid: [HeatCell] = styles.flatMap { st in (1...12).map { m in HeatCell(style: st, month: m, value: slices.first(where: { $0.style == st && $0.month == m })?.value ?? 0) } }
        Chart(grid) { cell in
            RectangleMark(
                x: .value("Month", shortMonth(cell.month)),
                y: .value("Style", cell.style)
            )
            .foregroundStyle(by: .value("Value", cell.value))   // map numeric → color
        }
        .chartForegroundStyleScale(range: Gradient(colors: [.blue, .red]))
        .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel().font(.caption) } }
        .chartXAxis { AxisMarks(position: .bottom) }
    }
}

// MARK: - Shared UI
struct ClearAllButton: View {
    var action: () -> Void
    var isEnabled: Bool = true

    var body: some View {
        Button(action: {
            if isEnabled { action() }
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    (isEnabled ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.1))
                )
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(.secondary.opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(isEnabled ? 0.1 : 0.0), radius: 1, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}




fileprivate struct FilterCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(LayoutGrid.cardInner)  // 12pt inner
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .padding(.horizontal, LayoutGrid.outerHorizontal) // 16pt from screen edge
    }
}


fileprivate struct SectionDivider: View {
    var label: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .frame(width: 4)
                .foregroundStyle(.secondary)
                .opacity(0.3)
            Text(label.uppercased())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, LayoutGrid.outerHorizontal)
        .padding(.top, 8)
    }
}


fileprivate struct FilterRow: View {
    let title: String
    let value: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

fileprivate struct KPICard: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Text("\(value)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(LayoutGrid.cardInner)
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

fileprivate struct KPITextCard: View {
    let title: String
    let valueText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(valueText)
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(LayoutGrid.cardInner)
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

fileprivate struct KPIRow<Left: View, Right: View>: View {
    var left: Left
    var right: Right

    init(left: Left, right: Right) {
        self.left = left
        self.right = right
    }

    var body: some View {
        HStack(spacing: 12) {
            left
            right
        }
        .padding(.horizontal, LayoutGrid.outerHorizontal)
    }
}


struct DateRangePicker: View {
    @Binding var range: DateRange
    @State private var isPresenting = false

    // Shared formatter
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        //f.locale = Locale(identifier: "de_DE")
        return f
    }()

    private var labelText: String {
        let f = Self.formatter

        switch (range.customStart, range.customEnd) {
        case let (start?, end?):
            return "\(f.string(from: start)) – \(f.string(from: end))"
        case let (start?, nil):
            return "\(f.string(from: start)) – …"
        case (nil, let end?):
            return "… – \(f.string(from: end))"
        default:
            return "Any time"
        }
    }

    var body: some View {
        Button {
            isPresenting = true
        } label: {
            HStack(spacing: 4) {
                Text(labelText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "calendar")
                    .imageScale(.small)
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresenting) {
            DateRangeSheet(range: $range, isPresented: $isPresenting)
                .presentationDetents([.medium, .large])
        }
    }
}

fileprivate struct DateRangeSheet: View {
    @Binding var range: DateRange
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Date range") {
                    DatePicker(
                        "Start Date",
                        selection: Binding(
                            get: { range.customStart ?? Date() },
                            set: { newStart in
                                range.customStart = newStart
                                if let end = range.customEnd, end < newStart {
                                    range.customEnd = newStart
                                }
                            }
                        ),
                        displayedComponents: .date
                    )

                    DatePicker(
                        "End Date",
                        selection: Binding(
                            get: { range.customEnd ?? (range.customStart ?? Date()) },
                            set: { newEnd in
                                if let start = range.customStart, newEnd < start {
                                    range.customEnd = start
                                } else {
                                    range.customEnd = newEnd
                                }
                            }
                        ),
                        displayedComponents: .date
                    )
                }
            }
            .navigationTitle("Select dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}





fileprivate struct MultiSelectSheet: View {
    let title: String; let options: [MultiPickOption]; @Binding var selected: Set<String>
    @Environment(\.dismiss) private var dismiss; @State private var query = ""
    var body: some View {
        NavigationStack {
            List(filtered(options)) { o in
                Button { toggle(o.id) } label: { HStack { Text(o.label); Spacer(); if selected.contains(o.id) { Image(systemName: "checkmark") } } }
            }
            .searchable(text: $query)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("None") { selected.removeAll() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("All") { selected = Set(options.map { $0.id }) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    private func filtered(_ o: [MultiPickOption]) -> [MultiPickOption] { query.isEmpty ? o : o.filter { $0.label.localizedCaseInsensitiveContains(query) } }
    private func toggle(_ id: String) { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }
}

fileprivate struct TooltipPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 140, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.secondary.opacity(0.3), lineWidth: 0.5)
            )
    }
}


fileprivate struct EmptyStateCard: View { var body: some View { HStack { Image(systemName: "exclamationmark.triangle"); Text("No data for current filters.") }.font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 16).background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 12)) } }

// MARK: - Cached date formatters
private let monthFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM"
    return f
}()

private let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "dd MMM"
    return f
}()

// MARK: - Helpers using cached formatters
private func shortMonth(_ m: Int) -> String {
    guard let date = Calendar.current.date(from: DateComponents(year: 2024, month: m, day: 1)) else { return "" }
    return monthFormatter.string(from: date)
}

private func shortDate(_ d: Date) -> String {
    return dayFormatter.string(from: d)
}

final class ReviewTrigger {
    static let shared = ReviewTrigger()

    @AppStorage("filterReviewTriggerCount") private var counter = 0

    func filtersChanged() {
        counter += 1

        // Trigger after 45 filters - decent usage
        if counter == 45 {
            requestReviewIfEligible()
        }
    }

    private func requestReviewIfEligible() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }

        SKStoreReviewController.requestReview(in: scene)
    }
}

fileprivate extension DateFormatter { func then(_ block: (DateFormatter)->Void) -> DateFormatter { block(self); return self } }

// MARK: - Preview
#Preview { NavigationStack { ProgressViewScreen() } }

