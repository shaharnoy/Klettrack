//
//  TB2SyncManager.swift
//  Klettrack
//  Created by Shahar Noy on 29.09.25.
//

import Foundation
import SwiftData

enum TB2SyncManager {
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
    
    static func sync(using creds: TB2Credentials, board: TB2Client.Board, into context: ModelContext) async throws {
        let client = TB2Client()
        
        // Login -> token
        let token = try await client.login(board: board, username: creds.username, password: creds.password)
        
        //Fetch shared maps: climbs + difficulties
        let (climbsByUUID, diffByKey, fallbackDiffs) = try await fetchSharedMaps(client: client, board: board, token: token)
        
        //Pull ascents and bids
        async let ascPages = client.syncPages(board: board, tablesAndSyncDates: ["ascents": TB2Client.Constants.baseSyncDate], token: token, maxPages: TB2Client.Constants.defaultMaxSyncPages)
        async let bidPages = client.syncPages(board: board, tablesAndSyncDates: ["bids": TB2Client.Constants.baseSyncDate], token: token, maxPages: TB2Client.Constants.defaultMaxSyncPages)
        let ascents = (try await ascPages).flatMap { $0.ascents ?? [] }
        let bids    = (try await bidPages).flatMap { $0.bids ?? [] }
        
        // 4) Summarize bids (tries per day/climb/angle/mirror)
        struct BidKey: Hashable { let uuid: String; let day: Date; let angle: Int?; let isMirror: Bool? }
        struct BidSum { var tries: Int; var comment: String? }
        //let cal = Calendar.current
        var bidSummary: [BidKey: BidSum] = [:]
        
        for b in bids {
            guard let uuid = b.climbUUID else { continue }
            guard let date = BoardDateParser.parse(b.climbedAt) else { continue } // strict: no fallback to now
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
        
        var rows: [Row] = []
        for a in ascents {
            if let listed = a.isListed, listed == false { continue }
            let uuid = a.climbUUID
            let angle = a.angle
            let (dispNum, benchFlag) = displayedDiffFor(uuid: uuid, angle: angle)
            let loggedNum = a.difficulty
            let disp = dispNum ?? loggedNum
            let loggedGrade = BoardGradeMapper.grade(of: loggedNum)
            let displayedGrade = BoardGradeMapper.grade(of: disp)
            guard let date = BoardDateParser.parse(a.climbedAt) else { continue }
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
            let (dispNum, benchFlag) = displayedDiffFor(uuid: key.uuid, angle: key.angle)
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
        try await applyRows(sortedRows, styleName: styleName, into: context)
    }
    
    // MARK: - Shared maps
    
    private static func fetchSharedMaps(client: TB2Client, board: TB2Client.Board, token: String) async throws -> ([String: String], [DiffKey: DiffRec], [String: [Int]]) {
        let pages = try await client.syncPages(board: board, tablesAndSyncDates: [
            "climbs": TB2Client.Constants.baseSyncDate,
            "difficulties": TB2Client.Constants.baseSyncDate
        ], token: token, maxPages: 10)
        
        var climbsByUUID: [String: String] = [:]
        var diffByKey: [DiffKey: DiffRec] = [:]
        var fallback: [String: [Int]] = [:]
        
        for p in pages {
            for c in p.climbs ?? [] {
                if let uid = c.uuid, let nm = c.name { climbsByUUID[uid] = nm }
            }
            for d in p.difficulties ?? [] {
                let uid = d.climbUUID ?? d.uuid
                guard let uid, let angle = d.angle else { continue }
                let rec = DiffRec(displayedDifficulty: d.difficulty, isBenchmark: (d.benchmarkDifficulty != nil) || (d.isBenchmark ?? false))
                diffByKey[DiffKey(uuid: uid, angle: angle)] = rec
                if let diff = d.difficulty { fallback[uid, default: []].append(diff) }
            }
        }
        return (climbsByUUID, diffByKey, fallback)
    }
    
    
    // MARK: - Apply to SwiftData (MainActor)
    
    @MainActor
    private static func applyRows(_ rows: [Row], styleName: String, into context: ModelContext) throws {
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
