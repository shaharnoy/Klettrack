//
//  TB2SyncManager.swift
//  ClimbingProgram
//

import Foundation
import SwiftData
import CryptoKit

enum TB2SyncManager {
    struct DiffKey: Hashable {
        let uuid: String
        let angle: Int
    }
    struct DiffRec {
        let displayedDifficulty: Int?
        let isBenchmark: Bool
    }
    
    static func sync(using creds: TB2Credentials, into context: ModelContext) async throws {
        let client = TB2Client()
        let board: TB2Client.Board = .tension
        
        // 1) Login -> token
        let token = try await client.login(board: board, username: creds.username, password: creds.password)
        
        // 2) Fetch shared maps: climbs + difficulties
        let (climbsByUUID, diffByKey, fallbackDiffs) = try await fetchSharedMaps(client: client, board: board, token: token)
        
        // 3) Pull ascents and bids
        async let ascPages = client.syncPages(board: board, tablesAndSyncDates: ["ascents": TB2Client.Constants.baseSyncDate], token: token, maxPages: TB2Client.Constants.defaultMaxSyncPages)
        async let bidPages = client.syncPages(board: board, tablesAndSyncDates: ["bids": TB2Client.Constants.baseSyncDate], token: token, maxPages: TB2Client.Constants.defaultMaxSyncPages)
        let ascents = (try await ascPages).flatMap { $0.ascents ?? [] }
        let bids    = (try await bidPages).flatMap { $0.bids ?? [] }
        
        // 4) Summarize bids (tries per day/climb/angle/mirror)
        struct BidKey: Hashable { let uuid: String; let day: Date; let angle: Int?; let isMirror: Bool? }
        struct BidSum { var tries: Int; var comment: String? }
        let cal = Calendar.current
        var bidSummary: [BidKey: BidSum] = [:]
        
        for b in bids {
            guard let uuid = b.climbUUID else { continue }
            guard let date = TB2DateParser.parse(b.climbedAt) else { continue } // strict: no fallback to now
            let day = cal.startOfDay(for: date)
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
            let loggedGrade = TB2GradeMapper.grade(of: loggedNum)
            let displayedGrade = TB2GradeMapper.grade(of: disp)
            guard let date = TB2DateParser.parse(a.climbedAt) else { continue }
            let day = cal.startOfDay(for: date)
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
                loggedGrade: TB2GradeMapper.grade(of: dispNum),
                displayedGrade: nil,
                isBenchmark: benchFlag,
                tries: sum.tries,
                isAscent: false,
                comment: sum.comment
            ))
        }
        
        // 7) Upsert into SwiftData, mark previously climbed if any earlier entry exists with same tb2ClimbUUID
        let styleName = "Tension board"
        //let gymEmpty = "" // leave empty as requested
        
        try await MainActor.run {
            // Process in chronological order
            for r in rows.sorted(by: { $0.day < $1.day }) {
                let id = stableID(climbUUID: r.climbUUID, day: r.day, angle: r.angle, isMirror: r.isMirror, isAscent: r.isAscent)
                
                // Skip if already present by id
                if let _ = (try? context.fetch(FetchDescriptor<ClimbEntry>(
                    predicate: #Predicate<ClimbEntry> { entry in entry.id == id }
                )))?.first {
                    continue
                }
                
                // Secondary guard: if an entry exists with the same TB2 identity on that day, skip (handles legacy CSV without id)
                let uuidOpt: String? = r.climbUUID
                let dayConst: Date = r.day
                let isWIPFlag = !r.isAscent
                let angleConst: Int? = r.angle
                if let _ = (try? context.fetch(FetchDescriptor<ClimbEntry>(
                    predicate: #Predicate<ClimbEntry> { entry in
                        entry.tb2ClimbUUID == uuidOpt &&
                        entry.dateLogged == dayConst &&
                        entry.angleDegrees == angleConst &&
                        entry.isWorkInProgress == isWIPFlag
                    }
                )))?.first {
                    continue
                }
                
                // Look for any earlier entry with same TB2 climb UUID
                var previously = false
                do {
                    let prior = try context.fetch(
                        FetchDescriptor<ClimbEntry>(
                            predicate: #Predicate { entry in
                                entry.tb2ClimbUUID == uuidOpt && entry.dateLogged < dayConst
                            },
                            sortBy: [SortDescriptor(\ClimbEntry.dateLogged)]
                        )
                    )
                    previously = !prior.isEmpty
                } catch {
                    previously = false
                }
                
                let grade = r.loggedGrade ?? ""
                let entry = ClimbEntry(
                    id: id,
                    climbType: .boulder,
                    grade: grade,
                    angleDegrees: r.angle,
                    style: styleName,
                    attempts: String(r.tries),
                    isWorkInProgress: !r.isAscent,
                    isPreviouslyClimbed: previously ? true : nil,
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
    
    // MARK: - Stable ID
    
    private static func stableID(climbUUID: String, day: Date, angle: Int?, isMirror: Bool?, isAscent: Bool) -> UUID {
        let dayEpoch = Int((day.timeIntervalSince1970 / 86400.0).rounded(.down))
        let key = "tb2|\(climbUUID)|\(dayEpoch)|\(angle ?? -999)|\((isMirror ?? false) ? 1 : 0)|\((isAscent) ? 1 : 0)"
        return deterministicUUID(from: key)
    }
    
    private static func deterministicUUID(from string: String) -> UUID {
        let hash = SHA256.hash(data: Data(string.utf8))
        let bytes = Array(hash.prefix(16))
        let uuid = uuid_t(bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15])
        return UUID(uuid: uuid)
    }
}
