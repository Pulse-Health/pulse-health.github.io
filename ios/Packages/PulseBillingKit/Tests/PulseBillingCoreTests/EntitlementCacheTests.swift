import XCTest
@testable import PulseBillingCore

final class EntitlementCacheTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_900_000_000)
    private func premium(until: Date?) -> Entitlement {
        Entitlement(premium: true, status: .active, planID: "premium_monthly", source: .stripe, premiumUntil: until)
    }

    func testPremiumWithinTheWindowAndBeforePremiumUntil() {
        let cached = CachedEntitlement(entitlement: premium(until: t0.addingTimeInterval(30 * 86_400)), confirmedAt: t0)
        XCTAssertTrue(EntitlementTrust.isPremium(cached, now: t0))
        XCTAssertTrue(EntitlementTrust.isPremium(cached, now: t0.addingTimeInterval(EntitlementTrust.offlineWindow)))
    }

    func testTheOfflineWindowCapsHowLongAnUnconfirmedAnswerIsTrusted() {
        let cached = CachedEntitlement(entitlement: premium(until: t0.addingTimeInterval(365 * 86_400)), confirmedAt: t0)
        XCTAssertFalse(EntitlementTrust.isPremium(cached, now: t0.addingTimeInterval(EntitlementTrust.offlineWindow + 1)))
    }

    func testPremiumUntilEndsTrustEvenInsideTheWindow() {
        let cached = CachedEntitlement(entitlement: premium(until: t0.addingTimeInterval(3_600)), confirmedAt: t0)
        XCTAssertTrue(EntitlementTrust.isPremium(cached, now: t0.addingTimeInterval(3_599)))
        XCTAssertFalse(EntitlementTrust.isPremium(cached, now: t0.addingTimeInterval(3_600)))
    }

    func testNotPremiumOrNothingCachedIsNotPremium() {
        XCTAssertFalse(EntitlementTrust.isPremium(nil, now: t0))
        XCTAssertFalse(EntitlementTrust.isPremium(CachedEntitlement(entitlement: .none, confirmedAt: t0), now: t0))
    }

    func testPremiumWithoutPremiumUntilReliesOnTheWindowOnly() {
        let cached = CachedEntitlement(entitlement: premium(until: nil), confirmedAt: t0)
        XCTAssertTrue(EntitlementTrust.isPremium(cached, now: t0.addingTimeInterval(86_400)))
    }

    func testInMemoryCacheIsPerUser() {
        let cache = InMemoryEntitlementCache()
        cache.store(premium(until: nil), userID: "a", confirmedAt: t0)
        XCTAssertNotNil(cache.cached(userID: "a"))
        XCTAssertNil(cache.cached(userID: "b"))
        cache.clear(userID: "a")
        XCTAssertNil(cache.cached(userID: "a"))
    }

    func testUserDefaultsCachePersistsAcrossInstancesAndIsPerUser() throws {
        let suite = "billing-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let entitlement = premium(until: t0.addingTimeInterval(86_400))
        UserDefaultsEntitlementCache(defaults: defaults).store(entitlement, userID: "user_1", confirmedAt: t0)

        let reopened = UserDefaultsEntitlementCache(defaults: defaults)
        XCTAssertEqual(reopened.cached(userID: "user_1"), CachedEntitlement(entitlement: entitlement, confirmedAt: t0))
        XCTAssertNil(reopened.cached(userID: "user_2"))

        // a later "not premium" answer replaces it
        reopened.store(.none, userID: "user_1", confirmedAt: t0.addingTimeInterval(60))
        XCTAssertEqual(reopened.cached(userID: "user_1")?.entitlement, Entitlement.none)
        reopened.clear(userID: "user_1")
        XCTAssertNil(reopened.cached(userID: "user_1"))
    }

    func testACorruptEntryReadsAsNothing() throws {
        let suite = "billing-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: "health.pulse.billing.entitlement.user_1")
        XCTAssertNil(UserDefaultsEntitlementCache(defaults: defaults).cached(userID: "user_1"))
    }
}
