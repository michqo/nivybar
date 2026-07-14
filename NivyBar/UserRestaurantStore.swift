//
//  UserRestaurantStore.swift
//  NivyBar
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class UserRestaurantStore: ObservableObject {

    @Published var restaurants: [UserRestaurant] = []

    // Fired by MenuViewModel when it wants to re-scrape after recipe changes
    let didUpdateRecipe = PassthroughSubject<UUID, Never>()

    // Fired when restaurants are added, deleted, or reordered
    let didChangeRestaurants = PassthroughSubject<Void, Never>()

    private var saveTask: Task<Void, Never>?
    private let dirtySubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Paths

    private var storeDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("NivyBar", isDirectory: true)
    }

    private var storeFileURL: URL {
        storeDirectory.appendingPathComponent("user_restaurants.json")
    }

    // MARK: - Init

    init() {
        load()
        setupDebouncedSave()
    }

    // MARK: - Debounced save

    private func setupDebouncedSave() {
        dirtySubject
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] in self?.persistNow() }
            .store(in: &cancellables)
    }

    func markDirty() {
        dirtySubject.send()
    }

    // MARK: - Load

    private func load() {
        guard FileManager.default.fileExists(atPath: storeFileURL.path),
              let data = try? Data(contentsOf: storeFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let loaded = try decoder.decode([UserRestaurant].self, from: data)
            restaurants = loaded.sorted { $0.displayOrder < $1.displayOrder }
        } catch {
            print("UserRestaurantStore failed to decode \(storeFileURL.path): \(error)")
        }
    }

    // MARK: - Save

    func persistNow() {
        do {
            try FileManager.default.createDirectory(
                at: storeDirectory,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(restaurants)
            try data.write(to: storeFileURL, options: .atomic)
        } catch {
            print("UserRestaurantStore save error: \(error)")
        }
    }

    // MARK: - CRUD

    func add(_ restaurant: UserRestaurant) {
        var r = restaurant
        r.displayOrder = (restaurants.map(\.displayOrder).max() ?? -1) + 1
        restaurants.append(r)
        markDirty()
    }

    func update(_ restaurant: UserRestaurant) {
        guard let idx = restaurants.firstIndex(where: { $0.id == restaurant.id }) else { return }
        restaurants[idx] = restaurant
        markDirty()
    }

    func delete(_ restaurant: UserRestaurant) {
        restaurants.removeAll { $0.id == restaurant.id }
        reorderAll()
        markDirty()
        didChangeRestaurants.send()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        restaurants.move(fromOffsets: source, toOffset: destination)
        reorderAll()
        markDirty()
        didChangeRestaurants.send()
    }

    // MARK: - Recipe helpers

    func updateRecipe(_ recipe: ScrapingRecipe, for id: UUID) {
        guard let idx = restaurants.firstIndex(where: { $0.id == id }) else { return }
        restaurants[idx].recipe = recipe
        restaurants[idx].lastScrapeError = nil
        markDirty()
        didUpdateRecipe.send(id)
    }

    func markScrapeError(_ error: String, for id: UUID) {
        guard let idx = restaurants.firstIndex(where: { $0.id == id }) else { return }
        restaurants[idx].lastScrapeError = error
        restaurants[idx].lastScrapedAt = Date()
        markDirty()
    }

    func markScrapeSuccess(for id: UUID) {
        guard let idx = restaurants.firstIndex(where: { $0.id == id }) else { return }
        restaurants[idx].lastScrapeError = nil
        restaurants[idx].lastScrapedAt = Date()
        markDirty()
    }

    // MARK: - Clear all

    func clearAll() {
        saveTask?.cancel()
        saveTask = nil
        restaurants.removeAll()
        try? FileManager.default.removeItem(at: storeFileURL)
        didChangeRestaurants.send()
    }

    // MARK: - Helpers

    private func reorderAll() {
        for i in restaurants.indices {
            restaurants[i].displayOrder = i
        }
    }
}
