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

    // MARK: - Dependencies

    private let cache           = LocalCacheManager.shared
    private let scraper         = MenuScraper.shared
    private let dynamicScraper  = DynamicMenuScraper.shared
    private var store: UserRestaurantStore?
    private var cancellables    = Set<AnyCancellable>()

    // MARK: - Store injection (called from App after both objects exist)

    func attach(store: UserRestaurantStore) {
        self.store = store

        // Re-scrape the affected restaurant when a recipe is updated
        store.didUpdateRecipe
            .sink { [weak self] id in
                Task { await self?.refreshDynamic(onlyID: id) }
            }
            .store(in: &cancellables)

        // Sync menus when restaurants are deleted or reordered
        store.didChangeRestaurants
            .sink { [weak self] in
                self?.syncWithStore()
            }
            .store(in: &cancellables)
    }

    // MARK: - Load from cache
    // Returns true when a fresh scrape is needed.

    @discardableResult
    private func loadFromCache() -> Bool {
        guard let cached = cache.load() else { return true }
        menus = filterStaleMenus(cached.menus)
        lastUpdated = cached.savedAt ?? Date()
        return cached.date != cache.todayString
    }

    // Remove user restaurants that no longer exist in the store.
    private func filterStaleMenus(_ menus: [RestaurantMenu]) -> [RestaurantMenu] {
        guard let store else { return menus }
        let userURLs = Set(store.restaurants.map(\.url))
        return menus.filter { menu in
            // Hardcoded menus are always kept
            if menu.displayOrder < 0 { return true }
            // User menus are kept only if their URL is still in the store
            return userURLs.contains(menu.url)
        }
    }

    // MARK: - On appear: load cache then conditionally refresh

    func onAppear() async {
        let needsRefresh = loadFromCache()
        if needsRefresh {
            await refresh()
        }
    }

    // MARK: - Full refresh (hardcoded + all user restaurants)

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        let userRestaurants = store?.restaurants ?? []

        async let hardcodedResults = scraper.scrapeAll()
        async let dynamicResults   = dynamicScraper.scrapeAll(restaurants: userRestaurants)

        let (hardcoded, dynamic) = await (hardcodedResults, dynamicResults)

        // Assign stable negative display orders to hardcoded restaurants
        let hardcodedMenus = hardcoded.enumerated().map { idx, menu in
            RestaurantMenu(
                restaurantName: menu.restaurantName,
                zone: menu.zone,
                url: menu.url,
                unifiedPrice: menu.unifiedPrice,
                items: menu.items,
                error: menu.error,
                accentColorHex: nil,
                displayOrder: -(hardcoded.count - idx)  // -3, -2, -1
            )
        }

        // Update scrape status on the store
        for pair in dynamic {
            if let err = pair.menu.error {
                store?.markScrapeError(err, for: pair.id)
            } else {
                store?.markScrapeSuccess(for: pair.id)
            }
        }

        let dynamicMenus = dynamic.map(\.menu)
        menus = merge(hardcoded: hardcodedMenus, dynamic: dynamicMenus)
        lastUpdated = Date()
        cache.save(menus: menus)
        isLoading = false
    }

    // MARK: - Targeted refresh for a single user restaurant

    private func refreshDynamic(onlyID id: UUID) async {
        guard let store,
              let restaurant = store.restaurants.first(where: { $0.id == id }) else { return }

        let pair = await (id: id, menu: dynamicScraper.scrape(restaurant: restaurant))

        if let err = pair.menu.error {
            store.markScrapeError(err, for: pair.id)
        } else {
            store.markScrapeSuccess(for: pair.id)
        }

        // Splice updated menu into existing list
        if let idx = menus.firstIndex(where: { $0.url == restaurant.url }) {
            menus[idx] = pair.menu
        } else {
            menus = merge(
                hardcoded: menus.filter { $0.displayOrder < 0 },
                dynamic: menus.filter { $0.displayOrder >= 0 } + [pair.menu]
            )
        }
        cache.save(menus: menus)
    }

    // MARK: - Merge + sort

    private func merge(hardcoded: [RestaurantMenu], dynamic: [RestaurantMenu]) -> [RestaurantMenu] {
        // Hardcoded always first (negative displayOrder), then user restaurants sorted by displayOrder
        let sortedDynamic = dynamic.sorted { $0.displayOrder < $1.displayOrder }
        return hardcoded + sortedDynamic
    }

    // MARK: - Sync with store after delete/reorder

    private func syncWithStore() {
        guard let store else { return }

        let userURLs = Set(store.restaurants.map(\.url))
        var updated: [RestaurantMenu] = []

        for menu in menus {
            if menu.displayOrder < 0 {
                updated.append(menu)
            } else if let restaurant = store.restaurants.first(where: { $0.url == menu.url }) {
                var refreshed = menu
                refreshed.displayOrder = restaurant.displayOrder
                updated.append(refreshed)
            }
            // deleted restaurants are dropped
        }

        menus = merge(hardcoded: updated.filter { $0.displayOrder < 0 },
                      dynamic: updated.filter { $0.displayOrder >= 0 })
        cache.save(menus: menus)
    }

    // MARK: - Computed

    func reset() {
        menus = []
        lastUpdated = nil
        isLoading = false
        errorMessage = nil
        cache.clear()
    }

    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.locale = Locale(identifier: Configuration.System.skLocale)
        return fmt
    }()

    private static let fullFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        fmt.locale = Locale(identifier: Configuration.System.skLocale)
        return fmt
    }()

    var lastUpdatedLabel: String {
        guard let date = lastUpdated else { return "Nikdy" }
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "Dnes o \(Self.timeFormatter.string(from: date))"
        } else {
            return Self.fullFormatter.string(from: date)
        }
    }

    var userRestaurantCount: Int {
        store?.restaurants.count ?? 0
    }

}
