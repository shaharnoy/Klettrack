//
//  SupabaseSession.swift
//  klettrack
//
//  Created by Shahar Noy on 10.02.26.
//

import Foundation

struct SupabaseSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresAt: Date
    let userID: String
    let email: String?
}
