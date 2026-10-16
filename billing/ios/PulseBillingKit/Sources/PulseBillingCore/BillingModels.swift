import Foundation

// The wire models of billing/contract/openapi.yaml. The fixtures in billing/contract/fixtures are decoded by the tests.

public enum BillingPlatform: String, Codable, Sendable {
    case ios
    case android
}

public enum PlanInterval: WireEnum {
    case month, year
    case unknown(String)

    public init(wire: String) {
        switch wire {
        case "month": self = .month
        case "year": self = .year
        default: self = .unknown(wire)
        }
    }

    public var wire: String {
        switch self {
        case .month: return "month"
        case .year: return "year"
        case .unknown(let raw): return raw
        }
    }
}

public enum TaxBehavior: WireEnum {
    case inclusive, exclusive, unspecified
    case unknown(String)

    public init(wire: String) {
        switch wire {
        case "inclusive": self = .inclusive
        case "exclusive": self = .exclusive
        case "unspecified": self = .unspecified
        default: self = .unknown(wire)
        }
    }

    public var wire: String {
        switch self {
        case .inclusive: return "inclusive"
        case .exclusive: return "exclusive"
        case .unspecified: return "unspecified"
        case .unknown(let raw): return raw
        }
    }
}

public struct Plan: Codable, Equatable, Sendable, Identifiable {
    /// The plan id, which is the Stripe price lookup key (for example `premium_monthly`).
    public let id: String
    public let name: String
    public let interval: PlanInterval
    public let intervalCount: Int
    public let currency: String
    /// Minor units (cents).
    public let unitAmount: Int
    public let taxBehavior: TaxBehavior
    /// Trial length offered to this user; 0 when none.
    public let trialDays: Int

    public init(id: String, name: String, interval: PlanInterval, intervalCount: Int = 1, currency: String, unitAmount: Int, taxBehavior: TaxBehavior = .inclusive, trialDays: Int = 0) {
        self.id = id
        self.name = name
        self.interval = interval
        self.intervalCount = intervalCount
        self.currency = currency
        self.unitAmount = unitAmount
        self.taxBehavior = taxBehavior
        self.trialDays = trialDays
    }
}

public enum PurchaseUnavailableReason: WireEnum {
    case billingDisabled, platformNotSupported, regionNotSupported, alreadySubscribed
    case unknown(String)

    public init(wire: String) {
        switch wire {
        case "billing_disabled": self = .billingDisabled
        case "platform_not_supported": self = .platformNotSupported
        case "region_not_supported": self = .regionNotSupported
        case "already_subscribed": self = .alreadySubscribed
        default: self = .unknown(wire)
        }
    }

    public var wire: String {
        switch self {
        case .billingDisabled: return "billing_disabled"
        case .platformNotSupported: return "platform_not_supported"
        case .regionNotSupported: return "region_not_supported"
        case .alreadySubscribed: return "already_subscribed"
        case .unknown(let raw): return raw
        }
    }
}

public struct PurchaseAvailability: Codable, Equatable, Sendable {
    public let available: Bool
    public let reason: PurchaseUnavailableReason?

    public init(available: Bool, reason: PurchaseUnavailableReason? = nil) {
        self.available = available
        self.reason = reason
    }
}

public struct Offers: Codable, Equatable, Sendable {
    public let purchase: PurchaseAvailability
    /// Show the consent to immediate performance and loss of the right of withdrawal next to the buy button.
    public let requiresWithdrawalConsent: Bool
    public let publishableKey: String
    public let merchantDisplayName: String
    public let plans: [Plan]

    public init(purchase: PurchaseAvailability, requiresWithdrawalConsent: Bool, publishableKey: String, merchantDisplayName: String, plans: [Plan]) {
        self.purchase = purchase
        self.requiresWithdrawalConsent = requiresWithdrawalConsent
        self.publishableKey = publishableKey
        self.merchantDisplayName = merchantDisplayName
        self.plans = plans
    }
}

public enum EntitlementStatus: WireEnum {
    case none, trialing, active, pastDue, incomplete, unpaid, canceled, paused
    case unknown(String)

    public init(wire: String) {
        switch wire {
        case "none": self = .none
        case "trialing": self = .trialing
        case "active": self = .active
        case "past_due": self = .pastDue
        case "incomplete": self = .incomplete
        case "unpaid": self = .unpaid
        case "canceled": self = .canceled
        case "paused": self = .paused
        default: self = .unknown(wire)
        }
    }

