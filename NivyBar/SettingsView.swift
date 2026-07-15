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
        LocalCacheManager.shared.clear()
        store.clearAll()
        vm.reset()
        AIConfig.resetAll()
        AIRateLimiter.shared.reset()

        baseURL = AIConfig.defaultBaseURL
        apiKey = ""
        selectedModel = customModelTag
        customModel = ""
        availableModels = []
        dailyLimit = "20"
    }
}
