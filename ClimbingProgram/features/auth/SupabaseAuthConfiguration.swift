//
//  SupabaseAuthConfiguration.swift
//  klettrack
//
//  Created by Shahar Noy on 10.02.26.
//

import Foundation

struct SupabaseAuthConfiguration: Sendable {
    let projectURL: URL
    let publishableKey: String
    let usernameResolverURL: URL?

    var syncFunctionBaseURL: URL {
        projectURL.appending(path: "functions").appending(path: "v1").appending(path: "sync")
    }

    static func load() -> SupabaseAuthConfiguration? {
        let env = ProcessInfo.processInfo.environment

        let bundleURL = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        let bundleKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String
        let bundleResolver = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_USERNAME_RESOLVER_URL") as? String

        let defaults = UserDefaults.standard
        let defaultsURL = defaults.string(forKey: "supabase.url")
        let defaultsKey = defaults.string(forKey: "supabase.publishableKey")
        let defaultsResolver = defaults.string(forKey: "supabase.usernameResolverURL")

        let rawURL = firstNonEmpty([
            env["SUPABASE_URL"],
            defaultsURL,
            bundleURL
        ])
        let rawKey = firstNonEmpty([
            env["SUPABASE_PUBLISHABLE_KEY"],
            defaultsKey,
            bundleKey
        ])
        let rawResolver = firstNonEmpty([
            env["SUPABASE_USERNAME_RESOLVER_URL"],
            defaultsResolver,
            bundleResolver
        ])

        guard
            let rawURL,
            let url = URL(string: rawURL),
            let rawKey,
            !rawKey.isEmpty
        else {
            return nil
        }

        let resolverURL = rawResolver.flatMap { URL(string: $0) }
        return SupabaseAuthConfiguration(
            projectURL: url,
            publishableKey: rawKey,
            usernameResolverURL: resolverURL
        )
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                continue
            }
            return trimmed
        }
        return nil
    }
}
