//
//  AIConfig.swift
//  NivyBar
//

import Foundation

/// Resolves AI configuration from UserDefaults first, then environment vars.
/// GUI apps launched from Finder/Xcode don't inherit shell env (fish/zsh),
/// so UserDefaults is the primary source for interactive users.
enum AIConfig {

    nonisolated static let defaultBaseURL = Configuration.AI.defaultBaseURL

    // MARK: - Key aliases (backward compat, prefer Configuration.AI directly)

    nonisolated static let baseURLKey                = Configuration.AI.baseURLKey
    nonisolated static let apiKeyKey                 = Configuration.AI.apiKeyKey
    nonisolated static let modelKey                  = Configuration.AI.modelKey
    nonisolated static let dailyLimitKey             = Configuration.AI.dailyLimitKey
    nonisolated static let availableModelsKey         = Configuration.AI.availableModelsKey
    nonisolated static let availableModelsFetchedAtKey = Configuration.AI.availableModelsFetchedAtKey

    // MARK: - Base URL

    nonisolated static var baseURL: String? {
        let ud = UserDefaults.standard.string(forKey: Configuration.AI.baseURLKey)
        if let ud, !ud.isEmpty { return ud }
        return ProcessInfo.processInfo.environment[Configuration.AI.envBaseURLKey]
            ?? defaultBaseURL
    }

    // MARK: - API Key

    nonisolated static var apiKey: String? {
        let ud = UserDefaults.standard.string(forKey: Configuration.AI.apiKeyKey)
        if let ud, !ud.isEmpty { return ud }
        return ProcessInfo.processInfo.environment[Configuration.AI.envAPIKeyKey]
    }

    // MARK: - Model

    nonisolated static var model: String? {
        let ud = UserDefaults.standard.string(forKey: Configuration.AI.modelKey)
        if let ud, !ud.isEmpty { return ud }
        return ProcessInfo.processInfo.environment[Configuration.AI.envModelKey]
    }

    // MARK: - Status

    nonisolated static var isConfigured: Bool {
        baseURL != nil && apiKey != nil
    }

    // MARK: - Daily limit

    nonisolated static var dailyLimit: Int {
        let ud = UserDefaults.standard.integer(forKey: Configuration.AI.dailyLimitKey)
        if ud > 0 { return ud }
        if let raw = ProcessInfo.processInfo.environment[Configuration.AI.envDailyLimitKey],
           let n = Int(raw), n > 0 { return n }
        return Configuration.AI.dailyLimitDefault
    }

    // MARK: - Available models cache

    nonisolated static var availableModels: [String] {
        UserDefaults.standard.stringArray(forKey: Configuration.AI.availableModelsKey) ?? []
    }

    nonisolated static func setAvailableModels(_ models: [String]) {
        UserDefaults.standard.set(models, forKey: Configuration.AI.availableModelsKey)
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: Configuration.AI.availableModelsFetchedAtKey
        )
    }

    // MARK: - Reset

    nonisolated static func resetAll() {
        let keys = [
            Configuration.AI.baseURLKey,
            Configuration.AI.apiKeyKey,
            Configuration.AI.modelKey,
            Configuration.AI.dailyLimitKey,
            Configuration.AI.availableModelsKey,
            Configuration.AI.availableModelsFetchedAtKey,
        ]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
}
