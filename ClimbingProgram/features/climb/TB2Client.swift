//
//  TB2Client.swift
//  ClimbingProgram
//

import Foundation

struct TB2Client {
    enum Board: String {
        case tension
        case kilter
        var hostBase: String {
            switch self {
            case .tension: return "tensionboardapp2"
            case .kilter:  return "kilterboardapp"
            }
        }
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

