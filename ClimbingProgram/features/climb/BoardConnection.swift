//
//  BoardConnection.swift
//  Klettrack
//

import Foundation

enum BoardConnection: String, Identifiable {
    case tension
    case kilter

    var id: Self { self }

    var credentialsHeader: String {
        switch self {
        case .tension: return "TB2 login details"
        case .kilter: return "Kilter login details"
        }
    }

    var displayName: String {
        switch self {
        case .tension: return "Tension Board"
        case .kilter: return "Kilter"
        }
    }

    var missingCredentialsMessage: String {
        switch self {
        case .tension: return "Please enter your Tension board credentials."
        case .kilter: return "Please enter your Kilter board credentials."
        }
    }
}
