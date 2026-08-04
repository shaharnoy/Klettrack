//
//  TB2SyncManager.swift
//  Klettrack
//  Created by Shahar Noy on 29.09.25.
//

import Foundation
import SwiftData

enum TB2SyncManager {
    enum SyncStage: String, Sendable {
        case loggingIn
        case cachingClimbs
        case cachingClimbStats
        case loadingDifficulties
        case loadingLogbook
        case applyingRows
        case backfillingNames
        case backfillingGrades
        case finished
    }

    struct SyncProgress: Sendable {
        let stage: SyncStage
        let page: Int?
        let isComplete: Bool?

        init(stage: SyncStage, page: Int? = nil, isComplete: Bool? = nil) {
            self.stage = stage
            self.page = page
            self.isComplete = isComplete
        }
    }

    struct ClimbCacheState {
        let isComplete: Bool
        let lastSynchronizedAt: String?
    }

    typealias ClimbStatsCacheState = ClimbCacheState

    private static let longCacheRefreshIntervalMonths = 6

    /// Returns whether the next TB2 refresh may need to rebuild a large cache.
    /// Both metadata caches are required for the refreshed climb data to be complete.
    static func cacheRefreshMayTakeLong(for board: TB2Client.Board, now: Date = Date()) -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        guard let cutoff = calendar.date(
            byAdding: .month,
            value: -longCacheRefreshIntervalMonths,
            to: now
        ) else {
            return true
        }

