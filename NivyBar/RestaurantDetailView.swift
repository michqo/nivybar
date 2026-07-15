//
//  RestaurantDetailView.swift
//  NivyBar
//

import SwiftUI

// MARK: - Recipe status badge

struct RecipeStatusBadge: View {
    let status: UserRestaurant.RecipeStatus

    var body: some View {
        switch status {
        case .notAnalyzed:
            badge("Not analyzed", color: .orange)
        case .working:
            badge("Working", color: .green)
        case .error:
            badge("Selector error", color: .red)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.12))
            )
    }
}

// MARK: - Restaurant detail

struct RestaurantDetailView: View {
    @Binding var restaurant: UserRestaurant
    @EnvironmentObject private var store: UserRestaurantStore

    @State private var isAnalyzing = false
    @State private var aiError: NivyBarError? = nil
    @State private var showRawAIResponse = false
    @State private var showReanalyzeConfirm = false
    @State private var showTesterSheet = false

    var body: some View {
        Form {
            Section("Basic Info") {
                LabeledContent("Name") {
                    TextField("", text: $restaurant.displayName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: restaurant.displayName) { _, _ in store.markDirty() }
                }
                LabeledContent("Zone") {
                    TextField("", text: Binding(
                        get: { restaurant.zone ?? "" },
                        set: { restaurant.zone = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: restaurant.zone) { _, _ in store.markDirty() }
                }
                LabeledContent("URL") {
                    TextField("", text: $restaurant.url)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: restaurant.url) { _, _ in store.markDirty() }
                }
                LabeledContent("Accent color") {
                    Menu {
                        ForEach(accentColorPresets, id: \.hex) { preset in
                            Button {
                                restaurant.accentColorHex = preset.hex
                                store.markDirty()
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(Color(hex: preset.hex))
                                        .frame(width: 14, height: 14)
                                    Text(preset.name)
                                    if restaurant.accentColorHex == preset.hex {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: restaurant.accentColorHex))
                                .frame(width: 14, height: 14)
                            Text(colorName(for: restaurant.accentColorHex))
                        }
                    }
                    .menuStyle(.borderlessButton)
                }
                LabeledContent("Favourite") {
                    Toggle("", isOn: $restaurant.isFavorite)
                        .labelsHidden()
                        .onChange(of: restaurant.isFavorite) { _, _ in store.markDirty() }
                }
            }

            Section {
                HStack {
                    RecipeStatusBadge(status: restaurant.recipeStatus)
                    if let scrapedAt = restaurant.lastScrapedAt {
                        Text("Last scraped: \(scrapedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.bottom, 4)

                if restaurant.recipe != nil {
                    RecipeEditorView(recipe: Binding(
                        get: { restaurant.recipe ?? ScrapingRecipe(restaurantNameSelector: "", mealRowSelector: "", mealNameSelector: "") },
                        set: { newRecipe in
                            restaurant.recipe = newRecipe
                            store.markDirty()
                        }
                    ))
                } else {
                    Text("No recipe yet — use 'Analyze with AI' below.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } header: {
                Text("Scraping Recipe")
            }

            Section("AI Actions") {
                HStack(spacing: 10) {
                    if restaurant.recipe == nil {
                        Button {
                            Task { await runAnalysis() }
                        } label: {
                            Label(isAnalyzing ? "Analyzing…" : "Analyze with AI", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isAnalyzing || restaurant.url.isEmpty)
                    } else {
                        Button {
                            showReanalyzeConfirm = true
                        } label: {
                            Label("Re-analyze with AI", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isAnalyzing)
                        .confirmationDialog(
                            "Re-analyze will overwrite the current recipe.",
                            isPresented: $showReanalyzeConfirm,
                            titleVisibility: .visible
                        ) {
                            Button("Re-analyze", role: .destructive) {
                                Task { await runAnalysis() }
                            }
                        }
                    }

                    if isAnalyzing {
                        ProgressView().controlSize(.small)
                    }

                    Spacer()

                    if restaurant.recipe != nil {
                        Button {
                            showTesterSheet = true
                        } label: {
                            Label("Test Selectors", systemImage: "play.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                let usage = AIRateLimiter.shared.currentUsage
                Text("AI calls today: \(usage.used) / \(usage.limit)")
                    .font(.caption)
                    .foregroundStyle(usage.used >= usage.limit ? .red : .secondary)

                if let err = aiError {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(err.errorDescription ?? "Unknown error", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.callout)
                        if let raw = err.rawAIResponse {
                            DisclosureGroup("Show raw AI response") {
                                ScrollView {
                                    Text(raw)
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                                .frame(maxHeight: 160)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(restaurant.effectiveName)
        .toolbar {
            ToolbarItem {
                Button {
                    store.delete(restaurant)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete restaurant")
            }
        }
        .sheet(isPresented: $showTesterSheet) {
            RecipeTesterSheet(restaurant: restaurant)
        }
    }

    private func runAnalysis() async {
        isAnalyzing = true
        aiError = nil

        let result = await AIRecipeGenerator.shared.generateRecipe(for: restaurant.url)
        switch result {
        case .success(let recipe):
            store.updateRecipe(recipe, for: restaurant.id)
            if let updated = store.restaurants.first(where: { $0.id == restaurant.id }) {
                restaurant = updated
            }
        case .failure(let err):
            aiError = err
        }

        isAnalyzing = false
    }
}

// MARK: - Recipe editor

private struct RecipeEditorView: View {
    @Binding var recipe: ScrapingRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            selectorField("Restaurant name selector", value: $recipe.restaurantNameSelector)
            selectorField("Soup selector (optional)", value: Binding(
                get: { recipe.soupSelector ?? "" },
                set: { recipe.soupSelector = $0.isEmpty ? nil : $0 }
            ), placeholder: "leave empty if not applicable")
            selectorField("Meal row selector", value: $recipe.mealRowSelector)
            selectorField("Meal name selector (relative to row)", value: $recipe.mealNameSelector)
            selectorField("Meal price selector (optional)", value: Binding(
                get: { recipe.mealPriceSelector ?? "" },
                set: { recipe.mealPriceSelector = $0.isEmpty ? nil : $0 }
            ), placeholder: "leave empty if not applicable")

            if let notes = recipe.notes, !notes.isEmpty {
                Text("AI notes: \(notes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private func selectorField(
        _ label: String,
        value: Binding<String>,
        placeholder: String = "CSS selector"
    ) -> some View {
        LabeledContent(label) {
            TextField(placeholder, text: value)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
    }
}

// MARK: - Accent color presets

private struct AccentColorPreset {
    let name: String
    let hex: String
}

private let accentColorPresets: [AccentColorPreset] = [
    AccentColorPreset(name: "Orange", hex: "#FF6B35"),
    AccentColorPreset(name: "Red",    hex: "#E74C3C"),
    AccentColorPreset(name: "Blue",   hex: "#3498DB"),
    AccentColorPreset(name: "Green",  hex: "#2ECC71"),
    AccentColorPreset(name: "Purple", hex: "#9B59B6"),
    AccentColorPreset(name: "Yellow", hex: "#F1C40F"),
    AccentColorPreset(name: "Teal",   hex: "#1ABC9C"),
    AccentColorPreset(name: "Pink",   hex: "#E91E63"),
]

private func colorName(for hex: String) -> String {
    accentColorPresets.first(where: { $0.hex.caseInsensitiveCompare(hex) == .orderedSame })?.name ?? "Custom"
}
