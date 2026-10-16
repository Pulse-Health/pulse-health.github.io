import XCTest
@testable import PulseBillingCore

/// A scripted `BillingServing`.
final class FakeBilling: BillingServing, @unchecked Sendable {
    private let lock = NSLock()
    var offersResult: Result<Offers, Error> = .success(FakeBilling.offers())
    var startResult: Result<SubscriptionStart, Error> = .success(FakeBilling.start(.payment))
    /// Answers of successive `sync()` calls; the last one repeats.
    var syncResults: [Result<Entitlement, Error>] = [.success(FakeBilling.premium)]
    var entitlementResult: Result<Entitlement, Error> = .success(FakeBilling.premium)
    private(set) var startCalls: [(planID: String, country: String?, billingCountry: String?, consent: WithdrawalConsent?, key: String)] = []
    private(set) var syncCount = 0
    var cancelResult: Result<Entitlement, Error> = .success(FakeBilling.premium)

    static let premium = Entitlement(premium: true, status: .active, planID: "premium_monthly", source: .stripe, currentPeriodEnd: Date(timeIntervalSince1970: 2_000_000_000), premiumUntil: Date(timeIntervalSince1970: 2_000_086_400))
    static let notYet = Entitlement(premium: false, status: .incomplete, planID: "premium_monthly", source: .stripe)

    static func offers(available: Bool = true, reason: PurchaseUnavailableReason? = nil, plans: [Plan]? = nil) -> Offers {
        Offers(
            purchase: PurchaseAvailability(available: available, reason: reason), requiresWithdrawalConsent: true, publishableKey: "pk_test_x", merchantDisplayName: "Pulse",
            plans: plans ?? [Plan(id: "premium_monthly", name: "Pulse Premium", interval: .month, currency: "eur", unitAmount: 999)]
        )
    }

    static func start(_ kind: PaymentIntentKind?) -> SubscriptionStart {
        SubscriptionStart(subscriptionID: "sub_1", status: "incomplete", customerID: "cus_1", customerEphemeralKeySecret: "ek_1", publishableKey: "pk_test_x", intent: kind.map { PaymentIntentInfo(kind: $0, clientSecret: "secret_1") })
    }

    func offers(country: String?) async throws -> Offers { try offersResult.get() }
    func entitlement() async throws -> Entitlement { try entitlementResult.get() }

    private func recordStart(_ call: (String, String?, String?, WithdrawalConsent?, String)) { lock.withLock { startCalls.append(call) } }
    private func nextSync() -> Result<Entitlement, Error> {
        lock.withLock {
            syncCount += 1
            return syncResults.count > 1 ? syncResults.removeFirst() : syncResults[0]
        }
    }

    func startSubscription(planID: String, country: String?, billingCountry: String?, consent: WithdrawalConsent?, idempotencyKey: String) async throws -> SubscriptionStart {
        recordStart((planID, country, billingCountry, consent, idempotencyKey))
        return try startResult.get()
    }

    func sync() async throws -> Entitlement { try nextSync().get() }
    func cancel() async throws -> Entitlement { try cancelResult.get() }
    func resume() async throws -> Entitlement { try cancelResult.get() }
    func portalURL(returnURL: String) async throws -> URL { URL(string: "https://billing.stripe.com/p/session/x")! }
    func deleteAccount() async throws {}
}

final class FakePresenter: PaymentSheetPresenting, @unchecked Sendable {
    private let lock = NSLock()
    var outcome: PaymentSheetOutcome = .completed
    private(set) var sessions: [PaymentSession] = []
    private func record(_ s: PaymentSession) { lock.withLock { sessions.append(s) } }
    func present(_ session: PaymentSession) async -> PaymentSheetOutcome { record(session); return outcome }
}

final class Sleeps: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var values: [TimeInterval] = []
    func add(_ v: TimeInterval) { lock.withLock { values.append(v) } }
}

final class PurchaseCoordinatorTests: XCTestCase {
    struct Rig {
        let coordinator: PurchaseCoordinator
        let billing: FakeBilling
        let presenter: FakePresenter
        let cache: InMemoryEntitlementCache
        let sleeps: Sleeps
    }

    private func makeRig(country: String? = "US", keys: [String] = ["key-1", "key-2", "key-3"]) -> Rig {
        let billing = FakeBilling()
        let presenter = FakePresenter()
        let cache = InMemoryEntitlementCache()
        let sleeps = Sleeps()
        let counter = KeyCounter(keys)
        let coordinator = PurchaseCoordinator(
            userID: "user_1", api: billing, presenter: presenter, cache: cache,
            country: { country }, consentLocale: "de-DE", now: { Date(timeIntervalSince1970: 1_900_000_000) },
            sleep: { sleeps.add($0) }, makeIdempotencyKey: { counter.next() }
        )
        return Rig(coordinator: coordinator, billing: billing, presenter: presenter, cache: cache, sleeps: sleeps)
    }

