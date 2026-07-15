//
//  MenuScraper.swift
//  NivyBar
//

import Foundation
import SwiftSoup

// MARK: - MenuScraper

// Explicitly nonisolated so network + SwiftSoup CPU work runs off MainActor,
// even though SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor is set project-wide.
final class MenuScraper: @unchecked Sendable {

    static let shared = MenuScraper()

    private let fetcher: HTMLFetching

    init(fetcher: HTMLFetching = HTMLFetcher()) {
        self.fetcher = fetcher
    }

    // Slovak weekday names (Calendar.weekday: 1=Sun, 2=Mon … 7=Sat)
    private let slovakWeekdays: [Int: String] = [
        2: "pondelok",
        3: "utorok",
        4: "streda",
        5: "stvrtok",   // without diacritic — matches Restaumatic URL IDs
        6: "piatok",
        7: "sobota",
        1: "nedela"
    ]

    // MARK: - Public entry point

    /// Scrape all three restaurants concurrently.
    /// Always returns an array of 3 RestaurantMenus — errors are embedded per item.
    nonisolated func scrapeAll() async -> [RestaurantMenu] {
        // Weekend check — Calendar.current respects system timezone
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        let isWeekend = (weekday == 1 || weekday == 7)

        if isWeekend {
            return RestaurantConfig.all.map { config in
                RestaurantMenu(
                    restaurantName: config.name,
                    zone: config.zone,
                    url: config.url,
                    error: "Cez víkend nie je obedové menu."
                )
            }
        }

        async let nostalgia = scrapeNostalgia()
        async let komin = scrapeKomin()
        async let dulak = scrapeDulak()

        return await [nostalgia, komin, dulak]
    }

    // MARK: - Shared fetch

    // MARK: - 1. Nostalgia Nivy (Restaumatic SPA)
    //
    // The site is a JS SPA; static HTML may or may not contain the rendered menu.
    // We attempt to find the today's section by its ID:
    //   menu-denne-menu-{slovak-weekday}-{dd}-{mm}-{yyyy}
    // e.g. menu-denne-menu-utorok-14-07-2026
    //
    // Selectors (when present in static HTML):
    //   - Section:  div[id="menu-denne-menu-..."]
    //   - Soup:     .m-list--header .m-list__description
    //   - Dishes:   li.m-list__item h4.restaurant-menu__dish-name
    //   - Price:    li.m-list__item button.add-button

