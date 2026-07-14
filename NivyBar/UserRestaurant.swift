//
//  UserRestaurant.swift
//  NivyBar
//

import Foundation
import SwiftUI

// MARK: - ScrapingRecipe

struct ScrapingRecipe: Codable, Sendable {
    var restaurantNameSelector: String
    var soupSelector: String?
    var mealRowSelector: String
    var mealNameSelector: String
    var mealPriceSelector: String?
    var notes: String?
    var extractedName: String?
    var extractedLocation: String?
    var usesJavaScript: Bool
    var suggestedColorHex: String?

    init(
        restaurantNameSelector: String,
        soupSelector: String? = nil,
        mealRowSelector: String,
        mealNameSelector: String,
        mealPriceSelector: String? = nil,
        notes: String? = nil,
        extractedName: String? = nil,
        extractedLocation: String? = nil,
        usesJavaScript: Bool = false,
        suggestedColorHex: String? = nil
    ) {
        self.restaurantNameSelector = restaurantNameSelector
        self.soupSelector = soupSelector
        self.mealRowSelector = mealRowSelector
        self.mealNameSelector = mealNameSelector
        self.mealPriceSelector = mealPriceSelector
        self.notes = notes
        self.extractedName = extractedName
        self.extractedLocation = extractedLocation
        self.usesJavaScript = usesJavaScript
        self.suggestedColorHex = suggestedColorHex
    }

    enum CodingKeys: String, CodingKey {
        case restaurantNameSelector, soupSelector, mealRowSelector
        case mealNameSelector, mealPriceSelector, notes
        case extractedName, extractedLocation, usesJavaScript
        case suggestedColorHex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        restaurantNameSelector = try c.decode(String.self, forKey: .restaurantNameSelector)
        soupSelector           = try c.decodeIfPresent(String.self, forKey: .soupSelector)
        mealRowSelector        = try c.decode(String.self, forKey: .mealRowSelector)
        mealNameSelector       = try c.decode(String.self, forKey: .mealNameSelector)
        mealPriceSelector      = try c.decodeIfPresent(String.self, forKey: .mealPriceSelector)
        notes                  = try c.decodeIfPresent(String.self, forKey: .notes)
        extractedName          = try c.decodeIfPresent(String.self, forKey: .extractedName)
        extractedLocation      = try c.decodeIfPresent(String.self, forKey: .extractedLocation)
        usesJavaScript         = try c.decodeIfPresent(Bool.self, forKey: .usesJavaScript) ?? false
        suggestedColorHex      = try c.decodeIfPresent(String.self, forKey: .suggestedColorHex)
    }
}

// MARK: - UserRestaurant

struct UserRestaurant: Codable, Identifiable, Sendable {
    var id: UUID
    var url: String
    var displayName: String
    var zone: String?
    var accentColorHex: String  // User-picked accent color stored as hex string
    var customName: String?     // Optional override for display name
    var displayOrder: Int
    var isFavorite: Bool
    var recipe: ScrapingRecipe? // nil = not yet analyzed
    var lastScrapedAt: Date?
    var lastScrapeError: String? // last known scrape error message

    init(
        id: UUID = UUID(),
        url: String,
        displayName: String,
        zone: String? = nil,
        accentColorHex: String = "#FF6B35",
        customName: String? = nil,
        displayOrder: Int = 0,
        isFavorite: Bool = false,
        recipe: ScrapingRecipe? = nil,
        lastScrapedAt: Date? = nil,
        lastScrapeError: String? = nil
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.zone = zone
        self.accentColorHex = accentColorHex
        self.customName = customName
        self.displayOrder = displayOrder
        self.isFavorite = isFavorite
        self.recipe = recipe
        self.lastScrapedAt = lastScrapedAt
        self.lastScrapeError = lastScrapeError
    }

    var effectiveName: String { customName ?? displayName }

    var recipeStatus: RecipeStatus {
        guard recipe != nil else { return .notAnalyzed }
        if let err = lastScrapeError, !err.isEmpty { return .error }
        return .working
    }

    enum RecipeStatus {
        case notAnalyzed, working, error
    }
}

// MARK: - Color hex extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 6:
            (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