    /// Runs `body` and returns every state the coordinator went through, in order.
    private func states(of rig: Rig, _ body: () async -> Void) async -> [PurchaseState] {
        let collector = Task { () -> [PurchaseState] in
            var seen: [PurchaseState] = []
            for await s in rig.coordinator.states { seen.append(s) }
            return seen
        }
        await body()
        await rig.coordinator.finish()
        return await collector.value
    }

    // MARK: - Offers

    func testOffersWithPlansAreReady() async {
        let rig = makeRig()
        let seen = await states(of: rig) { await rig.coordinator.loadOffers() }
        XCTAssertEqual(seen, [.loadingOffers, .ready(FakeBilling.offers())])
    }

    func testUnavailableOffersHideTheBuyButton() async {
        let rig = makeRig(country: "DE")
        rig.billing.offersResult = .success(FakeBilling.offers(available: false, reason: .regionNotSupported, plans: []))
        let seen = await states(of: rig) { await rig.coordinator.loadOffers() }
        XCTAssertEqual(seen.last, .unavailable(.regionNotSupported))
    }

    func testAvailableButEmptyIsTreatedAsUnavailable() async {
        let rig = makeRig()
        rig.billing.offersResult = .success(FakeBilling.offers(available: true, plans: []))
        await rig.coordinator.loadOffers()
        let state = await rig.coordinator.state
        XCTAssertEqual(state, .unavailable(.billingDisabled))
    }

    func testOffersFailureIsReported() async {
        let rig = makeRig()
        rig.billing.offersResult = .failure(BillingError.network("offline"))
        await rig.coordinator.loadOffers()
        let state = await rig.coordinator.state
        XCTAssertEqual(state, .failed(.network))
    }

    // MARK: - Purchase

    func testHappyPath() async {
        let rig = makeRig()
        await rig.coordinator.loadOffers()
        let seen = await states(of: rig) { await rig.coordinator.purchase(planID: "premium_monthly", consentGiven: true) }
        // the stream replays from the beginning, so the earlier loadOffers() states are part of it
        XCTAssertEqual(seen, [.loadingOffers, .ready(FakeBilling.offers()), .preparing, .awaitingPayment, .confirming, .activated(FakeBilling.premium)])

        let call = try! XCTUnwrap(rig.billing.startCalls.first)
        XCTAssertEqual(call.planID, "premium_monthly")
        XCTAssertEqual(call.country, "US")
        XCTAssertEqual(call.consent, WithdrawalConsent(withdrawalWaiver: true, locale: "de-DE"))
        XCTAssertEqual(call.key, "key-1")

        let session = try! XCTUnwrap(rig.presenter.sessions.first)
        XCTAssertEqual(session, PaymentSession(customerID: "cus_1", ephemeralKeySecret: "ek_1", publishableKey: "pk_test_x", merchantDisplayName: "Pulse", intent: PaymentIntentInfo(kind: .payment, clientSecret: "secret_1")))
        XCTAssertEqual(rig.cache.cached(userID: "user_1")?.entitlement, FakeBilling.premium)
        XCTAssertTrue(rig.sleeps.values.isEmpty, "the first confirmation attempt is immediate")
    }

    func testTheSellerNameComesFromTheOffersOrTheHostDefault() async {
        let withOffers = makeRig()
        withOffers.billing.offersResult = .success(Offers(purchase: PurchaseAvailability(available: true), requiresWithdrawalConsent: false, publishableKey: "pk", merchantDisplayName: "Pulse Health GmbH", plans: FakeBilling.offers().plans))
        withOffers.presenter.outcome = .canceled
        await withOffers.coordinator.loadOffers()
        await withOffers.coordinator.purchase(planID: "premium_monthly")
        XCTAssertEqual(withOffers.presenter.sessions.first?.merchantDisplayName, "Pulse Health GmbH")

        let withoutOffers = makeRig() // purchase() without loadOffers(): the host's default name
        withoutOffers.presenter.outcome = .canceled
        await withoutOffers.coordinator.purchase(planID: "premium_monthly")
        XCTAssertEqual(withoutOffers.presenter.sessions.first?.merchantDisplayName, "Pulse")
    }

