//
//  NivyBarError.swift
//  NivyBar
//

import Foundation

/// Unified domain error for the entire app.
/// Replaces the old ScraperError and AIError enums.
enum NivyBarError: LocalizedError, Sendable {

    // MARK: - Networking

    case networkFailure(String)
    case httpFailure(Int, String)
    case jinaFallbackFailed(String)
    case invalidURL(String)

    // MARK: - Parsing

    case parseFailure(String)
    case htmlStrippingFailed
    case aiParsingFailed(rawResponse: String)
    case emptyResponse

    // MARK: - Domain

    case menuNotFound(String)
    case weekend
    case missingConfig(String)
    case rateLimitExceeded(used: Int, limit: Int)
    case invalidSelectors(String)

    // MARK: - Storage

    case cacheLoadFailed(String)
    case cacheWriteFailed(String)
    case storeDecodeFailed(String)

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .networkFailure(let msg):
            return "Network error: \(msg)"
        case .httpFailure(let code, let msg):
            return "HTTP \(code): \(msg)"
        case .jinaFallbackFailed(let msg):
            return "Jina fallback failed: \(msg)"
        case .invalidURL(let msg):
            return "Invalid URL: \(msg)"
        case .parseFailure(let msg):
            return "Parse error: \(msg)"
        case .htmlStrippingFailed:
            return "Failed to strip HTML tags."
        case .aiParsingFailed(let raw):
            return "Could not parse AI response."
        case .emptyResponse:
            return "AI returned an empty response."
        case .menuNotFound(let msg):
            return msg
        case .weekend:
            return "Cez víkend nie je obedové menu."
        case .missingConfig(let msg):
            return "Configuration error: \(msg)"
        case .rateLimitExceeded(let used, let limit):
            return "Daily AI call limit reached (\(used)/\(limit)). Reset tomorrow or raise limit in Settings → AI."
        case .invalidSelectors(let msg):
            return "Selectors returned no results. \(msg)"
        case .cacheLoadFailed(let path):
            return "Failed to load cache: \(path)"
        case .cacheWriteFailed(let path):
            return "Failed to save cache: \(path)"
        case .storeDecodeFailed(let path):
            return "Failed to decode saved data: \(path)"
        }
    }

    /// Raw AI response text — non-nil only for aiParsingFailed
    var rawAIResponse: String? {
        if case .aiParsingFailed(let raw) = self { return raw }
        return nil
    }
}
