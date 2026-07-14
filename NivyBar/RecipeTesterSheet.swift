//
//  RecipeTesterSheet.swift
//  NivyBar
//

import SwiftUI

struct RecipeTesterSheet: View {
    let restaurant: UserRestaurant
    @EnvironmentObject private var store: UserRestaurantStore
    @Environment(\.dismiss) private var dismiss

    @State private var isRunning = false
    @State private var result: RestaurantMenu? = nil
    @State private var rawHTMLSnippet: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Test Selectors — \(restaurant.effectiveName)")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isRunning {
                        HStack {
                            ProgressView()
                            Text("Scraping with current selectors…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)

                    } else if let menu = result {
                        if menu.hasError {
                            // Error state
                            VStack(alignment: .leading, spacing: 10) {
                                Label(menu.error ?? "Unknown error", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                                if let snippet = rawHTMLSnippet {
                                    DisclosureGroup("Debug: raw HTML snippet (first 2000 chars)") {
                                        ScrollView {
                                            Text(snippet)
                                                .font(.system(.caption, design: .monospaced))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .textSelection(.enabled)
                                        }
                                        .frame(maxHeight: 200)
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        } else {
                            // Success — show parsed result
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Selectors working correctly", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.callout)

                                if let soup = menu.soup {
                                    GroupBox("Soup of the day") {
                                        Text(soup.name)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }

                                GroupBox("Dishes (\(menu.dishes.count) found)") {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(Array(menu.dishes.enumerated()), id: \.offset) { idx, dish in
                                            HStack {
                                                Text("\(idx + 1). \(dish.name)")
                                                    .lineLimit(2)
                                                Spacer()
                                                if let price = dish.price {
                                                    Text(price)
                                                        .foregroundStyle(.secondary)
                                                        .font(.system(size: 12))
                                                }
                                            }
                                            if idx < menu.dishes.count - 1 {
                                                Divider()
                                            }
                                        }
                                    }
                                }

                                if menu.dishes.isEmpty {
                                    Label("No dishes found — check mealRowSelector and mealNameSelector.", systemImage: "exclamationmark.triangle")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    } else {
                        Text("Press Run to test your selectors.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button {
                    Task { await runTest() }
                } label: {
                    Label(isRunning ? "Running…" : "Run Test", systemImage: "play.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 460)
        .task { await runTest() }     // auto-run on open
    }

    // MARK: - Run test

    private func runTest() async {
        isRunning = true
        rawHTMLSnippet = nil

        let menu = await DynamicMenuScraper.shared.scrape(restaurant: restaurant)
        result = menu

        // If no results, try to fetch raw HTML for debug snippet
        if menu.hasError || menu.dishes.isEmpty {
            if let url = URL(string: restaurant.url),
               let (data, _) = try? await URLSession.shared.data(from: url),
               let html = String(data: data, encoding: .utf8) {
                rawHTMLSnippet = String(html.prefix(2000))
            }
        }

        isRunning = false
    }
}
