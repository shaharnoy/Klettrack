//
//  KilterSyncTests.swift
//  klettrack Tests
//

import Foundation
import SwiftData
import XCTest

@testable import klettrack

final class KilterSyncTests: ClimbingProgramTestSuite {
    func testKilterClientBuildsLoginAndLogsRequests() async throws {
        let recorder = KilterRequestRecorder(responses: [
            (
                Data("""
                {
                  "access_token": "token-123",
                  "expires_in": 14400,
                  "refresh_token": "refresh-123",
                  "token_type": "Bearer"
                }
                """.utf8),
                200
            ),
            (
                Data("""
                [
                  {
                    "logUuid": "log-1",
                    "climbUuid": "climb-1",
                    "angle": 40,
                    "flashed": false,
                    "topped": true,
                    "attempts": 3,
                    "createdAt": "2026-06-02T18:53:20.416361Z",
                    "climbName": "Corporate Shrubbery",
                    "currentDifficultyId": 19
                  }
                ]
                """.utf8),
                200
            )
        ])

        let client = KilterClient(dataLoader: { request in
            try await recorder.load(request)
        })
        let token = try await client.login(username: "user@example.com", password: "p&ss word+")
        let logs = try await client.fetchLogs(accessToken: token.accessToken)

        XCTAssertEqual(token.accessToken, "token-123")
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.climbRating?.difficultyGradeId, nil)

        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://idp.kiltergrips.com/realms/kilter/protocol/openid-connect/token")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")

        let body = String(data: try XCTUnwrap(requests[0].httpBody), encoding: .utf8)
        XCTAssertTrue(body?.contains("grant_type=password") == true)
        XCTAssertTrue(body?.contains("client_id=kilter") == true)
        XCTAssertTrue(body?.contains("username=user%40example.com") == true)
        XCTAssertTrue(body?.contains("password=p%26ss+word%2B") == true)

        XCTAssertEqual(requests[1].url?.absoluteString, "https://portal.kiltergrips.com/api/logs/")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer token-123")
    }

    @MainActor
    func testKilterApplyRowsInsertsUpdatesAndMarksPreviouslyClimbed() throws {
        let firstDate = try XCTUnwrap(BoardDateParser.parse("2026-06-02T18:53:20.416361Z"))
        let secondDate = try XCTUnwrap(BoardDateParser.parse("2026-06-03T18:53:20.416361Z"))

        try KilterSyncManager.applyRows([
            KilterSyncManager.Row(
                logUuid: "log-1",
                climbUuid: "climb-a",
                day: firstDate,
                topped: true,
                angle: 40,
                attempts: 1,
                flashed: true,
                climbName: "First",
                grade: BoardGradeMapper.grade(of: 19),
                feelsLikeGrade: nil
            ),
            KilterSyncManager.Row(
                logUuid: "log-2",
                climbUuid: "climb-a",
                day: secondDate,
                topped: true,
                angle: 40,
                attempts: 2,
                flashed: false,
                climbName: "Second",
                grade: BoardGradeMapper.grade(of: 21),
                feelsLikeGrade: BoardGradeMapper.grade(of: 20)
            )
        ], into: context)

        var climbs = try context.fetch(FetchDescriptor<ClimbEntry>(sortBy: [SortDescriptor(\.dateLogged)]))
        XCTAssertEqual(climbs.count, 2)
        XCTAssertEqual(climbs[0].style, "Kilter board")
        XCTAssertNil(climbs[0].tb2ClimbUUID)
        XCTAssertEqual(climbs[0].kilterLogUuid, "log-1")
        XCTAssertEqual(climbs[0].kilterClimbUuid, "climb-a")
        XCTAssertEqual(climbs[0].isPreviouslyClimbed, false)
        XCTAssertEqual(climbs[1].isPreviouslyClimbed, true)
        XCTAssertEqual(climbs[1].feelsLikeGrade, "6c")

        try KilterSyncManager.applyRows([
            KilterSyncManager.Row(
                logUuid: "log-1",
                climbUuid: "climb-a",
                day: firstDate,
                topped: false,
                angle: 40,
                attempts: 3,
                flashed: false,
                climbName: "First updated",
                grade: BoardGradeMapper.grade(of: 20),
                feelsLikeGrade: nil
            )
        ], into: context)

        climbs = try context.fetch(FetchDescriptor<ClimbEntry>(sortBy: [SortDescriptor(\.dateLogged)]))
        XCTAssertEqual(climbs.count, 2)
        let updated = try XCTUnwrap(climbs.first { $0.kilterLogUuid == "log-1" })
        XCTAssertEqual(updated.attempts, "3")
        XCTAssertEqual(updated.grade, "6c")
        XCTAssertTrue(updated.isWorkInProgress)
        XCTAssertEqual(updated.notes, "First updated")
    }

    func testKilterLogsDecodeWithOptionalClimbRating() throws {
        let data = Data("""
        [
          {
            "logUuid": "log-1",
            "climbUuid": "climb-1",
            "angle": 40,
            "flashed": false,
            "topped": true,
            "attempts": 2,
            "createdAt": "2026-06-02T18:32:24.065921Z",
            "climbName": "Not in the Light",
            "currentDifficultyId": 21,
            "climbRating": {
              "difficultyGradeId": 20,
              "comment": "nice"
            }
          },
          {
            "logUuid": "log-2",
            "climbUuid": "climb-2",
            "angle": 30,
            "flashed": true,
            "topped": false,
            "attempts": 1,
            "createdAt": "2026-06-02T18:53:20.416361Z",
            "climbName": "No Rating",
            "currentDifficultyId": 19
          }
        ]
        """.utf8)

        let logs = try JSONDecoder().decode([KilterLog].self, from: data)

        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(logs[0].climbRating?.difficultyGradeId, 20)
        XCTAssertNil(logs[1].climbRating)
    }
}

private actor KilterRequestRecorder {
    private var responses: [(Data, Int)]
    private var storedRequests: [URLRequest] = []

    init(responses: [(Data, Int)]) {
        self.responses = responses
    }

    var requests: [URLRequest] {
        storedRequests
    }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        storedRequests.append(request)
        let response = responses.removeFirst()

        let http = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: response.1,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response.0, http)
    }
}
