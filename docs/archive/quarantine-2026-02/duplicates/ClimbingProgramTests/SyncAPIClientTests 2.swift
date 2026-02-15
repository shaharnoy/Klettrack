import XCTest
@testable import klettrack

final class SyncAPIClientTests: XCTestCase {
    private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
        static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }

            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private actor TokenCounter {
        private(set) var tokenProviderCalls = 0
        private(set) var forceRefreshCalls = 0

        func nextToken() -> String {
            tokenProviderCalls += 1
            return "token-\(tokenProviderCalls)"
        }

        func refreshedToken() -> String {
            forceRefreshCalls += 1
            return "refreshed-\(forceRefreshCalls)"
        }

        func snapshot() -> (tokenProviderCalls: Int, forceRefreshCalls: Int) {
            (tokenProviderCalls, forceRefreshCalls)
        }
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testPushRefreshesTokenOnceAfterUnauthorizedAndRetries() async throws {
        let baseURL = try XCTUnwrap(URL(string: "https://example.com/functions/v1/sync"))
        let counter = TokenCounter()

        let client = SyncAPIClient(
            configuration: SyncAPIConfiguration(syncFunctionBaseURL: baseURL),
            tokenProvider: {
                await counter.nextToken()
            },
            forceRefreshTokenProvider: {
                await counter.refreshedToken()
            },
            session: makeSession()
        )

        MockURLProtocol.handler = { request in
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            if auth == "Bearer token-1" {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                    Data("{\"error\":\"unauthorized\"}".utf8)
                )
            }

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{\"acknowledgedOpIds\":[],\"conflicts\":[],\"failed\":[],\"newCursor\":\"cursor-1\"}".utf8)
            )
        }

        let response = try await client.push(
            request: SyncPushRequest(deviceId: "device-a", baseCursor: nil, mutations: [])
        )
        let counts = await counter.snapshot()

        XCTAssertEqual(response.newCursor, "cursor-1")
        XCTAssertEqual(counts.tokenProviderCalls, 1)
        XCTAssertEqual(counts.forceRefreshCalls, 1)
    }

    func testPushWithoutForceRefreshProviderThrowsUnauthorized() async {
        let baseURL = URL(string: "https://example.com/functions/v1/sync")!
        let client = SyncAPIClient(
            configuration: SyncAPIConfiguration(syncFunctionBaseURL: baseURL),
            tokenProvider: { "token-1" },
            forceRefreshTokenProvider: nil,
            session: makeSession()
        )

        MockURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data("{\"error\":\"unauthorized\"}".utf8)
            )
        }

        do {
            _ = try await client.push(request: SyncPushRequest(deviceId: "device-a", baseCursor: nil, mutations: []))
            XCTFail("Expected unauthorized error")
        } catch let error as SyncAPIError {
            guard case .unauthorized = error else {
                return XCTFail("Expected unauthorized, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
