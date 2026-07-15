//
//  AIRateLimiter.swift
//  NivyBar
//

import Foundation

/// Persists call count per calendar day to UserDefaults.
/// Thread-safe: all mutations are serialized through a lock.
final class AIRateLimiter: @unchecked Sendable {

    nonisolated static let shared = AIRateLimiter()
    private init() {}

    private let lock = NSLock()
    private let countKey = Configuration.System.rateLimitCountKey
    private let dateKey  = Configuration.System.rateLimitDateKey

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = Configuration.System.dateFormat
        return fmt
    }()

    private var dailyLimit: Int { AIConfig.dailyLimit }

    private var todayString: String {
        Self.dateFormatter.string(from: Date())
    }

    /// Returns (allowed: Bool, used: Int, limit: Int)
    nonisolated func checkAndIncrement() -> (allowed: Bool, used: Int, limit: Int) {
        lock.lock()
        defer { lock.unlock() }

        let today = todayString
        let storedDate = UserDefaults.standard.string(forKey: dateKey) ?? ""

        if storedDate != today {
            UserDefaults.standard.set(today, forKey: dateKey)
            UserDefaults.standard.set(0, forKey: countKey)
        }

        let current = UserDefaults.standard.integer(forKey: countKey)
        let limit   = dailyLimit

        guard current < limit else {
            return (false, current, limit)
        }

        UserDefaults.standard.set(current + 1, forKey: countKey)
        return (true, current + 1, limit)
    }

    nonisolated var currentUsage: (used: Int, limit: Int) {
        lock.lock()
        defer { lock.unlock() }
        let today = todayString
        let storedDate = UserDefaults.standard.string(forKey: dateKey) ?? ""
        if storedDate != today { return (0, dailyLimit) }
        return (UserDefaults.standard.integer(forKey: countKey), dailyLimit)
    }

    nonisolated func reset() {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: dateKey)
        UserDefaults.standard.removeObject(forKey: countKey)
    }
}
