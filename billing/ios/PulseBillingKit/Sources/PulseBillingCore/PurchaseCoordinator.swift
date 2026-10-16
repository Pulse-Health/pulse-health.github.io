import Foundation

/// Everything the Stripe payment sheet needs for one purchase.
public struct PaymentSession: Equatable, Sendable {
    public let customerID: String
    public let ephemeralKeySecret: String
    public let publishableKey: String
    public let merchantDisplayName: String
    public let intent: PaymentIntentInfo

    public init(customerID: String, ephemeralKeySecret: String, publishableKey: String, merchantDisplayName: String, intent: PaymentIntentInfo) {
        self.customerID = customerID
        self.ephemeralKeySecret = ephemeralKeySecret
        self.publishableKey = publishableKey
        self.merchantDisplayName = merchantDisplayName
        self.intent = intent
    }
}

public enum PaymentSheetOutcome: Equatable, Sendable {
    case completed
    /// The user closed the sheet. Not an error.
    case canceled
    case failed(String)
}

/// Shows the payment sheet and returns when the user is done with it. The Stripe implementation lives in PulseBillingUI.
public protocol PaymentSheetPresenting: Sendable {
    func present(_ session: PaymentSession) async -> PaymentSheetOutcome
}

public enum PurchaseFailure: Equatable, Sendable {
    /// The server wants the withdrawal-right consent; show the checkbox.
    case consentRequired
    case notAvailable
    case rateLimited
    case unauthorized
    case network
    /// Text from the payment sheet or an unexpected server answer.
    case message(String)
}

public enum PurchaseState: Equatable, Sendable {
    case idle
    case loadingOffers
    case ready(Offers)
    /// Purchases cannot be started here; hide the buy button.
    case unavailable(PurchaseUnavailableReason)
    case preparing
    case awaitingPayment
    case confirming
    case activated(Entitlement)
    /// Paid, but the entitlement is not visible yet (the webhook is late). The app refreshes on its own later.
    case pendingActivation
    case canceled
    case failed(PurchaseFailure)
}

