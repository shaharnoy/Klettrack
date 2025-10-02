//
//  TB2SyncManager.swift
//  Klettrack
//  Created by Shahar Noy on 29.09.25.
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
        let styleName: String = {
            switch board {
            case .tension: return "Tension board"
            case .kilter:  return "Kilter board"
            }
        }()
        
        // Sort outside and pass into a MainActor-isolated function to avoid Swift 6 Sendable captures
        let sortedRows = rows.sorted(by: { $0.day < $1.day })
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
            
            // Look for any earlier entry with same TB2 climb UUID (regardless of board)
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

// MARK: - Local helpers (duplicated here so this target builds)

private struct TB2GradeMapper {
    static let mappingCSV = """
    difficulty,grade_label
    1,1a/V0
    2,1b/V0
    3,1c/V0
    4,2a/V0
    5,2b/V0
    6,2c/V0
    7,3a/V0
    8,3b/V0
    9,3c/V0
    10,4a/V0
    11,4b/V0
    12,4c/V0
    13,5a/V1
    14,5b/V1
    15,5c/V2
    16,6a/V3
    17,6a+/V3
    18,6b/V4
    19,6b+/V4
    20,6c/V5
    21,6c+/V5
    22,7a/V6
    23,7a+/V7
    24,7b/V8
    25,7b+/V8
    26,7c/V9
    27,7c+/V10
    28,8a/V11
    29,8a+/V12
    30,8b/V13
    31,8b+/V14
    32,8c/V15
    33,8c+/V16
    34,9a/V17
    35,9a+/V18
    36,9b/V19
    37,9b+/V20
    38,9c/V21
    39,9c+/V22
    """
    
    static let diffToGrade: [Int: String] = {
        var out: [Int: String] = [:]
        for line in mappingCSV.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty || t.hasPrefix("#") || t.lowercased().hasPrefix("difficulty") { continue }
            let parts = t.split(separator: ",", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2, let n = Int(parts[0]) else { continue }
            let left = leftPart(of: parts[1])
            out[n] = left
        }
        return out
    }()
    
    static func leftPart(of label: String) -> String {
        let first = label.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first ?? Substring("")
        let leftDot = first.split(separator: "·", maxSplits: 1, omittingEmptySubsequences: false).first ?? Substring("")
        return String(leftDot).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static func grade(of number: Any?) -> String? {
        guard let n = number else { return nil }
        let value: Double?
        if let i = n as? Int { value = Double(i) }
        else if let d = n as? Double { value = d }
        else if let s = n as? String { value = Double(s) }
        else { value = nil }
        guard let v = value else { return nil }
        let key = Int((v).rounded())
        return diffToGrade[key]
    }
}

private enum TB2DateParser {
    // ISO8601 variants
    static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
    // Common custom patterns (UTC)
    private static func makeFormatter(_ fmt: String, tzUTC: Bool = true) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tzUTC ? TimeZone(secondsFromGMT: 0) : TimeZone.current
        f.dateFormat = fmt
        return f
    }
    static let f1 = makeFormatter("yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX") // 2025-01-21 13:01:14.123456+00:00
    static let f2 = makeFormatter("yyyy-MM-dd HH:mm:ss.SSSSSSxxxx")  // 2025-01-21 13:01:14.123456+0000
    static let f3 = makeFormatter("yyyy-MM-dd HH:mm:ss.SSSSSS")      // 2025-01-21 13:01:14.123456
    static let f4 = makeFormatter("yyyy-MM-dd HH:mm:ssXXXXX")        // 2025-01-21 13:01:14+00:00
    static let f5 = makeFormatter("yyyy-MM-dd HH:mm:ssxxxx")         // 2025-01-21 13:01:14+0000
    static let f6 = makeFormatter("yyyy-MM-dd HH:mm:ss")             // 2025-01-21 13:01:14
    static let f7 = makeFormatter("yyyy-MM-dd")                      // 2025-01-21
    static let f8 = makeFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX")
    static let f9 = makeFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX")
    static let f10 = makeFormatter("yyyy-MM-dd'T'HH:mm:ssXXXXX")
    
    static func parse(_ s: String?) -> Date? {
        guard var s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        
        // Numeric epoch seconds or milliseconds
        if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: s)) {
            if let v = Double(s) {
                if s.count >= 13 { return Date(timeIntervalSince1970: v / 1000.0) }
                if s.count >= 10 { return Date(timeIntervalSince1970: v) }
            }
        }
        
        // Try ISO8601
        if let d = isoFull.date(from: s) { return d }
        if let d = isoBasic.date(from: s) { return d }
        
        for f in [f1,f2,f3,f4,f5,f6,f7,f8,f9,f10] {
            if let d = f.date(from: s) { return d }
        }
        
        if s.hasSuffix(" UTC") {
            s.removeLast(4)
            for f in [f3, f6, f7] {
                if let d = f.date(from: s) { return d }
            }
        }
        return nil
    }
}