        return [climbCacheState(for: board), climbStatsCacheState(for: board)].contains { state in
            guard state.isComplete, let lastSynchronizedAt = state.lastSynchronizedAt,
                  let lastSyncDate = BoardDateParser.parse(lastSynchronizedAt) else {
                return true
            }
            return lastSyncDate < cutoff
        }
    }

    struct DiffKey: Hashable {
        let uuid: String
        let angle: Int
    }
    struct DiffRec {
        let displayedDifficulty: Int?
        let isBenchmark: Bool
    }
    // Row moved to type scope so we can pass it into a @MainActor function
    struct Row {
        let climbUUID: String
        let angle: Int?
        let isMirror: Bool?
        let day: Date
        let climbName: String?
        let loggedDifficultyNum: Int?
        let displayedDifficultyNum: Int?
        let loggedGrade: String?
        let displayedGrade: String?
        let isBenchmark: Bool
        let tries: Int
        let isAscent: Bool
        let comment: String?
    }
    
    static func sync(
        using creds: TB2Credentials,
        board: TB2Client.Board,
        into context: ModelContext,
        progress: (@MainActor (SyncProgress) -> Void)? = nil
    ) async throws {
        let client = TB2Client()
        
        // Login -> token
        await progress?(SyncProgress(stage: .loggingIn))
        try Task.checkCancellation()
        let token = try await client.login(board: board, username: creds.username, password: creds.password)
        try Task.checkCancellation()
        
        //Fetch shared maps: cached climb names, cached stats grades + difficulties
        let (climbsByUUID, statsByKey, diffByKey, fallbackDiffs, climbCacheComplete, statsCacheComplete) = try await fetchSharedMaps(
            client: client,
            board: board,
            token: token,
            into: context,
            progress: progress
        )
        try Task.checkCancellation()
        
        //Pull ascents and bids
        await progress?(SyncProgress(stage: .loadingLogbook))
        async let ascPages = client.syncPages(
            board: board,
            tablesAndSyncDates: ["ascents": TB2Client.Constants.baseSyncDate],
            token: token,
            maxPages: TB2Client.Constants.defaultMaxSyncPages,
            progress: { page, _ in
                progress?(SyncProgress(stage: .loadingLogbook, page: page, isComplete: false))
            }
        )
        async let bidPages = client.syncPages(
            board: board,
            tablesAndSyncDates: ["bids": TB2Client.Constants.baseSyncDate],
            token: token,
            maxPages: TB2Client.Constants.defaultMaxSyncPages,
            progress: { page, _ in
                progress?(SyncProgress(stage: .loadingLogbook, page: page, isComplete: false))
            }
        )
        let ascents = (try await ascPages).flatMap { $0.ascents ?? [] }
        let bids    = (try await bidPages).flatMap { $0.bids ?? [] }
        try Task.checkCancellation()
        
        // 4) Summarize bids (tries per day/climb/angle/mirror)
        struct BidKey: Hashable { let uuid: String; let day: Date; let angle: Int?; let isMirror: Bool? }
        struct BidSum { var tries: Int; var comment: String? }
        //let cal = Calendar.current
        var bidSummary: [BidKey: BidSum] = [:]
        
        for b in bids {
            guard let uuid = b.climbUUID else { continue }
            guard let date = BoardDateParser.parseTensionClimbedAt(b.climbedAt) else { continue } // strict: no fallback to now
            let day = date
            let key = BidKey(uuid: uuid, day: day, angle: b.angle, isMirror: b.isMirror)
            var sum = bidSummary[key] ?? BidSum(tries: 0, comment: nil)
            sum.tries += (b.bidCount ?? 1)
            if sum.comment == nil {
                let c = (b.comment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !c.isEmpty { sum.comment = c }
            }
            bidSummary[key] = sum
        }
        
        // 5) Build ascent rows (merge bids tries)
        func displayedDiffFor(uuid: String?, angle: Int?) -> (Int?, Bool) {
            guard let uuid = uuid else { return (nil, false) }
            if let angle = angle, let rec = diffByKey[DiffKey(uuid: uuid, angle: angle)], rec.displayedDifficulty != nil {
                return (rec.displayedDifficulty, rec.isBenchmark)
            }
            let vals = fallbackDiffs[uuid] ?? []
            if vals.isEmpty { return (nil, false) }
            // mode
            var counts: [Int: Int] = [:]
            for v in vals.compactMap({ $0 }) { counts[v, default: 0] += 1 }
            let best = counts.max { $0.value < $1.value }?.key
            return (best, false)
        }

        func statsDifficultyFor(uuid: String?, angle: Int?) -> Int? {
            guard let uuid, let angle else { return nil }
            return statsByKey[DiffKey(uuid: uuid, angle: angle)]
        }
        
        var rows: [Row] = []
        for a in ascents {
            if let listed = a.isListed, listed == false { continue }
            let uuid = a.climbUUID
            let angle = a.angle
            let (dispNum, benchFlag) = displayedDiffFor(uuid: uuid, angle: angle)
            let loggedNum = a.difficulty ?? statsDifficultyFor(uuid: uuid, angle: angle)
            let disp = dispNum ?? loggedNum
            let loggedGrade = BoardGradeMapper.grade(of: loggedNum)
            let displayedGrade = BoardGradeMapper.grade(of: disp)
            guard let date = BoardDateParser.parseTensionClimbedAt(a.climbedAt) else { continue }
            let day = date
            let tries = (a.bidCount ?? a.attemptID ?? 1)
            let key = BidKey(uuid: uuid ?? "", day: day, angle: angle, isMirror: a.isMirror)
            let extra = bidSummary[key]?.tries ?? 0
            let name = uuid.flatMap { climbsByUUID[$0] }
            rows.append(Row(
                climbUUID: uuid ?? "",
                angle: angle,
                isMirror: a.isMirror,
                day: day,
                climbName: name,
                loggedDifficultyNum: loggedNum,
                displayedDifficultyNum: disp,
                loggedGrade: loggedGrade,
                displayedGrade: displayedGrade,
                isBenchmark: (benchFlag || (a.isBenchmark ?? false)),
                tries: tries + extra,
                isAscent: true,
                comment: a.comment
            ))
        }
        
        // 6) Add bids-only rows where no ascent exists that day
        let ascentKeySet: Set<BidKey> = Set(rows.map { BidKey(uuid: $0.climbUUID, day: $0.day, angle: $0.angle, isMirror: $0.isMirror) })
        for (key, sum) in bidSummary {
            if ascentKeySet.contains(key) { continue }
            let dispNum = statsDifficultyFor(uuid: key.uuid, angle: key.angle)
            let (_, benchFlag) = displayedDiffFor(uuid: key.uuid, angle: key.angle)
            rows.append(Row(
                climbUUID: key.uuid,
                angle: key.angle,
                isMirror: key.isMirror,
                day: key.day,
                climbName: climbsByUUID[key.uuid],
                loggedDifficultyNum: dispNum,
                displayedDifficultyNum: dispNum,
                loggedGrade: BoardGradeMapper.grade(of: dispNum),
                displayedGrade: nil,
                isBenchmark: benchFlag,
                tries: sum.tries,
                isAscent: false,
                comment: sum.comment
            ))
        }
        
        // 7) Upsert into SwiftData, mark previously climbed if any earlier entry exists with same tb2ClimbUUID
        let styleName = "Tension board"
        
        // Sort outside and pass into a MainActor-isolated function to avoid Swift 6 Sendable captures
        let sortedRows = rows.sorted(by: { $0.day < $1.day })
        
        //run migration to backfill precise climb times, once per board
        runOnce(per: "tb2_backfill_precise_times_v1_4\(board.rawValue)") {
            try? Self.backfillClimbTimesFromAPI(using: rows, into: context)
        }
        await progress?(SyncProgress(stage: .applyingRows))
        try Task.checkCancellation()
        try await applyRows(sortedRows, styleName: styleName, into: context)

        if climbCacheComplete {
            await progress?(SyncProgress(stage: .backfillingNames))
            try Task.checkCancellation()
            await runMissingNameBackfillOnce(board: board, into: context)
        }
        if statsCacheComplete {
            await progress?(SyncProgress(stage: .backfillingGrades))
            try Task.checkCancellation()
            await runMissingGradeBackfillOnce(board: board, into: context)
        }
        await progress?(SyncProgress(stage: .finished))
    }
    
    // MARK: - Shared maps
    
    private static func fetchSharedMaps(
        client: TB2Client,
        board: TB2Client.Board,
        token: String,
        into context: ModelContext,
        progress: (@MainActor (SyncProgress) -> Void)?
    ) async throws -> ([String: String], [DiffKey: Int], [DiffKey: DiffRec], [String: [Int]], Bool, Bool) {
        let cacheState = climbCacheState(for: board)
        let climbSyncDate = cacheState.isComplete
            ? (cacheState.lastSynchronizedAt ?? TB2Client.Constants.baseSyncDate)
            : TB2Client.Constants.baseSyncDate
        let statsCacheState = climbStatsCacheState(for: board)
        let statsSyncDate = statsCacheState.isComplete
            ? (statsCacheState.lastSynchronizedAt ?? TB2Client.Constants.baseSyncDate)
            : TB2Client.Constants.baseSyncDate

        await progress?(SyncProgress(stage: .cachingClimbs))
        try Task.checkCancellation()
        let resolvedClimbPages = try await client.syncPages(
            board: board,
            tablesAndSyncDates: ["climbs": climbSyncDate],
            token: token,
            maxPages: TB2Client.Constants.defaultMaxSyncPages
        ) { page, complete in
            progress?(SyncProgress(stage: .cachingClimbs, page: page, isComplete: complete))
        }
        try Task.checkCancellation()
        let cacheComplete = await upsertClimbMetadata(from: resolvedClimbPages, board: board, into: context)
        if cacheComplete {
            saveClimbCacheCursor(from: resolvedClimbPages, board: board)
        }
        let climbsByUUID = await cachedClimbNames(board: board, in: context)

        await progress?(SyncProgress(stage: .cachingClimbStats))
        try Task.checkCancellation()
        let resolvedStatsPages = try await client.syncPages(
            board: board,
            tablesAndSyncDates: ["climb_stats": statsSyncDate],
            token: token,
            maxPages: TB2Client.Constants.defaultMaxSyncPages
        ) { page, complete in
            progress?(SyncProgress(stage: .cachingClimbStats, page: page, isComplete: complete))
        }
        try Task.checkCancellation()
        let statsCacheComplete = await upsertClimbStatsMetadata(from: resolvedStatsPages, board: board, into: context)
        if statsCacheComplete {
            saveClimbStatsCacheCursor(from: resolvedStatsPages, board: board)
        }
        let statsByKey = await cachedClimbStatsDifficulties(board: board, in: context)

        await progress?(SyncProgress(stage: .loadingDifficulties))
        try Task.checkCancellation()
        let pages = try await client.syncPages(
            board: board,
            tablesAndSyncDates: ["difficulties": TB2Client.Constants.baseSyncDate],
            token: token,
            maxPages: TB2Client.Constants.defaultMaxSyncPages
        )
        try Task.checkCancellation()
        
        var diffByKey: [DiffKey: DiffRec] = [:]
        var fallback: [String: [Int]] = [:]
        
        for p in pages {
            for d in p.difficulties ?? [] {
                let uid = d.climbUUID ?? d.uuid
                guard let uid, let angle = d.angle else { continue }
                let rec = DiffRec(displayedDifficulty: d.difficulty, isBenchmark: (d.benchmarkDifficulty != nil) || (d.isBenchmark ?? false))
                diffByKey[DiffKey(uuid: uid, angle: angle)] = rec
                if let diff = d.difficulty { fallback[uid, default: []].append(diff) }
            }
        }
        return (climbsByUUID, statsByKey, diffByKey, fallback, cacheComplete, statsCacheComplete)
    }

    internal static func climbCacheState(for board: TB2Client.Board) -> ClimbCacheState {
        let defaults = UserDefaults.standard
        return ClimbCacheState(
            isComplete: defaults.bool(forKey: climbCacheCompleteKey(for: board)),
            lastSynchronizedAt: defaults.string(forKey: climbCacheCursorKey(for: board))
        )
    }

    internal static func saveClimbCacheCursor(from pages: [TB2Client.SyncResponse], board: TB2Client.Board) {
        guard pages.last?.complete == true else { return }
        let cursor = pages
            .flatMap { $0.sharedSyncs ?? [] }
            .last { $0.tableName == "climbs" }?
            .lastSynchronizedAt
        guard let cursor else { return }

        let defaults = UserDefaults.standard
        defaults.set(cursor, forKey: climbCacheCursorKey(for: board))
        defaults.set(true, forKey: climbCacheCompleteKey(for: board))
    }

    private static func climbCacheCursorKey(for board: TB2Client.Board) -> String {
        "tb2.climbsCache.\(board.rawValue).lastSynchronizedAt"
    }

    private static func climbCacheCompleteKey(for board: TB2Client.Board) -> String {
        "tb2.climbsCache.\(board.rawValue).complete"
    }

    internal static func climbStatsCacheState(for board: TB2Client.Board) -> ClimbStatsCacheState {
        let defaults = UserDefaults.standard
        return ClimbStatsCacheState(
            isComplete: defaults.bool(forKey: climbStatsCacheCompleteKey(for: board)),
            lastSynchronizedAt: defaults.string(forKey: climbStatsCacheCursorKey(for: board))
        )
    }

    internal static func saveClimbStatsCacheCursor(from pages: [TB2Client.SyncResponse], board: TB2Client.Board) {
        guard pages.last?.complete == true else { return }
        let cursor = pages
            .flatMap { $0.sharedSyncs ?? [] }
            .last { $0.tableName == "climb_stats" }?
            .lastSynchronizedAt
        guard let cursor else { return }

        let defaults = UserDefaults.standard
        defaults.set(cursor, forKey: climbStatsCacheCursorKey(for: board))
        defaults.set(true, forKey: climbStatsCacheCompleteKey(for: board))
    }

    private static func climbStatsCacheCursorKey(for board: TB2Client.Board) -> String {
        "tb2.climbStatsCache.\(board.rawValue).lastSynchronizedAt"
    }

    private static func climbStatsCacheCompleteKey(for board: TB2Client.Board) -> String {
        "tb2.climbStatsCache.\(board.rawValue).complete"
    }

    @MainActor
    @discardableResult
    internal static func upsertClimbMetadata(from pages: [TB2Client.SyncResponse], board: TB2Client.Board, into context: ModelContext) -> Bool {
        let climbs = pages.flatMap { $0.climbs ?? [] }
        guard !climbs.isEmpty else { return pages.last?.complete == true }

        let boardRawValue = board.rawValue
        let existing = (try? context.fetch(FetchDescriptor<TB2ClimbMetadata>(
            predicate: #Predicate { $0.boardRawValue == boardRawValue }
        ))) ?? []
        var byUUID: [String: TB2ClimbMetadata] = [:]
        for row in existing where byUUID[row.uuid] == nil {
            byUUID[row.uuid] = row
        }
        var changed = 0

        for climb in climbs {
            guard let uuid = climb.uuid else { continue }
            let name = climb.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }

            if let cached = byUUID[uuid] {
                if cached.name != name { cached.name = name; changed += 1 }
                if cached.updatedAt != climb.updatedAt { cached.updatedAt = climb.updatedAt; changed += 1 }
                if cached.layoutID != climb.layoutID { cached.layoutID = climb.layoutID; changed += 1 }
                if cached.isListed != climb.isListed { cached.isListed = climb.isListed; changed += 1 }
            } else {
                let metadata = TB2ClimbMetadata(
                    boardRawValue: boardRawValue,
                    uuid: uuid,
                    name: name,
                    updatedAt: climb.updatedAt,
                    layoutID: climb.layoutID,
                    isListed: climb.isListed
                )
                context.insert(metadata)
                byUUID[uuid] = metadata
                changed += 1
            }
        }

        if changed > 0 {
            try? context.save()
        }
        return pages.last?.complete == true
    }

    @MainActor
    internal static func cachedClimbNames(board: TB2Client.Board, in context: ModelContext) -> [String: String] {
        let boardRawValue = board.rawValue
        let rows = (try? context.fetch(FetchDescriptor<TB2ClimbMetadata>(
            predicate: #Predicate { $0.boardRawValue == boardRawValue }
        ))) ?? []
        var namesByUUID: [String: String] = [:]
        for row in rows where namesByUUID[row.uuid] == nil {
            namesByUUID[row.uuid] = row.name
        }
        return namesByUUID
    }

    @MainActor
    @discardableResult
    internal static func upsertClimbStatsMetadata(from pages: [TB2Client.SyncResponse], board: TB2Client.Board, into context: ModelContext) -> Bool {
        let statsRows = pages.flatMap { $0.climbStats ?? [] }
        guard !statsRows.isEmpty else { return pages.last?.complete == true }

        let boardRawValue = board.rawValue
        let existing = (try? context.fetch(FetchDescriptor<TB2ClimbStatsMetadata>(
            predicate: #Predicate { $0.boardRawValue == boardRawValue }
        ))) ?? []
        var byKey: [DiffKey: TB2ClimbStatsMetadata] = [:]
        for row in existing where byKey[DiffKey(uuid: row.climbUUID, angle: row.angle)] == nil {
            byKey[DiffKey(uuid: row.climbUUID, angle: row.angle)] = row
        }
        var changed = 0

        for stats in statsRows {
            guard let uuid = stats.climbUUID, let angle = stats.angle else { continue }
            let key = DiffKey(uuid: uuid, angle: angle)

            if let cached = byKey[key] {
                if cached.difficultyAverage != stats.difficultyAverage { cached.difficultyAverage = stats.difficultyAverage; changed += 1 }
                if cached.displayDifficulty != stats.displayDifficulty { cached.displayDifficulty = stats.displayDifficulty; changed += 1 }
                if cached.ascensionistCount != stats.ascensionistCount { cached.ascensionistCount = stats.ascensionistCount; changed += 1 }
                if cached.qualityAverage != stats.qualityAverage { cached.qualityAverage = stats.qualityAverage; changed += 1 }
            } else {
                let metadata = TB2ClimbStatsMetadata(
                    boardRawValue: boardRawValue,
                    climbUUID: uuid,
                    angle: angle,
                    difficultyAverage: stats.difficultyAverage,
                    displayDifficulty: stats.displayDifficulty,
                    ascensionistCount: stats.ascensionistCount,
                    qualityAverage: stats.qualityAverage
                )
                context.insert(metadata)
                byKey[key] = metadata
                changed += 1
            }
        }

        if changed > 0 {
            try? context.save()
        }
        return pages.last?.complete == true
    }

    @MainActor
    internal static func cachedClimbStatsDifficulties(board: TB2Client.Board, in context: ModelContext) -> [DiffKey: Int] {
        let boardRawValue = board.rawValue
        let rows = (try? context.fetch(FetchDescriptor<TB2ClimbStatsMetadata>(
            predicate: #Predicate { $0.boardRawValue == boardRawValue }
        ))) ?? []
        var difficultiesByKey: [DiffKey: Int] = [:]
        for row in rows where difficultiesByKey[DiffKey(uuid: row.climbUUID, angle: row.angle)] == nil {
            guard let grade = statsDifficultyNumber(average: row.difficultyAverage, display: row.displayDifficulty) else { continue }
            difficultiesByKey[DiffKey(uuid: row.climbUUID, angle: row.angle)] = grade
        }
        return difficultiesByKey
    }

    internal static func statsDifficultyNumber(average: Double?, display: Double?) -> Int? {
        let source = average ?? display
        guard let source else { return nil }
        return Int(source.rounded())
    }
    
    
    // MARK: - Apply to SwiftData (MainActor)
    
    @MainActor
    internal static func applyRows(_ rows: [Row], styleName: String, into context: ModelContext) throws {
        for r in rows {
            let id = stableID(climbUUID: r.climbUUID, day: r.day, angle: r.angle, isMirror: r.isMirror, isAscent: r.isAscent)
            
            // Skip if already present by id
            if let _ = (try? context.fetch(FetchDescriptor<ClimbEntry>(
                predicate: #Predicate<ClimbEntry> { entry in entry.id == id }
            )))?.first {
                continue
            }
            
            // Secondary guard: if an entry exists with the same TB2 identity on that day AND same style (board), skip
            let uuidOpt: String? = r.climbUUID
            let dayConst: Date = r.day
            let isWIPFlag = !r.isAscent
            let angleConst: Int? = r.angle
            let styleConst: String = styleName
            if let _ = (try? context.fetch(FetchDescriptor<ClimbEntry>(
                predicate: #Predicate<ClimbEntry> { entry in
                    entry.tb2ClimbUUID == uuidOpt &&
                    entry.dateLogged == dayConst &&
                    entry.angleDegrees == angleConst &&
                    entry.isWorkInProgress == isWIPFlag &&
                    entry.style == styleConst
                }
            )))?.first {
                continue
            }
            
            let previously = wasPreviouslyClimbed(
                in: context,
                tb2ClimbUUID: r.climbUUID,
                angleDegrees: r.angle,
                before: r.day
            )

            let grade = r.loggedGrade ?? ""
            let entry = ClimbEntry(
                id: id,
                climbType: .boulder,
                grade: grade,
                angleDegrees: r.angle,
                style: styleName,
                attempts: String(r.tries),
                isWorkInProgress: !r.isAscent,
                isPreviouslyClimbed: previously ? true : false,
                holdColor: nil,
                gym: String(r.climbName ?? ""),
                notes: r.climbName,
                dateLogged: r.day,
                tb2ClimbUUID: r.climbUUID
            )
            context.insert(entry)
        }
        try? context.save()
    }

    @MainActor
    private static func runMissingNameBackfillOnce(board: TB2Client.Board, into context: ModelContext) {
        runOnce(per: "tb2_backfill_missing_names_v1_2026_07_25_\(board.rawValue)") {
            try? Self.backfillMissingNames(board: board, into: context)
        }
    }

    @MainActor
    internal static func backfillMissingNames(board: TB2Client.Board, into context: ModelContext) throws {
        let boardRawValue = board.rawValue
        let metadataRows = (try? context.fetch(FetchDescriptor<TB2ClimbMetadata>(
            predicate: #Predicate { $0.boardRawValue == boardRawValue }
        ))) ?? []
        var namesByUUID: [String: String] = [:]
        for row in metadataRows where namesByUUID[row.uuid] == nil {
            namesByUUID[row.uuid] = row.name
        }
        guard !namesByUUID.isEmpty else { return }

        let entries = (try? context.fetch(FetchDescriptor<ClimbEntry>(
            predicate: #Predicate { $0.tb2ClimbUUID != nil }
        ))) ?? []
        var changed = 0

        for entry in entries {
            guard let uuid = entry.tb2ClimbUUID, let name = namesByUUID[uuid] else { continue }
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }

            let gymIsMissing = entry.gym.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let notesIsMissing = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true

            if gymIsMissing {
                entry.gym = trimmedName
                changed += 1
            }
            if notesIsMissing {
                entry.notes = trimmedName
                changed += 1
            }
        }

        if changed > 0 {
            try context.save()
        }
        print("Backfilled missing TB2 climb names for \(changed) fields.")
    }

    @MainActor
    private static func runMissingGradeBackfillOnce(board: TB2Client.Board, into context: ModelContext) {
        runOnce(per: "tb2_backfill_missing_grades_from_climb_stats_v1_2026_07_25_\(board.rawValue)") {
            try? Self.backfillMissingGradesFromClimbStats(board: board, into: context)
        }
    }

    @MainActor
    internal static func backfillMissingGradesFromClimbStats(board: TB2Client.Board, into context: ModelContext) throws {
        let statsByKey = cachedClimbStatsDifficulties(board: board, in: context)
        guard !statsByKey.isEmpty else { return }

        let entries = (try? context.fetch(FetchDescriptor<ClimbEntry>(
            predicate: #Predicate { $0.tb2ClimbUUID != nil }
        ))) ?? []
        var changed = 0

        for entry in entries {
            guard entry.style == "Tension board" else { continue }
            guard entry.grade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard let uuid = entry.tb2ClimbUUID, let angle = entry.angleDegrees else { continue }
            guard let difficulty = statsByKey[DiffKey(uuid: uuid, angle: angle)] else { continue }
            guard let grade = BoardGradeMapper.grade(of: difficulty) else { continue }

            entry.grade = grade
            changed += 1
        }

        if changed > 0 {
            try context.save()
        }
        print("Backfilled missing TB2 climb grades for \(changed) rows.")
    }
    
    // MARK: - Previously climbed helper (testable)

    @MainActor
    internal static func wasPreviouslyClimbed(
        in context: ModelContext,
        tb2ClimbUUID: String,
        angleDegrees: Int?,
        before day: Date
    ) -> Bool {
        let uuidOpt: String? = tb2ClimbUUID
        let angleConst: Int? = angleDegrees
        let dayConst: Date = day

        do {
            // Only count prior *completed* entries on the same angle.
            let priorCompleted = try context.fetch(
                FetchDescriptor<ClimbEntry>(
                    predicate: #Predicate { entry in
                        entry.tb2ClimbUUID == uuidOpt &&
                        entry.angleDegrees == angleConst &&
                        entry.dateLogged < dayConst &&
                        entry.isWorkInProgress == false
                    },
                    sortBy: [SortDescriptor(\ClimbEntry.dateLogged)]
                )
            )
            return !priorCompleted.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Stable ID
    private static func stableID(climbUUID: String, day: Date, angle: Int?, isMirror: Bool?, isAscent: Bool) -> UUID {
        let dayEpoch = Int((day.timeIntervalSince1970 / 86400.0).rounded(.down))
        let key = "tb2|\(climbUUID)|\(dayEpoch)|\(angle ?? -999)|\((isMirror ?? false) ? 1 : 0)|\((isAscent) ? 1 : 0)"
        return BoardSyncIdentity.deterministicUUID(from: key)
    }
    
    private static func dayKeyLocal(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current   // ← match how startOfDay behaved before
        let localStart = cal.startOfDay(for: date)
        let comps = cal.dateComponents([.year, .month, .day], from: localStart)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }


    //one time migration to fix missing timestamps from boards api
    private static func backfillClimbTimesFromAPI(using rows: [Row], into context: ModelContext) throws {
        // Build an index from API rows: (uuid, angle, dayKeyUTC) -> precise Date
        struct Key: Hashable { let uuid: String; let angle: Int?; let dayKey: String }

        // Use only rows that have a UUID (TB2)
        let apiRows = rows.filter { !$0.climbUUID.isEmpty }
        guard !apiRows.isEmpty else { return }

        var apiIndex: [Key: Date] = [:]

        for r in apiRows {
            let k = Key(uuid: r.climbUUID, angle: r.angle, dayKey: dayKeyLocal(r.day))
            if let cur = apiIndex[k] {
                // Prefer ascents; otherwise keep the earliest time as tiebreaker
                if r.isAscent {
                    apiIndex[k] = r.day
                } else if cur > r.day {
                    apiIndex[k] = r.day
                }
            } else {
                apiIndex[k] = r.day
            }
        }
        // Fetch existing climbs
        let fetch = FetchDescriptor<ClimbEntry>(predicate: #Predicate { $0.tb2ClimbUUID != nil })
        let existing = (try? context.fetch(fetch)) ?? []

        let localCal = Calendar(identifier: .gregorian)
        let localTZ  = TimeZone.current
        var changed = 0

        for e in existing {
            guard let uuid = e.tb2ClimbUUID else { continue }
            let k = Key(uuid: uuid, angle: e.angleDegrees, dayKey: dayKeyLocal(e.dateLogged))
            guard let apiDate = apiIndex[k] else { continue }

            // If time is missing (00:00:00 local) OR differs from API timestamp, update it
            let comps = localCal.dateComponents(in: localTZ, from: e.dateLogged)
            let looksTruncated = (comps.hour == 0 && comps.minute == 0 && comps.second == 0)

            if looksTruncated || e.dateLogged != apiDate {
                print("date before: \(e.dateLogged)  datetime after: \(apiDate)")
                e.dateLogged = apiDate
                changed += 1
            }
        }

        if changed > 0 { try context.save() }
        
        // --- Deduplicate exact-second duplicates (same uuid + timestamp) ---
        let fetch2 = FetchDescriptor<ClimbEntry>(predicate: #Predicate { $0.tb2ClimbUUID != nil })
        let allTB2 = (try? context.fetch(fetch2)) ?? []

        struct DedupeKey: Hashable { let uuid: String; let angle: Int?; let tsSec: Int }
        var buckets: [DedupeKey: [ClimbEntry]] = [:]

        for e in allTB2 {
            guard let uuid = e.tb2ClimbUUID else { continue }
            let tsSec = Int(e.dateLogged.timeIntervalSince1970) // second precision
            let key = DedupeKey(uuid: uuid, angle: e.angleDegrees, tsSec: tsSec)
            buckets[key, default: []].append(e)
        }

        var deleted = 0
        for (_, group) in buckets where group.count > 1 {
            // Keep one deterministically (smallest UUID), delete the rest
            let sorted = group.sorted { $0.id.uuidString < $1.id.uuidString }
            for dup in sorted.dropFirst() {
                print("Deleting duplicate ClimbEntry \(dup.id.uuidString) at \(dup.dateLogged)")
                context.delete(dup)
                deleted += 1
            }
        }

        if deleted > 0 { try context.save() }

    }

}
