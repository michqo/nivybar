//
//  AIRecipeGenerator.swift
//  NivyBar
//

import Foundation
import SwiftSoup

// MARK: - AI Error

enum AIError: LocalizedError, Sendable {
    case missingConfig(String)
    case networkError(String)
    case httpError(Int, String)
    case emptyResponse
    case jsonParseFailure(String)   // raw AI text included so UI can show it

    var errorDescription: String? {
        switch self {
        case .missingConfig(let m):     return "Configuration error: \(m)"
        case .networkError(let m):      return "Network error: \(m)"
        case .httpError(let code, let m): return "HTTP \(code): \(m)"
        case .emptyResponse:            return "AI returned an empty response."
        case .jsonParseFailure(let raw): return "Could not parse AI response. Raw: \(raw)"
        }
    }

    /// Raw AI text — non-nil only for jsonParseFailure
    var rawAIResponse: String? {
        if case .jsonParseFailure(let raw) = self { return raw }
        return nil
    }
}

// MARK: - AIConfig

/// Resolves AI configuration from UserDefaults first, then environment vars.
/// GUI apps launched from Finder/Xcode don't inherit shell env (fish/zsh),
/// so UserDefaults is the primary source for interactive users.
enum AIConfig {

    nonisolated static let defaultBaseURL = "https://api.openai.com/v1"
    nonisolated static let baseURLKey    = "ai.baseURL"
    nonisolated static let apiKeyKey     = "ai.apiKey"
    nonisolated static let modelKey      = "ai.model"
    nonisolated static let dailyLimitKey = "ai.dailyLimit"
    nonisolated static let availableModelsKey = "ai.availableModels"
    nonisolated static let availableModelsFetchedAtKey = "ai.availableModelsFetchedAt"

    nonisolated static var baseURL: String? {
        let ud = UserDefaults.standard.string(forKey: baseURLKey)
        if let ud, !ud.isEmpty { return ud }
        return ProcessInfo.processInfo.environment["OPENAI_BASE_URL"]
            ?? defaultBaseURL
    }

    nonisolated static var availableModels: [String] {
        UserDefaults.standard.stringArray(forKey: availableModelsKey) ?? []
    }

    nonisolated static func setAvailableModels(_ models: [String]) {
        UserDefaults.standard.set(models, forKey: availableModelsKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: availableModelsFetchedAtKey)
    }

    nonisolated static var apiKey: String? {
        let ud = UserDefaults.standard.string(forKey: apiKeyKey)
        if let ud, !ud.isEmpty { return ud }
        return ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
    }

    nonisolated static var model: String? {
        let ud = UserDefaults.standard.string(forKey: modelKey)
        if let ud, !ud.isEmpty { return ud }
        return ProcessInfo.processInfo.environment["OPENAI_MODEL"]
    }

    nonisolated static var isConfigured: Bool {
        baseURL != nil && apiKey != nil
    }

    nonisolated static var dailyLimit: Int {
        let ud = UserDefaults.standard.integer(forKey: dailyLimitKey)
        if ud > 0 { return ud }
        if let raw = ProcessInfo.processInfo.environment["NIVY_AI_DAILY_LIMIT"],
           let n = Int(raw), n > 0 { return n }
        return 20
    }
}

// MARK: - Rate limit error

extension AIError {
    static func rateLimitExceeded(used: Int, limit: Int) -> AIError {
        .missingConfig("Daily AI call limit reached (\(used)/\(limit)). Reset tomorrow or raise limit in Settings → AI.")
    }
}

// MARK: - AIRateLimiter

/// Persists call count per calendar day to UserDefaults.
/// Thread-safe: all mutations are serialized through a lock.
final class AIRateLimiter: @unchecked Sendable {

    nonisolated static let shared = AIRateLimiter()
    private init() {}

    private let lock = NSLock()
    private let countKey = "AIRateLimiter.count"
    private let dateKey  = "AIRateLimiter.date"

