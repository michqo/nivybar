//
//  MenuViewModel.swift
//  NivyBar
//

import SwiftUI
import Combine

@MainActor
final class MenuViewModel: ObservableObject {

    // MARK: - Published state

    @Published var menus: [RestaurantMenu] = []
    @Published var isLoading: Bool = false
    @Published var lastUpdated: Date? = nil
    @Published var errorMessage: String? = nil

    // MARK: - Private

    private let cache = LocalCacheManager.shared
    private let scraper = MenuScraper.shared

    // MARK: - Load from cache
    // Returns true when a fresh scrape is needed.

    @discardableResult
    private func loadFromCache() -> Bool {
        guard let cached = cache.load() else { return true }
        menus = cached.menus
        lastUpdated = dateFromCacheString(cached.date)
        // Stale if the cached date string doesn't match today
        return cached.date != cache.todayString
    }

    // MARK: - On appear: load cache then conditionally refresh

    func onAppear() async {
        let needsRefresh = loadFromCache()
        if needsRefresh {
            await refresh()
        }
    }

    // MARK: - Manual / forced refresh

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        let results = await scraper.scrapeAll()

        menus = results
        lastUpdated = Date()
        cache.save(menus: results)
        isLoading = false
    }

    // MARK: - Computed

    var lastUpdatedLabel: String {
        guard let date = lastUpdated else { return "Nikdy" }
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            fmt.locale = Locale(identifier: "sk_SK")
            return "Dnes o \(fmt.string(from: date))"
        } else {
            let fmt = DateFormatter()
            fmt.dateStyle = .short
            fmt.timeStyle = .short
            fmt.locale = Locale(identifier: "sk_SK")
            return fmt.string(from: date)
        }
    }

    // MARK: - Helpers

    private func dateFromCacheString(_ string: String) -> Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "sk_SK")
        return fmt.date(from: string)
    }
}
