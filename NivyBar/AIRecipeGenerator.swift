//
//  AIRecipeGenerator.swift
//  NivyBar
//

import Foundation
import SwiftSoup

// MARK: - AIRecipeGenerator

final class AIRecipeGenerator: @unchecked Sendable {

    static let shared = AIRecipeGenerator()

    private let fetcher: HTMLFetching
    private let rateLimiter: AIRateLimiter

    init(fetcher: HTMLFetching = HTMLFetcher(),
         rateLimiter: AIRateLimiter = .shared) {
        self.fetcher = fetcher
        self.rateLimiter = rateLimiter
    }

    private let htmlTruncationLimit = Configuration.AI.htmlTruncationLimit

    private let modelFallbackChain = Configuration.AI.modelFallbackChain

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

    nonisolated func generateRecipe(for urlString: String) async -> Result<ScrapingRecipe, NivyBarError> {
        let rateCheck = rateLimiter.checkAndIncrement()
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

        var lastError: NivyBarError = .emptyResponse
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
                if case .aiParsingFailed = err { return result }
                if case .emptyResponse = err    { return result }
                lastError = err
                // Continue to next model in chain
            }
        }
        return .failure(lastError)
    }

    // MARK: - HTML fetch with Jina.ai fallback

    nonisolated private func fetchHTMLWithFallback(urlString: String) async -> Result<(html: String, usedJina: Bool), NivyBarError> {
        do {
            let html = try await fetcher.fetch(urlString: urlString)
            let bodyText = (try? SwiftSoup.parse(html).body()?.text()) ?? ""
            if bodyText.count >= Configuration.AI.spaBodyThreshold {
                return .success((html, false))
            }
            let stripped = stripNoiseTags(from: html)
            let strippedBody = (try? SwiftSoup.parse(stripped).body()?.text()) ?? ""
            if strippedBody.count >= Configuration.AI.spaStrippedThreshold {
                return .success((html, false))
            }
        } catch let e as NivyBarError {
            // Primary fetch failed, fall through to Jina
            _ = e
        } catch {
            // Unexpected error, fall through to Jina
        }

        do {
            let html = try await fetcher.fetchViaJina(urlString: urlString)
            return .success((html, true))
        } catch let e as NivyBarError {
            return .failure(e)
        } catch {
            return .failure(.networkFailure(error.localizedDescription))
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
        for prefix in Configuration.AI.reasoningModelPrefixes {
            if lower.hasPrefix(prefix) { return false }
        }
        return true
    }

    nonisolated private func callLLM(
        html: String,
        baseURL: String,
        apiKey: String,
        model: String
    ) async -> Result<ScrapingRecipe, NivyBarError> {
        // Build endpoint URL — strip trailing slash, append /chat/completions
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let endpoint = "\(base)/chat/completions"
        guard let url = URL(string: endpoint) else {
            return .failure(.networkFailure("Invalid OPENAI_BASE_URL: \(baseURL)"))
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
            return .failure(.networkFailure("Failed to serialize request body"))
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
                return .failure(.httpFailure(http.statusCode, msg))
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
                return .failure(.aiParsingFailed(rawResponse:raw))
            }

            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return .failure(.emptyResponse) }

            // Parse recipe JSON
            return parseRecipe(from: trimmed)

        } catch {
            return .failure(.networkFailure(error.localizedDescription))
        }
    }

    // MARK: - Available models

    nonisolated func fetchAvailableModels() async -> Result<[String], NivyBarError> {
        guard let baseURL = AIConfig.baseURL else {
            return .failure(.missingConfig("OPENAI_BASE_URL not set. Configure in Settings → AI."))
        }
        guard let apiKey = AIConfig.apiKey else {
            return .failure(.missingConfig("OPENAI_API_KEY not set. Configure in Settings → AI."))
        }

        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let endpoint = "\(base)/models"
        guard let url = URL(string: endpoint) else {
            return .failure(.networkFailure("Invalid OPENAI_BASE_URL: \(baseURL)"))
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                return .failure(.httpFailure(http.statusCode, msg))
            }

            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let modelsArray = json["data"] as? [[String: Any]]
            else {
                let raw = String(data: data, encoding: .utf8) ?? ""
                return .failure(.aiParsingFailed(rawResponse:raw))
            }

            let ids: [String] = modelsArray.compactMap { $0["id"] as? String }
                .sorted()
            AIConfig.setAvailableModels(ids)
            return .success(ids)

        } catch {
            return .failure(.networkFailure(error.localizedDescription))
        }
    }

    // MARK: - Recipe JSON parsing

    nonisolated private func parseRecipe(from text: String) -> Result<ScrapingRecipe, NivyBarError> {
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
            return .failure(.aiParsingFailed(rawResponse:text))
        }

        guard
            let nameSelector  = json["restaurantNameSelector"] as? String,
            let rowSelector   = json["mealRowSelector"] as? String,
            let nameInRow     = json["mealNameSelector"] as? String
        else {
            return .failure(.aiParsingFailed(rawResponse:text))
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