    private var dailyLimit: Int { AIConfig.dailyLimit }

    private var todayString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    /// Returns (allowed: Bool, used: Int, limit: Int)
    nonisolated func checkAndIncrement() -> (allowed: Bool, used: Int, limit: Int) {
        lock.lock()
        defer { lock.unlock() }

        let today = todayString
        let storedDate = UserDefaults.standard.string(forKey: dateKey) ?? ""

        // Reset counter on new day
        if storedDate != today {
            UserDefaults.standard.set(today, forKey: dateKey)
            UserDefaults.standard.set(0, forKey: countKey)
        }

        let current = UserDefaults.standard.integer(forKey: countKey)
        let limit   = dailyLimit

        guard current < limit else {
            return (false, current, limit)
        }

        UserDefaults.standard.set(current + 1, forKey: countKey)
        return (true, current + 1, limit)
    }

    nonisolated var currentUsage: (used: Int, limit: Int) {
        lock.lock()
        defer { lock.unlock() }
        let today = todayString
        let storedDate = UserDefaults.standard.string(forKey: dateKey) ?? ""
        if storedDate != today { return (0, dailyLimit) }
        return (UserDefaults.standard.integer(forKey: countKey), dailyLimit)
    }
}

// MARK: - AIRecipeGenerator

final class AIRecipeGenerator: @unchecked Sendable {

    static let shared = AIRecipeGenerator()
    private init() {}

    private let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
        "Version/17.4 Safari/605.1.15"

    private let htmlTruncationLimit = 30_000

    // Model preference order — first available in env wins, then these fallbacks
    private let modelFallbackChain = [
        "claude-sonnet-4-6",    // best at HTML structure + JSON
        "gpt-5-mini",           // fast, cheap, reliable JSON
        "haiku",                // smallest Claude if above unavailable
    ]

    private let baseSystemPrompt = """
        You are an expert web scraper analyzing a restaurant daily menu page.
        Identify CSS selectors to extract:
        1. Restaurant name (as text on the page)
        2. Location or address shown on the page (if present)
        3. Soup of the day (if present, otherwise omit the key entirely)
        4. The repeating row/container element for each main dish
        5. Dish name relative to the row container
        6. Dish price relative to the row container if present, otherwise omit

        Also suggest a hex accent color that matches the website's design.
        If the site has an obvious brand color, use that. Otherwise pick a warm,
        food-friendly color (orange, red, green, teal, brown, etc).

        Respond ONLY with raw JSON, no markdown, no backticks, matching exactly this schema:
        {
          "extractedName": "actual restaurant name shown on the page",
          "extractedLocation": "neighborhood or address if available, otherwise omit",
          "restaurantNameSelector": "CSS selector for the restaurant name element",
          "soupSelector": "string",
          "mealRowSelector": "string",
          "mealNameSelector": "string",
          "mealPriceSelector": "string",
          "notes": "brief explanation of the page structure and any caveats",
          "suggestedColorHex": "#FF6B35"
        }
        """

    nonisolated private func buildSystemPrompt() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        let todayString = formatter.string(from: Date())

