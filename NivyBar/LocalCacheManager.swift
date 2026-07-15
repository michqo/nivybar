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

    private var cacheDirectory: URL? {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent(Configuration.System.appSupportFolder, isDirectory: true)
    }

    private var cacheFileURL: URL? {
        cacheDirectory?.appendingPathComponent(Configuration.System.cacheFileName)
    }

    // MARK: - Date helpers

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = Configuration.System.dateFormat
        fmt.locale = Locale(identifier: Configuration.System.skLocale)
        return fmt
    }()

    var todayString: String {
        Self.dateFormatter.string(from: Date())
    }

    // MARK: - Load

    func load() -> CachedMenuData? {
        guard let file = cacheFileURL,
              FileManager.default.fileExists(atPath: file.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: file)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(CachedMenuData.self, from: data)
        } catch {
            print(NivyBarError.cacheLoadFailed(error.localizedDescription).errorDescription ?? "")
            return nil
        }
    }

    // MARK: - Save

    func save(menus: [RestaurantMenu]) {
        guard let dir = cacheDirectory, let file = cacheFileURL else {
            print(NivyBarError.cacheWriteFailed("Cache directory unavailable").errorDescription ?? "")
            return
        }
        let payload = CachedMenuData(date: todayString, savedAt: Date(), menus: menus)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: file, options: .atomic)
        } catch {
            print(NivyBarError.cacheWriteFailed(error.localizedDescription).errorDescription ?? "")
        }
    }

    // MARK: - Clear

    func clear() {
        guard let file = cacheFileURL else { return }
        try? FileManager.default.removeItem(at: file)
    }
}