    func testNoConsentIsSentWhenNotGiven() async {
        let rig = makeRig()
        await rig.coordinator.purchase(planID: "premium_monthly")
        XCTAssertNil(rig.billing.startCalls.first?.consent)
    }

    func testATrialPassesTheSetupIntentToTheSheet() async {
        let rig = makeRig()
        rig.billing.startResult = .success(FakeBilling.start(.setup))
        await rig.coordinator.purchase(planID: "premium_monthly")
        XCTAssertEqual(rig.presenter.sessions.first?.intent.kind, .setup)
    }

    func testNothingToCollectSkipsTheSheet() async {
        let rig = makeRig()
        rig.billing.startResult = .success(FakeBilling.start(nil))
        let seen = await states(of: rig) { await rig.coordinator.purchase(planID: "premium_monthly") }
        XCTAssertEqual(seen, [.preparing, .confirming, .activated(FakeBilling.premium)])
        XCTAssertTrue(rig.presenter.sessions.isEmpty)
    }

    func testClosingTheSheetIsNotAnError() async {
        let rig = makeRig()
        rig.presenter.outcome = .canceled
        let seen = await states(of: rig) { await rig.coordinator.purchase(planID: "premium_monthly") }
        XCTAssertEqual(seen, [.preparing, .awaitingPayment, .canceled])
        XCTAssertEqual(rig.billing.syncCount, 0, "nothing was paid, so there is nothing to confirm")
    }

    func testAFailedSheetShowsItsMessage() async {
        let rig = makeRig()
        rig.presenter.outcome = .failed("Your card was declined.")
        await rig.coordinator.purchase(planID: "premium_monthly")
        let state = await rig.coordinator.state
        XCTAssertEqual(state, .failed(.message("Your card was declined.")))
        XCTAssertEqual(rig.billing.syncCount, 0)
    }

    func testServerRefusalsMapToTypedFailures() async {
        let cases: [(BillingErrorCode, Int, PurchaseFailure)] = [
            (.consentRequired, 400, .consentRequired),
            (.purchaseNotAvailable, 403, .notAvailable),
            (.rateLimited, 429, .rateLimited),
            (.planNotFound, 404, .message("nope")),
        ]
        for (code, status, expected) in cases {
            let rig = makeRig()
            rig.billing.startResult = .failure(BillingError.api(code: code, status: status, message: "nope"))
            await rig.coordinator.purchase(planID: "premium_monthly")
            let state = await rig.coordinator.state
            XCTAssertEqual(state, .failed(expected), "\(code)")
            XCTAssertTrue(rig.presenter.sessions.isEmpty)
        }
    }

    func testAlreadySubscribedJustConfirms() async {
        let rig = makeRig()
        rig.billing.startResult = .failure(BillingError.api(code: .alreadySubscribed, status: 409, message: "already"))
        await rig.coordinator.purchase(planID: "premium_monthly")
        let state = await rig.coordinator.state
        XCTAssertEqual(state, .activated(FakeBilling.premium))
        XCTAssertTrue(rig.presenter.sessions.isEmpty)
    }

    func testEveryPurchaseGetsAFreshIdempotencyKey() async {
        let rig = makeRig()
        rig.presenter.outcome = .canceled
        await rig.coordinator.purchase(planID: "premium_monthly")
        await rig.coordinator.purchase(planID: "premium_monthly")
        XCTAssertEqual(rig.billing.startCalls.map(\.key), ["key-1", "key-2"])
    }

    func testBillingCountryIsForwarded() async {
        let rig = makeRig()
        rig.presenter.outcome = .canceled
        await rig.coordinator.purchase(planID: "premium_yearly", billingCountry: "DE")
        XCTAssertEqual(rig.billing.startCalls.first?.billingCountry, "DE")
    }

    // MARK: - Confirmation

    func testALateWebhookIsWaitedFor() async {
        let rig = makeRig()
        rig.billing.syncResults = [.success(FakeBilling.notYet), .success(FakeBilling.notYet), .success(FakeBilling.premium)]
        await rig.coordinator.purchase(planID: "premium_monthly")
        let state = await rig.coordinator.state
        XCTAssertEqual(state, .activated(FakeBilling.premium))
        XCTAssertEqual(rig.billing.syncCount, 3)
        XCTAssertEqual(rig.sleeps.values, [1, 2])
    }

    func testStillNotPremiumAfterAllAttemptsIsPendingActivation() async {
        let rig = makeRig()
        rig.billing.syncResults = [.success(FakeBilling.notYet)]
        await rig.coordinator.purchase(planID: "premium_monthly")
        let state = await rig.coordinator.state
        XCTAssertEqual(state, .pendingActivation)
        XCTAssertEqual(rig.billing.syncCount, 6)
        XCTAssertEqual(rig.sleeps.values, [1, 2, 3, 5, 8])
        XCTAssertEqual(rig.cache.cached(userID: "user_1")?.entitlement, FakeBilling.notYet, "the latest server answer is cached")
    }

