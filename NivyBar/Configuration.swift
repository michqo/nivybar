//
//  Configuration.swift
//  NivyBar
//

import Foundation

/// Magic strings, numbers, and defaults in one place.
/// No raw values scattered in the codebase.
enum Configuration {

    // MARK: - Network

    enum Network {
        static let userAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
            "Version/17.4 Safari/605.1.15"

        static let acceptHeader         = "text/html,application/xhtml+xml"
        static let acceptLanguageHeader = "sk-SK,sk;q=0.9,en;q=0.8"
        static let cacheControlHeader   = "no-cache"
        static let jsonContentType      = "application/json"

        static let timeout: TimeInterval         = 15
        static let aiTimeout: TimeInterval       = 60
        static let modelsTimeout: TimeInterval   = 30
        static let jinaTimeout: TimeInterval     = 30
    }

    // MARK: - Jina.ai

    enum Jina {
        static let baseURL = "https://r.jina.ai/"
    }

    // MARK: - AI

    enum AI {
        static let htmlTruncationLimit  = 30_000
        static let spaBodyThreshold     = 800
        static let spaStrippedThreshold = 500
        static let defaultBaseURL       = "https://api.openai.com/v1"
        static let dailyLimitDefault    = 20

        static let modelFallbackChain: [String] = [
            "claude-sonnet-4-6",
            "gpt-5-mini",
            "haiku",
        ]

        static let reasoningModelPrefixes: [String] = [
            "gpt-5", "o1", "o3", "o4",
        ]

        // MARK: UserDefaults keys

        static let baseURLKey        = "ai.baseURL"
        static let apiKeyKey         = "ai.apiKey"
        static let modelKey          = "ai.model"
        static let dailyLimitKey     = "ai.dailyLimit"
        static let availableModelsKey          = "ai.availableModels"
        static let availableModelsFetchedAtKey = "ai.availableModelsFetchedAt"

        // MARK: OpenAI env var names

        static let envBaseURLKey     = "OPENAI_BASE_URL"
        static let envAPIKeyKey      = "OPENAI_API_KEY"
        static let envModelKey       = "OPENAI_MODEL"
        static let envDailyLimitKey  = "NIVY_AI_DAILY_LIMIT"
    }

    // MARK: - UI

    enum UI {
        static let menuBarIcon       = "fork.knife"
        static let settingsWindowID  = "settings"
        static let windowMinWidth: CGFloat  = 700
        static let windowMinHeight: CGFloat = 500
        static let defaultWindowWidth: CGFloat  = 760
        static let defaultWindowHeight: CGFloat = 540
        static let menuPanelWidth: CGFloat  = 340
        static let menuPanelHeight: CGFloat = 480

        static let iconKomín         = "mug.fill"
        static let iconDefault       = "fork.knife.circle"
        static let iconGear          = "gearshape"
        static let iconClock         = "clock"
        static let iconRefresh       = "arrow.clockwise"
        static let iconExclamation   = "exclamationmark.triangle"
        static let iconTrash         = "trash"
        static let iconSparkles      = "sparkles"
        static let iconPlus          = "plus"
        static let iconStarFill      = "star.fill"
        static let iconPlayCircle    = "play.circle"
        static let iconCheckmark     = "checkmark"
        static let iconInfoCircle    = "info.circle"

        static let accentColorPresets: [(name: String, hex: String)] = [
            ("Orange", "#FF6B35"),
            ("Red",    "#E74C3C"),
            ("Blue",   "#3498DB"),
            ("Green",  "#2ECC71"),
            ("Purple", "#9B59B6"),
            ("Yellow", "#F1C40F"),
            ("Teal",   "#1ABC9C"),
            ("Pink",   "#E91E63"),
        ]
    }

    // MARK: - System

    enum System {
        static let appSupportFolder = "NivyBar"
        static let cacheFileName    = "cached_menus.json"
        static let storeFileName    = "user_restaurants.json"
        static let dateFormat       = "yyyy-MM-dd"
        static let skLocale         = "sk_SK"

        // Rate limiter UserDefaults keys
        static let rateLimitCountKey = "AIRateLimiter.count"
        static let rateLimitDateKey  = "AIRateLimiter.date"
    }
}
