//
//  LocalCacheManager.swift
//  NivyBar
//

import Foundation

// @unchecked Sendable: all state is file-system-backed (atomic writes),
// instance is a singleton used only for read/write from MainActor.
final class LocalCacheManager: @unchecked Sendable {

    static let shared = LocalCacheManager()
    private init() {}

    // MARK: - Paths

    private var cacheDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("NivyBar", isDirectory: true)
    }

    private var cacheFileURL: URL {
        cacheDirectory.appendingPathComponent("cached_menus.json")
    }

    // MARK: - Date helpers

    var todayString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "sk_SK")
        return fmt.string(from: Date())
    }

    // MARK: - Load

    func load() -> CachedMenuData? {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(CachedMenuData.self, from: data)
        } catch {
            print("Cache load error: \(error)")
            return nil
        }
    }

    // MARK: - Save

    func save(menus: [RestaurantMenu]) {
        let payload = CachedMenuData(date: todayString, savedAt: Date(), menus: menus)
        do {
            try FileManager.default.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: cacheFileURL, options: .atomic)
        } catch {
            print("Cache save error: \(error)")
        }
    }

    // MARK: - Clear

    func clear() {
        try? FileManager.default.removeItem(at: cacheFileURL)
    }
}
