//
//  SupabaseAuthErrorTests.swift
//  klettrack tests
//
//  Created by Codex on 25.02.26.
//

import XCTest
@testable import klettrack

final class SupabaseAuthErrorTests: XCTestCase {
    func testSessionInvalidUnauthorizedRequiresReauthentication() {
        let error = SupabaseAuthError.unauthorized(reason: .sessionInvalid)
        XCTAssertTrue(error.requiresReauthentication)
        XCTAssertFalse(error.isTransient)
    }

    func testCredentialsUnauthorizedDoesNotRequireReauthentication() {
        let error = SupabaseAuthError.unauthorized(reason: .credentialsInvalid)
        XCTAssertFalse(error.requiresReauthentication)
        XCTAssertFalse(error.isTransient)
    }

    func testTransientErrorsAreMarkedTransient() {
        XCTAssertTrue(SupabaseAuthError.transientNetwork.isTransient)
        XCTAssertTrue(SupabaseAuthError.transientServer(statusCode: 503).isTransient)
    }
}