    func testATransientSyncErrorDoesNotTurnAPaymentIntoAnErrorScreen() async {
        let rig = makeRig()
        rig.billing.syncResults = [.failure(BillingError.network("blip")), .failure(BillingError.api(code: .stripeError, status: 502, message: "")), .success(FakeBilling.premium)]
        await rig.coordinator.purchase(planID: "premium_monthly")
        let state = await rig.coordinator.state
        XCTAssertEqual(state, .activated(FakeBilling.premium))
    }

    func testALostSessionDuringConfirmationStopsTheLoop() async {
        let rig = makeRig()
        rig.billing.syncResults = [.failure(BillingError.unauthorized)]
        await rig.coordinator.purchase(planID: "premium_monthly")
        let state = await rig.coordinator.state
        XCTAssertEqual(state, .failed(.unauthorized))
        XCTAssertEqual(rig.billing.syncCount, 1)
    }

    // MARK: - Re-entrancy

    func testASecondPurchaseWhileOneRunsIsIgnored() async {
        let rig = makeRig()
        let gate = Gate()
        let slowPresenter = GatedPresenter(gate: gate)
        let coordinator = PurchaseCoordinator(userID: "user_1", api: rig.billing, presenter: slowPresenter, cache: rig.cache, country: { "US" }, sleep: { _ in })
        let first = Task { await coordinator.purchase(planID: "premium_monthly") }
        await slowPresenter.waitUntilPresented()
        await coordinator.purchase(planID: "premium_monthly") // second tap
        XCTAssertEqual(rig.billing.startCalls.count, 1)
        gate.open()
        await first.value
        let state = await coordinator.state
        XCTAssertEqual(state, .activated(FakeBilling.premium))
    }

    // MARK: - Entitlement helpers

    func testRefreshStoresAnswersButAFailureLeavesTheCacheAlone() async {
        let rig = makeRig()
        let fresh = await rig.coordinator.refreshEntitlement()
        XCTAssertEqual(fresh, FakeBilling.premium)
        XCTAssertEqual(rig.cache.cached(userID: "user_1")?.entitlement, FakeBilling.premium)

        rig.billing.entitlementResult = .failure(BillingError.network("offline"))
        let offline = await rig.coordinator.refreshEntitlement()
        XCTAssertEqual(offline, FakeBilling.premium, "falls back to the cached answer")
        XCTAssertEqual(rig.cache.cached(userID: "user_1")?.entitlement, FakeBilling.premium)

        rig.billing.entitlementResult = .success(.none)
        let revoked = await rig.coordinator.refreshEntitlement()
        XCTAssertEqual(revoked, Entitlement.none)
        XCTAssertEqual(rig.cache.cached(userID: "user_1")?.entitlement, Entitlement.none, "a successful 'not premium' must clear Premium")
        let premiumFromCache = await rig.coordinator.isPremiumFromCache()
        XCTAssertFalse(premiumFromCache)
    }

    func testCancelAndResumeUpdateTheCache() async throws {
        let rig = makeRig()
        let canceling = Entitlement(premium: true, status: .active, planID: "premium_monthly", source: .stripe, cancelAtPeriodEnd: true, premiumUntil: Date(timeIntervalSince1970: 2_000_086_400))
        rig.billing.cancelResult = .success(canceling)
        let result = try await rig.coordinator.cancelSubscription()
        XCTAssertEqual(result, canceling)
        XCTAssertEqual(rig.cache.cached(userID: "user_1")?.entitlement.cancelAtPeriodEnd, true)
        _ = try await rig.coordinator.resumeSubscription()
    }
}

final class KeyCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String]
    init(_ keys: [String]) { self.keys = keys }
    func next() -> String { lock.withLock { keys.isEmpty ? UUID().uuidString : keys.removeFirst() } }
}

/// Lets a test hold the payment sheet open.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        let toResume = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        toResume.forEach { $0.resume() }
    }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }
}

final class GatedPresenter: PaymentSheetPresenting, @unchecked Sendable {
    private let gate: Gate
    private let presented = Gate()
    init(gate: Gate) { self.gate = gate }

    func waitUntilPresented() async { await presented.wait() }

    func present(_ session: PaymentSession) async -> PaymentSheetOutcome {
        presented.open()
        await gate.wait()
        return .completed
    }
}