        return """
        Today is \(todayString). Extract ONLY today's menu.
        If the page lists the whole week, pick only the section/block for today and ignore other days.

        \(baseSystemPrompt)
        """
    }

    // MARK: - Public

    nonisolated func generateRecipe(for urlString: String) async -> Result<ScrapingRecipe, AIError> {
        // 0. Rate limit check — before any network work
        let rateCheck = AIRateLimiter.shared.checkAndIncrement()
        guard rateCheck.allowed else {
            return .failure(.rateLimitExceeded(used: rateCheck.used, limit: rateCheck.limit))
        }

        // 1. Read config from AIConfig (UserDefaults → env fallback)
        guard let baseURL = AIConfig.baseURL else {
            return .failure(.missingConfig("OPENAI_BASE_URL not set. Configure in Settings → AI."))
        }
        guard let apiKey = AIConfig.apiKey else {
            return .failure(.missingConfig("OPENAI_API_KEY not set. Configure in Settings → AI."))
        }
        let model = AIConfig.model ?? modelFallbackChain[0]

        // 2. Fetch HTML with Jina fallback
        let htmlResult = await fetchHTMLWithFallback(urlString: urlString)
        let rawHTML: String
        let usedJina: Bool
        switch htmlResult {
        case .success(let result):
            rawHTML = result.html
            usedJina = result.usedJina
        case .failure(let err):  return .failure(err)
        }

        // 3. Strip noise tags via SwiftSoup
        let stripped = stripNoiseTags(from: rawHTML)

        // 4. Truncate
        let truncated: String
        if stripped.count > htmlTruncationLimit {
            truncated = String(stripped.prefix(htmlTruncationLimit))
                + "\n\n[Content truncated at \(htmlTruncationLimit) characters]"
        } else {
            truncated = stripped
        }

        // 5. Try primary model, then each fallback in chain
        // (skip fallbacks if the user set a model explicitly via UD or env)
        let chain: [String] = AIConfig.model != nil
            ? [model]
            : ([model] + modelFallbackChain.filter { $0 != model })

        var lastError: AIError = .emptyResponse
        for candidate in chain {
            let result = await callLLM(
                html: truncated,
                baseURL: baseURL,
                apiKey: apiKey,
                model: candidate
            )
            switch result {
            case .success(let recipe):
                var patched = recipe
                patched.usesJavaScript = usedJina
                return .success(patched)
            case .failure(let err):
                // Only retry on HTTP 4xx model-not-found / quota errors,
                // not on parse failures (those are model-agnostic content issues)
                if case .jsonParseFailure = err { return result }
                if case .emptyResponse = err    { return result }
                lastError = err
                // Continue to next model in chain
            }
        }
        return .failure(lastError)
    }

    // MARK: - HTML fetch with Jina.ai fallback

    nonisolated private func fetchHTMLWithFallback(urlString: String) async -> Result<(html: String, usedJina: Bool), AIError> {
        // Primary fetch
        let primary = await fetchHTML(from: urlString)
        switch primary {
        case .success(let html):
            // JS-rendered detection: body text too short means no real content
            let bodyText = (try? SwiftSoup.parse(html).body()?.text()) ?? ""
            if bodyText.count >= 800 {
                return .success((html, false))
            }
            // Additional check: strip scripts/styles, remaining text < 500 = SPA
            let stripped = stripNoiseTags(from: html)
            let strippedBody = (try? SwiftSoup.parse(stripped).body()?.text()) ?? ""
            if strippedBody.count >= 500 {
                return .success((html, false))
            }
            // Fall through to Jina
        case .failure:
            break
        }

        // Jina.ai fallback — returns rendered HTML/text
        let jinaURL = "https://r.jina.ai/\(urlString)"
        let fallback = await fetchHTML(from: jinaURL)
        switch fallback {
        case .success(let html):
            return .success((html, true))
        case .failure(let err):
            return .failure(err)
        }
    }

    nonisolated private func fetchHTML(from urlString: String) async -> Result<String, AIError> {
        guard let url = URL(string: urlString) else {
            return .failure(.networkError("Invalid URL: \(urlString)"))
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8)
                          ?? String(data: data, encoding: .isoLatin1) else {
                return .failure(.networkError("Could not decode response from \(urlString)"))
            }
            return .success(html)
        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }

    // MARK: - HTML stripping

    nonisolated private func stripNoiseTags(from html: String) -> String {
        guard let doc = try? SwiftSoup.parse(html) else { return html }
        let noiseTags = ["script", "style", "svg", "noscript", "iframe", "link", "meta"]
        for tag in noiseTags {
            try? doc.select(tag).remove()
        }
        return (try? doc.html()) ?? html
    }

    // MARK: - LLM call

    nonisolated private func supportsTemperature(_ model: String) -> Bool {
        let lower = model.lowercased()
        let reasoningPrefixes = ["gpt-5", "o1", "o3", "o4"]
        for prefix in reasoningPrefixes {
            if lower.hasPrefix(prefix) { return false }
        }
        return true
    }

    nonisolated private func callLLM(
        html: String,
        baseURL: String,
        apiKey: String,
        model: String
    ) async -> Result<ScrapingRecipe, AIError> {
        // Build endpoint URL — strip trailing slash, append /chat/completions
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let endpoint = "\(base)/chat/completions"
        guard let url = URL(string: endpoint) else {
            return .failure(.networkError("Invalid OPENAI_BASE_URL: \(baseURL)"))
        }

        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": buildSystemPrompt()],
                ["role": "user",   "content": "Here is the restaurant page HTML:\n\n\(html)"]
            ]
        ]
        if supportsTemperature(model) {
            body["temperature"] = 0.1
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure(.networkError("Failed to serialize request body"))
        }

        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                return .failure(.httpError(http.statusCode, msg))
            }

            // Parse OpenAI-compatible response
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = json["choices"] as? [[String: Any]],
                let first = choices.first,
                let message = first["message"] as? [String: Any],
                let content = message["content"] as? String
            else {
                let raw = String(data: data, encoding: .utf8) ?? ""
                return .failure(.jsonParseFailure(raw))
            }

            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return .failure(.emptyResponse) }

            // Parse recipe JSON
            return parseRecipe(from: trimmed)

        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }

    // MARK: - Available models

    nonisolated func fetchAvailableModels() async -> Result<[String], AIError> {
        guard let baseURL = AIConfig.baseURL else {
            return .failure(.missingConfig("OPENAI_BASE_URL not set. Configure in Settings → AI."))
        }
        guard let apiKey = AIConfig.apiKey else {
            return .failure(.missingConfig("OPENAI_API_KEY not set. Configure in Settings → AI."))
        }

        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let endpoint = "\(base)/models"
        guard let url = URL(string: endpoint) else {
            return .failure(.networkError("Invalid OPENAI_BASE_URL: \(baseURL)"))
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                return .failure(.httpError(http.statusCode, msg))
            }

            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let modelsArray = json["data"] as? [[String: Any]]
            else {
                let raw = String(data: data, encoding: .utf8) ?? ""
                return .failure(.jsonParseFailure(raw))
            }

            let ids: [String] = modelsArray.compactMap { $0["id"] as? String }
                .sorted()
            AIConfig.setAvailableModels(ids)
            return .success(ids)

        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }

    // MARK: - Recipe JSON parsing

    nonisolated private func parseRecipe(from text: String) -> Result<ScrapingRecipe, AIError> {
        // Strip markdown code fences if AI ignored instructions
        var cleaned = text
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: #"^```[a-zA-Z]*\n?"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\n?```$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.jsonParseFailure(text))
        }

        guard
            let nameSelector  = json["restaurantNameSelector"] as? String,
            let rowSelector   = json["mealRowSelector"] as? String,
            let nameInRow     = json["mealNameSelector"] as? String
        else {
            return .failure(.jsonParseFailure(text))
        }

        let recipe = ScrapingRecipe(
            restaurantNameSelector: nameSelector,
            soupSelector:           json["soupSelector"] as? String,
            mealRowSelector:        rowSelector,
            mealNameSelector:       nameInRow,
            mealPriceSelector:      json["mealPriceSelector"] as? String,
            notes:                  json["notes"] as? String,
            extractedName:          json["extractedName"] as? String,
            extractedLocation:      json["extractedLocation"] as? String,
            suggestedColorHex:      json["suggestedColorHex"] as? String
        )
        return .success(recipe)
    }
}
