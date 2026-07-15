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

    let didUpdateRecipe = PassthroughSubject<UUID, Never>()
    let didChangeRestaurants = PassthroughSubject<Void, Never>()

    private let dirtySubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Paths

    private var storeDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(Configuration.System.appSupportFolder, isDirectory: true)
    }

    private var storeFileURL: URL? {
        storeDirectory?.appendingPathComponent(Configuration.System.storeFileName)
    }

    // MARK: - Init

    init() {
        load()
        setupDebouncedSave()
        observeTermination()
    }

    private func observeTermination() {
        NotificationCenter.default
            .publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.persistNow() }
            .store(in: &cancellables)
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
        guard let file = storeFileURL,
              FileManager.default.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file) else {
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let loaded = try decoder.decode([UserRestaurant].self, from: data)
            restaurants = loaded.sorted { $0.displayOrder < $1.displayOrder }
        } catch {
            print(NivyBarError.storeDecodeFailed(error.localizedDescription).errorDescription ?? "")
        }
    }

    // MARK: - Save

    func persistNow() {
        guard let dir = storeDirectory, let file = storeFileURL else { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(restaurants)
            try data.write(to: file, options: .atomic)
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
        didChangeRestaurants.send()
    }

    func update(_ restaurant: UserRestaurant) {
        guard let idx = restaurants.firstIndex(where: { $0.id == restaurant.id }) else { return }
        restaurants[idx] = restaurant
        markDirty()
        didChangeRestaurants.send()
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
        restaurants.removeAll()
        if let file = storeFileURL {
            try? FileManager.default.removeItem(at: file)
        }
        didChangeRestaurants.send()
    }

    // MARK: - Helpers

    private func reorderAll() {
        for i in restaurants.indices {
            restaurants[i].displayOrder = i
        }
    }
}
