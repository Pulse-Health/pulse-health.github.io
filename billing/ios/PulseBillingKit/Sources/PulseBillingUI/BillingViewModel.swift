#if os(iOS)
import SwiftUI
import PulseBillingCore

/// Where the paywall links to and where the customer portal sends the user back to.
public struct BillingLinks: Sendable {
    public var termsURL: URL?
    public var privacyURL: URL?
    /// A URL of the app (scheme registered in Info.plist) that must also be in the server's `BILLING_PORTAL_RETURN_URLS`.
    public var portalReturnURL: String

    public init(termsURL: URL?, privacyURL: URL?, portalReturnURL: String) {
        self.termsURL = termsURL
        self.privacyURL = privacyURL
        self.portalReturnURL = portalReturnURL
    }
}

/// Drives the paywall and the manage screen from a `PurchaseCoordinator`.
@MainActor
public final class BillingViewModel: ObservableObject {
    public enum Phase: Equatable {
        case loading
        case purchasable(Offers)
        case unavailable
        case working(String)
        case activated
        case pending
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .loading
    @Published public private(set) var entitlement: Entitlement?
    @Published public var selectedPlanID: String?
    @Published public var consentTicked = false
    /// A message to show next to the buy button or the manage buttons (already localized).
    @Published public private(set) var notice: String?
    /// True while cancel / resume / portal requests run.
    @Published public private(set) var isBusy = false

    public let strings: BillingStrings
    public let links: BillingLinks

    private let coordinator: PurchaseCoordinator
    private var offers: Offers?
    private var streamTask: Task<Void, Never>?

    public init(coordinator: PurchaseCoordinator, links: BillingLinks, strings: BillingStrings = .forLocale()) {
        self.coordinator = coordinator
        self.links = links
        self.strings = strings
    }

    // MARK: Lifecycle

    /// Starts listening to the coordinator and loads the offers and the entitlement. Safe to call repeatedly.
    public func start() {
        guard streamTask == nil else { return }
        let stream = coordinator.states
        streamTask = Task { [weak self] in
            for await state in stream {
                self?.apply(state)
            }
        }
        Task { await refresh() }
    }

    public func stop() {
        streamTask?.cancel()
        streamTask = nil
    }

    public func refresh() async {
        await coordinator.loadOffers()
        entitlement = await coordinator.refreshEntitlement()
    }

    /// Only the entitlement, for the manage screen.
    public func refreshEntitlement() async {
        entitlement = await coordinator.refreshEntitlement()
    }

    // MARK: Actions

    public var selectedPlan: Plan? {
        guard case .purchasable(let offers) = phase else { return nil }
        return offers.plans.first(where: { $0.id == selectedPlanID }) ?? offers.plans.first
    }

    public var canBuy: Bool {
        guard case .purchasable(let offers) = phase, selectedPlan != nil else { return false }
        return !offers.requiresWithdrawalConsent || consentTicked
    }

    public func buy() {
        guard case .purchasable(let offers) = phase, let plan = selectedPlan else { return }
        if offers.requiresWithdrawalConsent && !consentTicked {
            notice = strings.consentMissing
            return
        }
        notice = nil
        let consent = consentTicked
        let coordinator = self.coordinator
        Task { await coordinator.purchase(planID: plan.id, consentGiven: consent) }
    }

    public func cancelSubscription() {
        mutate { try await $0.cancelSubscription() }
    }

    public func resumeSubscription() {
        mutate { try await $0.resumeSubscription() }
    }

    /// The customer-portal link (payment methods, invoices); nil with a notice if it cannot be created.
    public func portalURL() async -> URL? {
        isBusy = true
        defer { isBusy = false }
        do {
            return try await coordinator.portalURL(returnURL: links.portalReturnURL)
        } catch {
            notice = strings.message(for: PurchaseCoordinator.failure(from: error))
            return nil
        }
    }

    private func mutate(_ operation: @escaping (PurchaseCoordinator) async throws -> Entitlement) {
        guard !isBusy else { return }
        isBusy = true
        notice = nil
        let coordinator = self.coordinator
        Task {
            do {
                entitlement = try await operation(coordinator)
            } catch {
                notice = strings.message(for: PurchaseCoordinator.failure(from: error))
            }
            isBusy = false
        }
    }

    // MARK: State mapping

    private func apply(_ state: PurchaseState) {
        switch state {
        case .idle:
            break
        case .loadingOffers:
            if offers == nil { phase = .loading }
        case .ready(let newOffers):
            offers = newOffers
            if selectedPlanID == nil || !newOffers.plans.contains(where: { $0.id == selectedPlanID }) {
                selectedPlanID = newOffers.plans.first?.id
            }
            phase = .purchasable(newOffers)
        case .unavailable:
            offers = nil
            phase = .unavailable
        case .preparing, .awaitingPayment:
            phase = .working(strings.working)
        case .confirming:
            phase = .working(strings.confirming)
        case .activated(let newEntitlement):
            entitlement = newEntitlement
            phase = .activated
        case .pendingActivation:
            phase = .pending
        case .canceled:
            phase = offers.map { Phase.purchasable($0) } ?? .loading
        case .failed(let failure):
            let message = strings.message(for: failure)
            notice = message
            if let offers, failure != .unauthorized {
                phase = .purchasable(offers)
            } else {
                phase = .failed(message)
            }
        }
    }
}
#endif