    nonisolated private func scrapeNostalgia() async -> RestaurantMenu {
        let config = RestaurantConfig.all[0]

        do {
            let html = try await self.fetcher.fetch(urlString: config.url)
            let doc = try SwiftSoup.parse(html)

            // All daily menu sections are pre-rendered with IDs like:
            //   menu-denne-menu-streda-15-07-2026
            // The site shows current + next 2 weekdays, so today's section
            // may not exist if menus aren't published yet. Strategy:
            //   1. Try today's exact section ID first.
            //   2. Fall back to the first available menuv2-section whose
            //      ID contains today's dd-mm-yyyy date string.
            //   3. Fall back to the very first menuv2-section (nearest day).

            let allSections = try doc.select("div.menuv2-section")

            guard !allSections.isEmpty() else {
                return RestaurantMenu(
                    restaurantName: config.name,
                    zone: config.zone,
                    url: config.url,
                    error: "Menu sa nedá načítať (stránka vyžaduje JavaScript)."
                )
            }

            // Build today's date suffix dd-mm-yyyy for matching
            let calendar = Calendar.current
            let now = Date()
            let day   = calendar.component(.day,   from: now)
            let month = calendar.component(.month,  from: now)
            let year  = calendar.component(.year,   from: now)
            let dateSuffix = String(format: "%02d-%02d-%04d", day, month, year)

            // Try exact today ID first, then date-suffix match. If neither is found,
            // the menu for today is not published yet — do not fall back to another day.
            let todayID = buildNostalgiaMenuSectionID()
            let section: Element
            if let exact = try allSections.first(where: {
                (try? $0.attr("id")) == todayID
            }) {
                section = exact
            } else if let dateMatch = try allSections.first(where: {
                ((try? $0.attr("id")) ?? "").contains(dateSuffix)
            }) {
                section = dateMatch
            } else {
                return RestaurantMenu(
                    restaurantName: config.name,
                    zone: config.zone,
                    url: config.url,
                    error: "Dnešné menu ešte nie je zverejnené."
                )
            }

            var items: [MenuItem] = []

            // Soup of the day
            if let soupDesc = try section.select(".m-list--header .m-list__description").first() {
                var soupText = try soupDesc.text()
                // Strip "Polievka dňa: " prefix if present
                let prefix = "Polievka dňa:"
                if let range = soupText.range(of: prefix, options: .caseInsensitive) {
                    soupText = String(soupText[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
                // Strip trailing allergen info like "/ A: 1,7 /"
                soupText = stripAllergenSuffix(soupText)
                if !soupText.isEmpty {
                    items.append(MenuItem(name: soupText, price: nil, isSoup: true))
                }
            }

            // Main dishes
            let dishItems = try section.select("li.m-list__item")
            for li in dishItems {
                guard let nameEl = try li.select("h4.restaurant-menu__dish-name").first() else { continue }
                var name = try nameEl.text()

                // Remove "+ polievka" suffix (soup is already shown separately)
                name = name.replacingOccurrences(of: "+ polievka", with: "", options: .caseInsensitive)
                name = name.trimmingCharacters(in: .whitespacesAndNewlines)

                // Skip if the "dish" is just the soup listed as an orderable item
                if name.lowercased().contains("polievk") && items.contains(where: { $0.isSoup }) {
                    continue
                }
                if name.isEmpty { continue }

                // Price
                var price: String? = nil
                if let priceEl = try li.select("button.add-button").first() {
                    let rawPrice = try priceEl.text()
                        .trimmingCharacters(in: .whitespaces)
                    if !rawPrice.isEmpty {
                        price = rawPrice
                    }
                }

                items.append(MenuItem(name: name, price: price, isSoup: false))
            }

            if items.isEmpty {
                return RestaurantMenu(
                    restaurantName: config.name,
                    zone: config.zone,
                    url: config.url,
                    error: "Dnešné menu ešte nie je zverejnené."
                )
            }

            return RestaurantMenu(
                restaurantName: config.name,
                zone: config.zone,
                url: config.url,
                items: items
            )

        } catch let e as NivyBarError {
            return RestaurantMenu(
                restaurantName: config.name,
                zone: config.zone,
                url: config.url,
                error: e.errorDescription ?? "Neznáma chyba."
            )
        } catch {
            return RestaurantMenu(
                restaurantName: config.name,
                zone: config.zone,
                url: config.url,
                error: "Sieťová chyba: \(error.localizedDescription)"
            )
        }
    }

    /// Build section ID like: menu-denne-menu-utorok-14-07-2026
    nonisolated private func buildNostalgiaMenuSectionID() -> String {
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let day = calendar.component(.day, from: now)
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)

        let dayName = slovakWeekdays[weekday] ?? "pondelok"
        let dd = String(format: "%02d", day)
        let mm = String(format: "%02d", month)

        return "menu-denne-menu-\(dayName)-\(dd)-\(mm)-\(year)"
    }

    // MARK: - 2. Pivovar Komín (WordPress + Elementor)
    //
    // All content is in Elementor text-editor widgets.
    // Day headings: h2.elementor-heading-title containing date like "Pondelok 13.07.2026"
    // Today is matched by comparing the date part to today's dd.MM.yyyy string.
    //
    // Within the matched section's .elementor-widget-text-editor p:
    //   - Soup:   first <strong> block, text begins with "0,33l" or is labeled "Polievka:"
    //   - Dishes: <strong>1:</strong>, <strong>2:</strong>, <strong>3:</strong>
    //             Dish text follows in <span> or as adjacent text node
    //
    // Unified price: .elementor-widget-icon-box .elementor-icon-box-title (first one)

    nonisolated private func scrapeKomin() async -> RestaurantMenu {
        let config = RestaurantConfig.all[1]

        do {
            let html = try await self.fetcher.fetch(urlString: config.url)
            let doc = try SwiftSoup.parse(html)

            // Unified price from icon boxes
            var unifiedPrice: String? = nil
            if let priceBox = try doc.select(".elementor-widget-icon-box .elementor-icon-box-title span").first() {
                let txt = try priceBox.text()
                // Expect something like "Jednotná cena  8,90 €"
                if let euroRange = txt.range(of: #"\d[\d,.]+\s*€"#, options: .regularExpression) {
                    unifiedPrice = String(txt[euroRange]).trimmingCharacters(in: .whitespaces)
                } else if txt.contains("€") {
                    // Fallback: take the whole text stripped
                    unifiedPrice = txt.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        .last
                }
            }

            // Today's date string in dd.MM.yyyy format (to match heading)
            let todayDateString = buildKominTodayDateString()

            // Find the heading that contains today's date
            let headings = try doc.select("h2.elementor-heading-title")
            var todayHeading: Element? = nil
            for heading in headings {
                let text = try heading.text()
                if text.contains(todayDateString) {
                    todayHeading = heading
                    break
                }
            }

            guard let heading = todayHeading else {
                return RestaurantMenu(
                    restaurantName: config.name,
                    zone: config.zone,
                    url: config.url,
                    unifiedPrice: unifiedPrice,
                    error: "Dnešné menu ešte nie je zverejnené."
                )
            }

            // Walk up to the elementor-column section, then find the text-editor widget
            // The heading is inside .elementor-widget-heading; sibling is .elementor-widget-text-editor
            guard let sectionEl = heading.parents().first(where: {
                (try? $0.hasClass("elementor-column")) ?? false
            }) else {
                return RestaurantMenu(
                    restaurantName: config.name,
                    zone: config.zone,
                    url: config.url,
                    unifiedPrice: unifiedPrice,
                    error: "Nepodarilo sa nájsť sekciu s menu."
                )
            }

            // Get all text-editor widgets in this column
            let textEditors = try sectionEl.select(".elementor-widget-text-editor .elementor-widget-container")
            guard let menuEditor = textEditors.first() else {
                return RestaurantMenu(
                    restaurantName: config.name,
                    zone: config.zone,
                    url: config.url,
                    unifiedPrice: unifiedPrice,
                    error: "Nepodarilo sa nájsť text menu."
                )
            }

            // Parse <p> content
            let paragraphs = try menuEditor.select("p")
            var items: [MenuItem] = []

            for p in paragraphs {
                // Get the raw HTML of the paragraph to walk nodes manually
                let pHtml = try p.html()
                // Parse each node: we're looking for <strong> tags as labels
                let pDoc = try SwiftSoup.parseBodyFragment(pHtml)
                let strongs = try pDoc.select("strong")

                for strong in strongs {
                    let label = try strong.text().trimmingCharacters(in: .whitespaces)

                    // Soup detection: label starts with "0,33l" or "Polievka"
                    if label.lowercased().hasPrefix("0,33l") || label.lowercased().hasPrefix("polievka") {
                        // Text content after "0,33l " is the soup name
                        var soupName = label
                        if let idx = soupName.range(of: "0,33l", options: .caseInsensitive)?.upperBound {
                            soupName = String(soupName[idx...]).trimmingCharacters(in: .whitespaces)
                        } else if let idx = soupName.range(of: "Polievka:", options: .caseInsensitive)?.upperBound {
                            soupName = String(soupName[idx...]).trimmingCharacters(in: .whitespaces)
                        }
                        // Also grab the adjacent span text (dish text is in span.a_GcMg)
                        if let nextSpan = try strong.nextElementSibling(),
                           nextSpan.tagName() == "span" || nextSpan.tagName() == "a" {
                            let spanText = try nextSpan.text().trimmingCharacters(in: .whitespaces)
                            if !spanText.isEmpty { soupName = spanText }
                        }
                        soupName = stripAllergenSuffix(soupName)
                        if !soupName.isEmpty {
                            items.append(MenuItem(name: soupName, price: nil, isSoup: true))
                        }
                        continue
                    }

                    // Dish detection: label is "1:", "2:", "3:" etc.
                    let dishLabelPattern = #"^\d+:$"#
                    let isDishLabel = label.range(of: dishLabelPattern, options: .regularExpression) != nil
                    if isDishLabel {
                        // Dish name: try adjacent span first, then sibling text nodes
                        var dishName = ""
                        if let nextEl = try strong.nextElementSibling() {
                            dishName = try nextEl.text().trimmingCharacters(in: .whitespaces)
                        }
                        // If span didn't have it, extract from parent text after the label.
                        // Anchor the search with a regex so "1:" only matches at a word
                        // boundary and not inside a dish name like "contains 1,3 kg".
                        if dishName.isEmpty {
                            var parentText = try strong.parent()?.text() ?? ""
                            // Match label only when preceded by start or whitespace
                            let anchoredPattern = #"(?:^|\s)"# + NSRegularExpression.escapedPattern(for: label)
                            if let labelRange = parentText.range(of: anchoredPattern, options: .regularExpression) {
                                parentText = String(parentText[labelRange.upperBound...])
                                    .trimmingCharacters(in: .whitespaces)
                                // Trim at the next dish label (e.g. "2:") boundary
                                if let nextLabel = parentText.range(of: #"(?:^|\s)\d+:"#, options: .regularExpression) {
                                    parentText = String(parentText[..<nextLabel.lowerBound])
                                }
                                dishName = parentText.trimmingCharacters(in: .whitespaces)
                            }
                        }
                        dishName = stripAllergenSuffix(dishName)
                        if !dishName.isEmpty {
                            // Unified price — don't attach per-dish price
                            items.append(MenuItem(name: dishName, price: nil, isSoup: false))
                        }
                    }
                }
            }

            if items.isEmpty {
                return RestaurantMenu(
                    restaurantName: config.name,
                    zone: config.zone,
                    url: config.url,
                    unifiedPrice: unifiedPrice,
                    error: "Dnešné menu ešte nie je zverejnené."
                )
            }

            return RestaurantMenu(
                restaurantName: config.name,
                zone: config.zone,
                url: config.url,
                unifiedPrice: unifiedPrice,
                items: items
            )

        } catch let e as NivyBarError {
            return RestaurantMenu(
                restaurantName: config.name,
                zone: config.zone,
                url: config.url,
                error: e.errorDescription ?? "Neznáma chyba."
            )
        } catch {
            return RestaurantMenu(
                restaurantName: config.name,
                zone: config.zone,
                url: config.url,
                error: "Sieťová chyba: \(error.localizedDescription)"
            )
        }
    }

    /// Today's date as dd.MM.yyyy for matching Komín headings.
    nonisolated private func buildKominTodayDateString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "dd.MM.yyyy"
        fmt.locale = Locale(identifier: "sk_SK")
        return fmt.string(from: Date())
    }

    // MARK: - 3. Dulák Košická (restauracie.sme.sk)
    //
    // Cleanest structure of the three.
    //
    // Selectors:
    //   - Today's block:   div.dnesne_menu
    //   - All rows:        div.jedlo_polozka
    //   - Name:            div.left   (text content)
    //   - Price:           span.right b  (absent for soup)
    //   - Soup row:        div.left text starts with "Polievka:"
    //   - Skip label rows: div.left contains only <b> with no numeric prefix

    nonisolated private func scrapeDulak() async -> RestaurantMenu {
        let config = RestaurantConfig.all[2]

        do {
            let html = try await self.fetcher.fetch(urlString: config.url)
            let doc = try SwiftSoup.parse(html)

            guard let todaySection = try doc.select("div.dnesne_menu").first() else {
                return RestaurantMenu(
                    restaurantName: config.name,
                    zone: config.zone,
                    url: config.url,
                    error: "Dnešné menu ešte nie je zverejnené."
                )
            }

            let rows = try todaySection.select("div.jedlo_polozka")
            var items: [MenuItem] = []

            for row in rows {
                guard let leftDiv = try row.select("div.left").first() else { continue }
                let rawText = try leftDiv.text()
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if rawText.isEmpty { continue }

                // Detect soup: starts with "Polievka"
                let isSoup = rawText.lowercased().hasPrefix("polievka")

                // Detect label-only rows (no price, bold, not soup, not numbered)
                // These are announcements like "Stála ponuka na tento týždeň:"
                let hasPrice = (try? row.select("span.right b").first()) != nil
                let isNumbered = rawText.range(of: #"^\d+[.:]"#, options: .regularExpression) != nil

                if !isSoup && !hasPrice && !isNumbered {
                    // It's a label/note row — skip
                    continue
                }

                // Clean the name
                var name = rawText

                // Remove soup prefix "Polievka: " or "Polievka:"
                if isSoup {
                    if let idx = name.range(of: "Polievka:", options: .caseInsensitive)?.upperBound {
                        name = String(name[idx...]).trimmingCharacters(in: .whitespaces)
                    }
                    // Format: "0,25l  Kulajda, zemiaky..." — strip portion size prefix
                    name = stripPortionPrefix(name)
                } else {
                    // Remove "1: " or "1. " prefix from numbered dishes
                    name = name.replacingOccurrences(
                        of: #"^\d+[.:]\s*"#,
                        with: "",
                        options: .regularExpression
                    )
                    // Strip portion size prefix like "350g" or "150g/160g"
                    name = stripPortionPrefix(name)
                }

                name = stripAllergenSuffix(name)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if name.isEmpty { continue }

                // Price
                var price: String? = nil
                if let priceEl = try row.select("span.right b").first() {
                    let rawPrice = try priceEl.text().trimmingCharacters(in: .whitespaces)
                    if !rawPrice.isEmpty {
                        // Normalise decimal separator: "9.00 €" → "9,00 €"
                        // Replace dots only when surrounded by digits, not all dots.
                        price = rawPrice.replacingOccurrences(
                            of: #"(\d)\.(\d)"#,
                            with: "$1,$2",
                            options: .regularExpression
                        )
                    }
                }

                items.append(MenuItem(name: name, price: price, isSoup: isSoup))
            }

            if items.isEmpty {
                return RestaurantMenu(
                    restaurantName: config.name,
                    zone: config.zone,
                    url: config.url,
                    error: "Dnešné menu ešte nie je zverejnené."
                )
            }

            return RestaurantMenu(
                restaurantName: config.name,
                zone: config.zone,
                url: config.url,
                items: items
            )

        } catch let e as NivyBarError {
            return RestaurantMenu(
                restaurantName: config.name,
                zone: config.zone,
                url: config.url,
                error: e.errorDescription ?? "Neznáma chyba."
            )
        } catch {
            return RestaurantMenu(
                restaurantName: config.name,
                zone: config.zone,
                url: config.url,
                error: "Sieťová chyba: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Text cleaning helpers

    /// Strip trailing allergen codes like "(1,3,7)" or "/ A: 1,7 /" from dish names.
    nonisolated private func stripAllergenSuffix(_ text: String) -> String {
        var result = text
        // Strip " / A: 1,7 /" style (Nostalgia)
        result = result.replacingOccurrences(
            of: #"\s*/\s*[Aa]:\s*[\d,\s]+/.*$"#,
            with: "",
            options: .regularExpression
        )
        // Strip "(1,3,7)" style allergen codes at end
        result = result.replacingOccurrences(
            of: #"\s*\([\d,\s]+\)\s*$"#,
            with: "",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strip leading portion-size prefixes like "0,25l", "350g", "150g/160g".
    nonisolated private func stripPortionPrefix(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"^\s*[\d][,.\d]*(g|ml|l|dcl|kg|G|ML|L|DCL|KG)(\/[\d][,.\d]*(g|ml|l|dcl|kg|G|ML|L|DCL|KG))?\s+"#,
            with: "",
            options: .regularExpression
        )
    }
}
