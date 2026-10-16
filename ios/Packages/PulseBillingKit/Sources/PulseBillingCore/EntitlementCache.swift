import Foundation

/// The last entitlement the server told us, plus when it did.
public struct CachedEntitlement: Codable, Equatable, Sendable {
    public let entitlement: Entitlement
    /// When the server last vouched for it (the device clock at the time of the answer).
    public let confirmedAt: Date

    public init(entitlement: Entitlement, confirmedAt: Date) {
        self.entitlement = entitlement
        self.confirmedAt = confirmedAt
    }
}

public protocol EntitlementCache: Sendable {
    func cached(userID: String) -> CachedEntitlement?
    func store(_ entitlement: Entitlement, userID: String, confirmedAt: Date)
    func clear(userID: String)
}

public enum EntitlementTrust {
    /// How long an answer stays usable without a fresh confirmation. Same window as the Pulse app's `PremiumAccessCache`: long
    /// enough for a subscriber who is offline, short enough that a revocation (refund, chargeback) is noticed.
    public static let offlineWindow: TimeInterval = 7 * 24 * 60 * 60

    /// Premium according to the cache: premium, not past `premiumUntil`, and confirmed within the offline window.
    public static func isPremium(_ cached: CachedEntitlement?, now: Date) -> Bool {
        guard let cached, cached.entitlement.premium else { return false }
        if let until = cached.entitlement.premiumUntil, now >= until { return false }
        return now.timeIntervalSince(cached.confirmedAt) <= offlineWindow
    }
}

public final class InMemoryEntitlementCache: EntitlementCache, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: CachedEntitlement] = [:]

    public init() {}

    public func cached(userID: String) -> CachedEntitlement? {
        lock.lock(); defer { lock.unlock() }
        return entries[userID]
    }

    public func store(_ entitlement: Entitlement, userID: String, confirmedAt: Date) {
        lock.lock(); defer { lock.unlock() }
        entries[userID] = CachedEntitlement(entitlement: entitlement, confirmedAt: confirmedAt)
    }

    public func clear(userID: String) {
        lock.lock(); defer { lock.unlock() }
        entries[userID] = nil
    }
}

/// Persists the cache in UserDefaults, one entry per user.
public final class UserDefaultsEntitlementCache: EntitlementCache, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ userID: String) -> String { "health.pulse.billing.entitlement.\(userID)" }

    public func cached(userID: String) -> CachedEntitlement? {
        guard let data = defaults.data(forKey: key(userID)) else { return nil }
        return try? BillingJSON.makeDecoder().decode(CachedEntitlement.self, from: data)
    }

    public func store(_ entitlement: Entitlement, userID: String, confirmedAt: Date) {
        let entry = CachedEntitlement(entitlement: entitlement, confirmedAt: confirmedAt)
        if let data = try? BillingJSON.makeEncoder().encode(entry) { defaults.set(data, forKey: key(userID)) }
    }

    public func clear(userID: String) {
        defaults.removeObject(forKey: key(userID))
    }
}
