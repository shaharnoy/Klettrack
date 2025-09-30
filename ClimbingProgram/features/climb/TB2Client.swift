//
//  TB2Client.swift
//  ClimbingProgram
//

import Foundation

struct TB2Client {
    enum Board: String {
        case tension
        var hostBase: String { "tensionboardapp2" }
        var webBaseURL: URL { URL(string: "https://\(hostBase).com")! }
    }
    
    struct Constants {
        static let baseSyncDate = "1970-01-01 00:00:00.000000"
        static let defaultMaxSyncPages = 100
        static let userAgent = "Kilter%20Board/202 CFNetwork/1568.100.1 Darwin/24.0.0"
    }
    
    struct SyncResponse: Decodable {
        let complete: Bool?
        let ascents: [Ascent]?
        let bids: [Bid]?
        let climbs: [Climb]?
        let difficulties: [Difficulty]?
        let userSyncs: [TableSync]?
        let sharedSyncs: [TableSync]?
        
        enum CodingKeys: String, CodingKey {
            case complete = "_complete"
            case ascents, bids, climbs, difficulties
            case userSyncs = "user_syncs"
            case sharedSyncs = "shared_syncs"
        }
    }
    
    struct TableSync: Decodable {
        let tableName: String
        let lastSynchronizedAt: String?
        enum CodingKeys: String, CodingKey {
            case tableName = "table_name"
            case lastSynchronizedAt = "last_synchronized_at"
        }
    }
    
    struct Ascent: Decodable {
        let isListed: Bool?
        let climbUUID: String?
        let angle: Int?
        let difficulty: Int?
        let isBenchmark: Bool?
        let bidCount: Int?
        let attemptID: Int?
        let isMirror: Bool?
        let comment: String?
        let climbedAt: String?
        
        enum CodingKeys: String, CodingKey {
            case isListed = "is_listed"
            case climbUUID = "climb_uuid"
            case angle
            case difficulty
            case isBenchmark = "is_benchmark"
            case bidCount = "bid_count"
            case attemptID = "attempt_id"
            case isMirror = "is_mirror"
            case comment
            case climbedAt = "climbed_at"
        }
    }
    
    struct Bid: Decodable {
        let climbUUID: String?
        let angle: Int?
        let isMirror: Bool?
        let bidCount: Int?
        let comment: String?
        let climbedAt: String?
        
        enum CodingKeys: String, CodingKey {
            case climbUUID = "climb_uuid"
            case angle
            case isMirror = "is_mirror"
            case bidCount = "bid_count"
            case comment
            case climbedAt = "climbed_at"
        }
    }
    
    struct Climb: Decodable {
        let uuid: String?
        let name: String?
    }
    
    struct Difficulty: Decodable {
        let climbUUID: String?
        let uuid: String?
        let angle: Int?
        let difficulty: Int?
        let benchmarkDifficulty: Int?
        let isBenchmark: Bool?
        
        enum CodingKeys: String, CodingKey {
            case climbUUID = "climb_uuid"
            case uuid
            case angle
            case difficulty
            case benchmarkDifficulty = "benchmark_difficulty"
            case isBenchmark = "is_benchmark"
        }
    }
    
    // MARK: - Login
    
    func login(board: Board, username: String, password: String) async throws -> String {
        var req = URLRequest(url: board.webBaseURL.appendingPathComponent("sessions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(Constants.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("keep-alive", forHTTPHeaderField: "Connection")
        req.setValue("en-AU,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        
        let body: [String: Any] = [
            "username": username,
            "password": password,
            "tou": "accepted",
            "pp": "accepted",
            "ua": "app"
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 422 {
            throw NSError(domain: "TB2", code: 422, userInfo: [NSLocalizedDescriptionKey: "Invalid username or password."])
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "TB2", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Login failed (\(http.statusCode))."])
        }
        
        // session can be string or object containing token/id/value
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        let sess = json?["session"]
        if let token = sess as? String {
            return token
        } else if let obj = sess as? [String: Any] {
            if let token = obj["token"] as? String ?? obj["id"] as? String ?? obj["value"] as? String {
                return token
            }
        }
        throw NSError(domain: "TB2", code: -1, userInfo: [NSLocalizedDescriptionKey: "Login OK but no session token found."])
    }
    
    // MARK: - Sync
    
    private func postSync(url: URL, body: String, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k,v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 404 {
            let alt = URL(string: url.absoluteString.replacingOccurrences(of: "/sync", with: "/api/v1/sync"))!
            var altReq = URLRequest(url: alt)
            altReq.httpMethod = "POST"
            for (k,v) in headers { altReq.setValue(v, forHTTPHeaderField: k) }
            altReq.httpBody = body.data(using: .utf8)
            let (d2, r2) = try await URLSession.shared.data(for: altReq)
            guard let http2 = r2 as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return (d2, http2)
        }
        return (data, http)
    }
    
    func syncPages(board: Board, tablesAndSyncDates: [String: String], token: String?, maxPages: Int = Constants.defaultMaxSyncPages) async throws -> [SyncResponse] {
        var headers: [String: String] = [
            "Accept": "application/json",
            "User-Agent": Constants.userAgent,
            "Content-Type": "application/x-www-form-urlencoded",
        ]
        if let token = token { headers["Cookie"] = "token=\(token)" }
        
        var payload = tablesAndSyncDates
        var pages: [SyncResponse] = []
        var complete = false
        var pageCount = 0
        let base = board.webBaseURL.appendingPathComponent("sync")
        
        while !complete && pageCount < maxPages {
            let body = urlFormBody(payload)
            let (data, http) = try await postSync(url: base, body: body, headers: headers)
            if http.statusCode == 401 {
                throw NSError(domain: "TB2", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized (401). Token invalid/expired."])
            }
            guard (200..<300).contains(http.statusCode) else {
                throw NSError(domain: "TB2", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Sync failed (\(http.statusCode))."])
            }
            
            let page = try JSONDecoder().decode(SyncResponse.self, from: data)
            complete = page.complete ?? false
            pages.append(page)
            
            // advance per table if timestamps are provided
            if token != nil {
                for us in page.userSyncs ?? [] {
                    if let last = us.lastSynchronizedAt, payload.keys.contains(us.tableName) {
                        payload[us.tableName] = last
                    }
                }
            }
            for ss in page.sharedSyncs ?? [] {
                if let last = ss.lastSynchronizedAt, payload.keys.contains(ss.tableName) {
                    payload[ss.tableName] = last
                }
            }
            pageCount += 1
        }
        return pages
    }
    
    // MARK: - Helpers
    
    private func urlFormBody(_ dict: [String: String]) -> String {
        dict.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
    }
}

// MARK: - Grade mapper (left part of CSV label)

struct TB2GradeMapper {
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

// MARK: - Date parsing

enum TB2DateParser {
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
        
        // Some services emit "Z" without colon in offset; DateFormatter with XXXXX expects colon
        // Already handled by isoBasic/isoFull above, but keep fallbacks:
        for f in [f1,f2,f3,f4,f5,f6,f7,f8,f9,f10] {
            if let d = f.date(from: s) { return d }
        }
        
        // Some APIs use " UTC" suffix; strip and retry
        if s.hasSuffix(" UTC") {
            s.removeLast(4)
            for f in [f3, f6, f7] {
                if let d = f.date(from: s) { return d }
            }
        }
        return nil
    }
}