    public var wire: String {
        switch self {
        case .none: return "none"
        case .trialing: return "trialing"
        case .active: return "active"
        case .pastDue: return "past_due"
        case .incomplete: return "incomplete"
        case .unpaid: return "unpaid"
        case .canceled: return "canceled"
        case .paused: return "paused"
        case .unknown(let raw): return raw
        }
    }
}

public enum EntitlementSource: WireEnum {
    case none, stripe, code
    case unknown(String)

    public init(wire: String) {
        switch wire {
        case "none": self = .none
        case "stripe": self = .stripe
        case "code": self = .code
        default: self = .unknown(wire)
        }
    }

    public var wire: String {
        switch self {
        case .none: return "none"
        case .stripe: return "stripe"
        case .code: return "code"
        case .unknown(let raw): return raw
        }
    }
}

public struct Entitlement: Codable, Equatable, Sendable {
    public let premium: Bool
    public let status: EntitlementStatus
    public let planID: String?
    public let source: EntitlementSource
    public let currentPeriodEnd: Date?
    public let cancelAtPeriodEnd: Bool
    public let trialEnd: Date?
    /// Until when a client may keep treating the user as Premium without asking the server.
    public let premiumUntil: Date?

    public init(premium: Bool, status: EntitlementStatus, planID: String? = nil, source: EntitlementSource = .none, currentPeriodEnd: Date? = nil, cancelAtPeriodEnd: Bool = false, trialEnd: Date? = nil, premiumUntil: Date? = nil) {
        self.premium = premium
        self.status = status
        self.planID = planID
        self.source = source
        self.currentPeriodEnd = currentPeriodEnd
        self.cancelAtPeriodEnd = cancelAtPeriodEnd
        self.trialEnd = trialEnd
        self.premiumUntil = premiumUntil
    }

    public static let none = Entitlement(premium: false, status: .none)

    enum CodingKeys: String, CodingKey {
        case premium, status, source, currentPeriodEnd, cancelAtPeriodEnd, trialEnd, premiumUntil
        case planID = "planId"
    }
}

struct EntitlementResponse: Codable, Equatable, Sendable {
    let entitlement: Entitlement
    let serverTime: Date
}

public enum PaymentIntentKind: WireEnum {
    case payment, setup
    case unknown(String)

    public init(wire: String) {
        switch wire {
        case "payment": self = .payment
        case "setup": self = .setup
        default: self = .unknown(wire)
        }
    }

    public var wire: String {
        switch self {
        case .payment: return "payment"
        case .setup: return "setup"
        case .unknown(let raw): return raw
        }
    }
}

/// What the Stripe payment sheet needs to collect a payment method or the first payment.
public struct PaymentIntentInfo: Codable, Equatable, Sendable {
    public let kind: PaymentIntentKind
    public let clientSecret: String

    public init(kind: PaymentIntentKind, clientSecret: String) {
        self.kind = kind
        self.clientSecret = clientSecret
    }
}

public struct SubscriptionStart: Codable, Equatable, Sendable {
    public let subscriptionID: String
    public let status: String
    public let customerID: String
    public let customerEphemeralKeySecret: String
    public let publishableKey: String
    /// Nil when there is nothing left to collect (the subscription is already paid).
    public let intent: PaymentIntentInfo?

    public init(subscriptionID: String, status: String, customerID: String, customerEphemeralKeySecret: String, publishableKey: String, intent: PaymentIntentInfo?) {
        self.subscriptionID = subscriptionID
        self.status = status
        self.customerID = customerID
        self.customerEphemeralKeySecret = customerEphemeralKeySecret
        self.publishableKey = publishableKey
        self.intent = intent
    }

    enum CodingKeys: String, CodingKey {
        case status, customerEphemeralKeySecret, publishableKey, intent
        case subscriptionID = "subscriptionId"
        case customerID = "customerId"
    }
}

/// The buyer's consent to immediate performance and loss of the withdrawal right (see `Offers.requiresWithdrawalConsent`).
public struct WithdrawalConsent: Codable, Equatable, Sendable {
    public let withdrawalWaiver: Bool
    /// BCP 47 language of the text the buyer saw, for example `de-DE`.
    public let locale: String

    public init(withdrawalWaiver: Bool, locale: String) {
        self.withdrawalWaiver = withdrawalWaiver
        self.locale = locale
    }
}

struct CreateSubscriptionRequest: Codable, Equatable, Sendable {
    let planId: String
    let platform: BillingPlatform
    let country: String?
    let billingCountry: String?
    let consent: WithdrawalConsent?
}

struct PortalRequest: Codable, Sendable { let returnUrl: String }
struct PortalResponse: Codable, Sendable { let url: URL }
struct AccountDeletedResponse: Codable, Sendable { let deleted: Bool }