/// The purchase flow of client-design.md: offers, create the subscription, show the sheet, confirm with the server.
public actor PurchaseCoordinator {
    /// Every state change in order. Single consumer.
    public nonisolated let states: AsyncStream<PurchaseState>
    public private(set) var state: PurchaseState = .idle {
        didSet { continuation.yield(state) }
    }

    /// Delay before each of the (up to six) confirmation attempts.
    public static let confirmationSchedule: [TimeInterval] = [0, 1, 2, 3, 5, 8]

    private let continuation: AsyncStream<PurchaseState>.Continuation
    private let userID: String
    private let api: BillingServing
    private let presenter: PaymentSheetPresenting
    private let cache: EntitlementCache
    private let country: @Sendable () async -> String?
    private let consentLocale: String
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let makeIdempotencyKey: @Sendable () -> String
    private var inFlight = false
    /// What the payment sheet shows as the seller. Taken from the offers; the host's value is used if purchase() is called before any offers were loaded.
    private var merchantDisplayName: String

    public init(
        userID: String,
        api: BillingServing,
        presenter: PaymentSheetPresenting,
        cache: EntitlementCache = InMemoryEntitlementCache(),
        country: @escaping @Sendable () async -> String?,
        merchantDisplayName: String = "Pulse",
        consentLocale: String = Locale.current.identifier.replacingOccurrences(of: "_", with: "-"),
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) },
        makeIdempotencyKey: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        var continuation: AsyncStream<PurchaseState>.Continuation!
        self.states = AsyncStream { continuation = $0 }
        self.continuation = continuation
        self.userID = userID
        self.api = api
        self.presenter = presenter
        self.cache = cache
        self.country = country
        self.merchantDisplayName = merchantDisplayName
        self.consentLocale = consentLocale
        self.now = now
        self.sleep = sleep
        self.makeIdempotencyKey = makeIdempotencyKey
    }

    /// Ends the `states` stream. Call it when the owner (for example a view model) goes away.
    public func finish() {
        continuation.finish()
    }

    // MARK: - Offers

    public func loadOffers() async {
        guard !inFlight else { return }
        state = .loadingOffers
        do {
            let offers = try await api.offers(country: await country())
            if !offers.merchantDisplayName.isEmpty { merchantDisplayName = offers.merchantDisplayName }
            if offers.purchase.available, !offers.plans.isEmpty {
                state = .ready(offers)
            } else {
                state = .unavailable(offers.purchase.reason ?? .billingDisabled)
            }
        } catch {
            state = .failed(Self.failure(from: error))
        }
    }

    // MARK: - Purchase

    /// Runs the whole purchase for one plan. The result is the final `state`.
    public func purchase(planID: String, billingCountry: String? = nil, consentGiven: Bool = false) async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        state = .preparing
        let start: SubscriptionStart
        do {
            start = try await api.startSubscription(
                planID: planID,
                country: await country(),
                billingCountry: billingCountry,
                consent: consentGiven ? WithdrawalConsent(withdrawalWaiver: true, locale: consentLocale) : nil,
                idempotencyKey: makeIdempotencyKey()
            )
        } catch BillingError.api(code: .alreadySubscribed, _, _) {
            await confirm() // the user simply already has Premium
            return
        } catch {
            state = .failed(Self.failure(from: error))
            return
        }

        if let intent = start.intent {
            state = .awaitingPayment
            let outcome = await presenter.present(PaymentSession(
                customerID: start.customerID,
                ephemeralKeySecret: start.customerEphemeralKeySecret,
                publishableKey: start.publishableKey,
                merchantDisplayName: merchantDisplayName,
                intent: intent
            ))
            switch outcome {
            case .completed: break
            case .canceled:
                state = .canceled
                return
            case .failed(let message):
                state = .failed(.message(message))
                return
            }
        }
        await confirm()
    }

    /// Asks the server for the fresh entitlement until it shows Premium (the Stripe webhook may be a few seconds behind the sheet).
    private func confirm() async {
        state = .confirming
        for delay in Self.confirmationSchedule {
            if delay > 0 { await sleep(delay) }
            do {
                let entitlement = try await api.sync()
                cache.store(entitlement, userID: userID, confirmedAt: now())
                if entitlement.premium {
                    state = .activated(entitlement)
                    return
                }
            } catch BillingError.unauthorized {
                state = .failed(.unauthorized)
                return
            } catch {
                continue // a transient problem must not turn a successful payment into an error screen
            }
        }
        state = .pendingActivation
    }

    // MARK: - Entitlement

    /// The fresh entitlement, which is also stored in the cache. If the server cannot be reached the cached one is returned and
    /// the cache is left alone: only a successful answer, including "not premium", may change it.
    public func refreshEntitlement() async -> Entitlement? {
        do {
            let entitlement = try await api.entitlement()
            cache.store(entitlement, userID: userID, confirmedAt: now())
            return entitlement
        } catch {
            return cache.cached(userID: userID)?.entitlement
        }
    }

    public func cancelSubscription() async throws -> Entitlement {
        let entitlement = try await api.cancel()
        cache.store(entitlement, userID: userID, confirmedAt: now())
        return entitlement
    }

    public func resumeSubscription() async throws -> Entitlement {
        let entitlement = try await api.resume()
        cache.store(entitlement, userID: userID, confirmedAt: now())
        return entitlement
    }

    public func portalURL(returnURL: String) async throws -> URL {
        try await api.portalURL(returnURL: returnURL)
    }

    /// Premium according to the cache and the offline trust window.
    public func isPremiumFromCache() -> Bool {
        EntitlementTrust.isPremium(cache.cached(userID: userID), now: now())
    }

    /// How an error from the API is reported to the user.
    public static func failure(from error: Error) -> PurchaseFailure {
        switch error as? BillingError {
        case .unauthorized?: return .unauthorized
        case .network?: return .network
        case .api(let code, _, let message)?:
            switch code {
            case .consentRequired: return .consentRequired
            case .purchaseNotAvailable: return .notAvailable
            case .rateLimited: return .rateLimited
            case .unauthorized: return .unauthorized
            default: return .message(message.isEmpty ? code.wire : message)
            }
        case .invalidResponse(let detail)?: return .message(detail)
        case nil: return .message(error.localizedDescription)
        }
    }
}
