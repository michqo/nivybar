//
//  Models.swift
//  NivyBar
//

import Foundation

// MARK: - MenuItem

struct MenuItem: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    let name: String
    let price: String?     // nil for soup (free with meal) or when unified price
    let isSoup: Bool

    enum CodingKeys: String, CodingKey {
        case name, price, isSoup
    }

    nonisolated init(name: String, price: String? = nil, isSoup: Bool = false) {
        self.id = UUID()
        self.name = name
        self.price = price
        self.isSoup = isSoup
    }
}

// MARK: - RestaurantMenu

struct RestaurantMenu: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    let restaurantName: String
    let zone: String
    let url: String
    let unifiedPrice: String?   // e.g. Komín shows one price for all dishes
    let items: [MenuItem]
    let error: String?          // non-nil when scraping failed

    enum CodingKeys: String, CodingKey {
        case restaurantName, zone, url, unifiedPrice, items, error
    }

    nonisolated init(
        restaurantName: String,
        zone: String,
        url: String,
        unifiedPrice: String? = nil,
        items: [MenuItem] = [],
        error: String? = nil
    ) {
        self.id = UUID()
        self.restaurantName = restaurantName
        self.zone = zone
        self.url = url
        self.unifiedPrice = unifiedPrice
        self.items = items
        self.error = error
    }

    var hasError: Bool { error != nil }
    var soup: MenuItem? { items.first(where: { $0.isSoup }) }
    var dishes: [MenuItem] { items.filter { !$0.isSoup } }
}

// MARK: - CachedMenuData (root JSON envelope)

struct CachedMenuData: Codable {
    let date: String        // "yyyy-MM-dd" — day the data was scraped
    let menus: [RestaurantMenu]
}

// MARK: - RestaurantConfig (static, not cached)

struct RestaurantConfig: Sendable {
    let name: String
    let zone: String
    let url: String
    let icon: String        // SF Symbol name

    static let all: [RestaurantConfig] = [
        RestaurantConfig(
            name: "Nostalgia Nivy",
            zone: "Paričkova / Dulovo nám.",
            url: "https://www.nostalgianivy.sk/",
            icon: "fork.knife"
        ),
        RestaurantConfig(
            name: "Pivovar Komín",
            zone: "Miletičova (Trhovisko)",
            url: "https://www.pivovarkomin.sk/denne-menu/",
            icon: "mug.fill"
        ),
        RestaurantConfig(
            name: "Dulák Košická",
            zone: "Košická / Dulovo nám.",
            url: "https://restauracie.sme.sk/restauracia/dulak-kosicka_11298-ruzinov_2980/denne-menu",
            icon: "fork.knife.circle"
        )
    ]
}
