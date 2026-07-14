//
//  SettingsView.swift
//  NivyBar
//

import SwiftUI

// MARK: - SettingsView (NavigationSplitView root)

struct SettingsView: View {
    @EnvironmentObject private var store: UserRestaurantStore
    @State private var selectedID: UUID? = nil
    @State private var showAddSheet = false
    @State private var showAIConfig = false

    var body: some View {
        NavigationSplitView {
            // MARK: Left panel — restaurant list + AI Settings
            List(selection: $selectedID) {
                ForEach(store.restaurants) { restaurant in
                    RestaurantListRow(restaurant: restaurant)
                        .tag(restaurant.id)
                        .contextMenu {
                            Button {
                                store.delete(restaurant)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { offsets in
                    offsets.forEach { store.delete(store.restaurants[$0]) }
                }

                Section {
                    Button {
                        selectedID = nil
                        showAIConfig = true
                    } label: {
                        Label("AI Settings", systemImage: "gearshape")
                            .foregroundStyle(showAIConfig ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Restaurants")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add restaurant")
                }

            }
            .sheet(isPresented: $showAddSheet) {
                AddRestaurantSheet(onAdded: { newID in
                    showAIConfig = false
                    selectedID = newID
                })
                .environmentObject(store)
            }
            .onChange(of: selectedID) { _, newID in
                if newID != nil { showAIConfig = false }
            }
        } detail: {
            if showAIConfig {
                AIConfigView()
            } else if let id = selectedID,
               let idx = store.restaurants.firstIndex(where: { $0.id == id }) {
                RestaurantDetailView(restaurant: $store.restaurants[idx])
                    .id(id) // force view refresh when selection changes
                    .environmentObject(store)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "fork.knife.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Select a restaurant")
                        .foregroundStyle(.secondary)
                    Text("or press + to add one")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

// MARK: - List row

private struct RestaurantListRow: View {
    let restaurant: UserRestaurant

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: restaurant.accentColorHex))
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(restaurant.effectiveName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let zone = restaurant.zone, !zone.isEmpty {
                    Text(zone)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            RecipeStatusBadge(status: restaurant.recipeStatus)
            if restaurant.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .imageScale(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

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

// MARK: - Restaurant detail + recipe editor

struct RestaurantDetailView: View {
    @Binding var restaurant: UserRestaurant
    @EnvironmentObject private var store: UserRestaurantStore

    @State private var isAnalyzing = false
    @State private var aiError: AIError? = nil
    @State private var showRawAIResponse = false
    @State private var showReanalyzeConfirm = false
    @State private var showTesterSheet = false

    var body: some View {
        Form {
            // MARK: Section 1 — Basic info
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

            // MARK: Section 2 — Scraping recipe
            Section {
                // Status indicator
                HStack {
                    RecipeStatusBadge(status: restaurant.recipeStatus)
                    if let scrapedAt = restaurant.lastScrapedAt {
                        Text("Last scraped: \(scrapedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.bottom, 4)

                if var recipe = restaurant.recipe {
                    RecipeEditorView(recipe: Binding(
                        get: { restaurant.recipe ?? ScrapingRecipe(restaurantNameSelector: "", mealRowSelector: "", mealNameSelector: "") },
                        set: { newRecipe in
                            restaurant.recipe = newRecipe
                            store.markDirty()
                        }
                    ))
                    .onAppear { _ = recipe } // suppress warning
                } else {
                    Text("No recipe yet — use 'Analyze with AI' below.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } header: {
                Text("Scraping Recipe")
            }

            // MARK: Section 3 — AI actions
            Section("AI Actions") {
                HStack(spacing: 10) {
                    // Analyze / Re-analyze
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

                    // Test selectors
                    if restaurant.recipe != nil {
                        Button {
                            showTesterSheet = true
                        } label: {
                            Label("Test Selectors", systemImage: "play.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Rate limit indicator
                let usage = AIRateLimiter.shared.currentUsage
                Text("AI calls today: \(usage.used) / \(usage.limit)")
                    .font(.caption)
                    .foregroundStyle(usage.used >= usage.limit ? .red : .secondary)

                // Error / raw AI response disclosure
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
                .environmentObject(store)
        }
    }

    // MARK: - AI analysis

    private func runAnalysis() async {
        isAnalyzing = true
        aiError = nil

        let result = await AIRecipeGenerator.shared.generateRecipe(for: restaurant.url)
        switch result {
        case .success(let recipe):
            store.updateRecipe(recipe, for: restaurant.id)
            // Reflect back into binding — store.restaurants is the source of truth
            if let updated = store.restaurants.first(where: { $0.id == restaurant.id }) {
                restaurant = updated
        }
        case .failure(let err):
            aiError = err
        }

        isAnalyzing = false
    }
}

// MARK: - Recipe editor sub-view

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

// MARK: - AI Configuration view

struct AIConfigView: View {

    @EnvironmentObject private var store: UserRestaurantStore
    @EnvironmentObject private var vm: MenuViewModel

    @State private var baseURL: String    = AIConfig.baseURL ?? AIConfig.defaultBaseURL
    @State private var apiKey: String     = UserDefaults.standard.string(forKey: AIConfig.apiKeyKey) ?? ""
    @State private var dailyLimit: String = UserDefaults.standard.integer(forKey: AIConfig.dailyLimitKey) > 0
        ? String(UserDefaults.standard.integer(forKey: AIConfig.dailyLimitKey))
        : "20"
    @State private var showKey: Bool      = false

    @State private var availableModels: [String] = AIConfig.availableModels
    @State private var selectedModel: String     = ""
    @State private var customModel: String        = ""
    @State private var isLoadingModels: Bool      = false
    @State private var modelError: String?        = nil

    @State private var showResetConfirm = false

    private let customModelTag = "__custom__"

    private var envBaseURL: String? { ProcessInfo.processInfo.environment["OPENAI_BASE_URL"] }
    private var envModel: String?   { ProcessInfo.processInfo.environment["OPENAI_MODEL"] }

    init() {
        let saved = UserDefaults.standard.string(forKey: AIConfig.modelKey) ?? ""
        let cached = AIConfig.availableModels
        if !saved.isEmpty && cached.contains(saved) {
            _selectedModel = State(initialValue: saved)
            _customModel = State(initialValue: "")
        } else {
            _selectedModel = State(initialValue: customModelTag)
            _customModel = State(initialValue: saved)
        }
    }

    var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("Base URL") {
                    TextField("", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: baseURL) { _, v in
                            if v.isEmpty {
                                baseURL = AIConfig.defaultBaseURL
                                UserDefaults.standard.set(AIConfig.defaultBaseURL, forKey: AIConfig.baseURLKey)
                            } else {
                                save(key: AIConfig.baseURLKey, value: v)
                            }
                        }
                }
                LabeledContent("API Key") {
                    Group {
                        if showKey {
                            TextField("", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .onChange(of: apiKey) { _, v in save(key: AIConfig.apiKeyKey, value: v) }
                    Toggle("Show key", isOn: $showKey)
                        .font(.caption)
                        .labelsHidden()
                }
                LabeledContent("Model") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Picker("", selection: $selectedModel) {
                                ForEach(availableModels, id: \.self) { id in
                                    Text(id).tag(id)
                                }
                                Text("Custom...").tag(customModelTag)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(minWidth: 220)
                            .onChange(of: selectedModel) { _, newValue in
                                if newValue == customModelTag {
                                    save(key: AIConfig.modelKey, value: customModel)
                                } else {
                                    save(key: AIConfig.modelKey, value: newValue)
                                }
                            }

                            Button {
                                Task { await refreshModels() }
                            } label: {
                                if isLoadingModels {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(isLoadingModels || !AIConfig.isConfigured)
                            .help("Refresh available models from the server")
                        }

                        if selectedModel == customModelTag {
                            TextField("", text: $customModel)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: customModel) { _, v in
                                    save(key: AIConfig.modelKey, value: v)
                                }
                        }

                        if let error = modelError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if availableModels.isEmpty {
                            Text("No models loaded. Tap refresh to fetch available models.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Section("Rate Limiting") {
                LabeledContent("Daily AI call limit") {
                    TextField("", text: $dailyLimit)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onChange(of: dailyLimit) { _, v in
                            let n = Int(v) ?? 20
                            UserDefaults.standard.set(max(1, n), forKey: AIConfig.dailyLimitKey)
                        }
                }
                let usage = AIRateLimiter.shared.currentUsage
                Text("Calls today: \(usage.used) / \(usage.limit)")
                    .font(.caption)
                    .foregroundStyle(usage.used >= usage.limit ? .red : .secondary)
            }

            Section("Status") {
                HStack(spacing: 8) {
                    Circle()
                        .fill(AIConfig.isConfigured ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(AIConfig.isConfigured ? "Configured" : "Not configured — enter Base URL and API Key above")
                        .font(.callout)
                        .foregroundStyle(AIConfig.isConfigured ? Color.secondary : Color.orange)
                }

                if let env = envBaseURL, baseURL.isEmpty {
                    Label(
                        "Env var OPENAI_BASE_URL is set (\(env)) and will be used unless overridden here.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
                if let env = envModel, AIConfig.model == nil {
                    Label(
                        "Env var OPENAI_MODEL is set (\(env)) and will be used unless overridden here.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }

            Section {
                Text("Values are stored in UserDefaults and take priority over environment variables. Environment vars can still be used if these fields are left blank.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("Reset Everything", systemImage: "trash")
                }
                .confirmationDialog(
                    "This will wipe all saved restaurants, cached menus, AI configuration, and rate limit data. This action cannot be undone.",
                    isPresented: $showResetConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Reset Everything", role: .destructive) {
                        resetEverything()
                    }
                    Button("Cancel", role: .cancel) {}
                }

                Text("Clears all local data: restaurants, menu cache, and AI settings.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI Settings")
        .task {
            if availableModels.isEmpty && AIConfig.isConfigured {
                await refreshModels()
            }
        }
    }

    private func save(key: String, value: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func refreshModels() async {
        isLoadingModels = true
        modelError = nil

        let result = await AIRecipeGenerator.shared.fetchAvailableModels()
        switch result {
        case .success(let ids):
            availableModels = ids
            let saved = UserDefaults.standard.string(forKey: AIConfig.modelKey) ?? ""
            if !saved.isEmpty {
                if ids.contains(saved) {
                    selectedModel = saved
                } else {
                    selectedModel = customModelTag
                    customModel = saved
                }
            } else if let first = ids.first {
                selectedModel = first
                save(key: AIConfig.modelKey, value: first)
            }
        case .failure(let err):
            modelError = err.errorDescription
        }

        isLoadingModels = false
    }

    private func resetEverything() {
        // Clear cache
        LocalCacheManager.shared.clear()

        // Clear user restaurants
        store.clearAll()

        // Clear menus from view model
        vm.menus = []
        vm.lastUpdated = nil

        // Clear AI UserDefaults
        let aiKeys = [
            AIConfig.baseURLKey, AIConfig.apiKeyKey, AIConfig.modelKey,
            AIConfig.dailyLimitKey, AIConfig.availableModelsKey, AIConfig.availableModelsFetchedAtKey,
            "AIRateLimiter.count", "AIRateLimiter.date"
        ]
        for key in aiKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        // Reset local state to defaults
        baseURL = AIConfig.defaultBaseURL
        apiKey = ""
        selectedModel = customModelTag
        customModel = ""
        availableModels = []
        dailyLimit = "20"
    }
}
