//
//  DynamicMenuScraper.swift
//  NivyBar
//

import Foundation
import SwiftSoup

final class DynamicMenuScraper: @unchecked Sendable {

    static let shared = DynamicMenuScraper()

    private let fetcher: HTMLFetching

    init(fetcher: HTMLFetching = HTMLFetcher()) {
        self.fetcher = fetcher
    }

    // MARK: - Scrape all user restaurants concurrently

    /// Scrapes all user restaurants that have a recipe.
    /// Returns one RestaurantMenu per restaurant (with embedded error if scraping fails).
    /// The restaurantIDs parameter is an in-out map updated with error/success state.
    nonisolated func scrapeAll(
        restaurants: [UserRestaurant]
    ) async -> [(id: UUID, menu: RestaurantMenu)] {
        let withRecipe = restaurants.filter { $0.recipe != nil }
        guard !withRecipe.isEmpty else { return [] }

        return await withTaskGroup(of: (UUID, RestaurantMenu).self) { group in
            for restaurant in withRecipe {
                group.addTask {
                    let menu = await self.scrape(restaurant: restaurant)
                    return (restaurant.id, menu)
                }
            }
            var results: [(UUID, RestaurantMenu)] = []
            for await pair in group {
                results.append(pair)
            }
            // Restore displayOrder from source
            return results.map { (id: $0.0, menu: $0.1) }
        }
    }

    /// Scrape a single user restaurant using its saved recipe.
    /// Used by "Test Selectors" in SettingsView.
    nonisolated func scrape(restaurant: UserRestaurant) async -> RestaurantMenu {
        guard let recipe = restaurant.recipe else {
            return makeError(restaurant, "No scraping recipe configured.")
        }

        do {
            let html: String
            if recipe.usesJavaScript {
                html = try await self.fetcher.fetchViaJina(urlString: restaurant.url)
            } else {
                html = try await self.fetcher.fetch(urlString: restaurant.url)
            }
            let doc  = try SwiftSoup.parse(html)

            var items: [MenuItem] = []

            // Soup
            if let soupSel = recipe.soupSelector, !soupSel.isEmpty,
               let soupEl = try doc.select(soupSel).first() {
                let soupText = try soupEl.text().trimmingCharacters(in: .whitespacesAndNewlines)
                if !soupText.isEmpty {
                    items.append(MenuItem(name: soupText, price: nil, isSoup: true))
                }
            }

            // Meal rows
            let rows = try doc.select(recipe.mealRowSelector)
            for row in rows {
                // Name within row
                let nameEl: Element?
                if recipe.mealNameSelector.hasPrefix(recipe.mealRowSelector) ||
                   recipe.mealNameSelector == recipe.mealRowSelector {
                    // Selector is the same as row — use the row itself
                    nameEl = row
                } else {
                    nameEl = try row.select(recipe.mealNameSelector).first()
                        ?? (try? doc.select(recipe.mealNameSelector).first())
                }

                guard let el = nameEl else { continue }
                let name = try el.text().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }

                // Price within row
                var price: String? = nil
                if let priceSel = recipe.mealPriceSelector, !priceSel.isEmpty {
                    if let priceEl = try? row.select(priceSel).first()
                        ?? doc.select(priceSel).first() {
                        let raw = try priceEl.text().trimmingCharacters(in: .whitespaces)
                        if !raw.isEmpty {
                            price = raw.replacingOccurrences(
                                of: #"(\d)\.(\d)"#,
                                with: "$1,$2",
                                options: .regularExpression
                            )
                        }
                    }
                }

                items.append(MenuItem(name: name, price: price, isSoup: false))
            }

            if items.isEmpty {
                return makeError(restaurant, "Selectors returned no results. Check the recipe.")
            }

            // Last-resort: if we got soup but no main dishes, the page may be a JS SPA.
            // Retry with Jina only if we did not already use Jina for this fetch.
            let dishCount = items.filter { !$0.isSoup }.count
            if dishCount == 0 && !recipe.usesJavaScript {
                let jinaHTML = try? await self.fetcher.fetchViaJina(urlString: restaurant.url)
                if let jinaHTML, let jinaDoc = try? SwiftSoup.parse(jinaHTML) {
                    var jinaItems: [MenuItem] = items  // keep the soup we already found
                    if let soupSel = recipe.soupSelector, !soupSel.isEmpty,
                       let soupEl = try jinaDoc.select(soupSel).first(),
                       jinaItems.first(where: { $0.isSoup }) == nil {
                        let soupText = try soupEl.text().trimmingCharacters(in: .whitespacesAndNewlines)
                        if !soupText.isEmpty {
                            jinaItems.insert(MenuItem(name: soupText, price: nil, isSoup: true), at: 0)
                        }
                    }
                    let jinaRows = try jinaDoc.select(recipe.mealRowSelector)
                    for row in jinaRows {
                        let nameEl: Element?
                        if recipe.mealNameSelector.hasPrefix(recipe.mealRowSelector) ||
                           recipe.mealNameSelector == recipe.mealRowSelector {
                            nameEl = row
                        } else {
                            nameEl = try row.select(recipe.mealNameSelector).first()
                                ?? (try? jinaDoc.select(recipe.mealNameSelector).first())
                        }
                        guard let el = nameEl else { continue }
                        let name = try el.text().trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { continue }
                        var price: String? = nil
                        if let priceSel = recipe.mealPriceSelector, !priceSel.isEmpty {
                            if let priceEl = try? row.select(priceSel).first()
                                ?? jinaDoc.select(priceSel).first() {
                                let raw = try priceEl.text().trimmingCharacters(in: .whitespaces)
                                if !raw.isEmpty {
                                    price = raw.replacingOccurrences(
                                        of: #"(\d)\.(\d)"#,
                                        with: "$1,$2",
                                        options: .regularExpression
                                    )
                                }
                            }
                        }
                        jinaItems.append(MenuItem(name: name, price: price, isSoup: false))
                    }
                    let jinaDishCount = jinaItems.filter { !$0.isSoup }.count
                    if jinaDishCount > 0 { items = jinaItems }
                }
            }

            return RestaurantMenu(
                restaurantName: restaurant.effectiveName,
                zone: restaurant.zone ?? "",
                url: restaurant.url,
                items: items,
                accentColorHex: restaurant.accentColorHex,
                displayOrder: restaurant.displayOrder
            )

        } catch {
            return makeError(restaurant, "Scrape failed: \(error.localizedDescription)")
        }
    }

    // MARK: - HTML fetch

    // MARK: - Helper

    nonisolated private func makeError(_ restaurant: UserRestaurant, _ message: String) -> RestaurantMenu {
        RestaurantMenu(
            restaurantName: restaurant.effectiveName,
            zone: restaurant.zone ?? "",
            url: restaurant.url,
            error: message,
            accentColorHex: restaurant.accentColorHex,
            displayOrder: restaurant.displayOrder
        )
    }
}
