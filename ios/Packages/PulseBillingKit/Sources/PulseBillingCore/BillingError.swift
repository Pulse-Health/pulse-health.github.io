import Foundation

/// The `error.code` values of the contract. Unknown codes decode to `.unknown`.
public enum BillingErrorCode: WireEnum {
    case unauthorized, invalidRequest, consentRequired, purchaseNotAvailable, planNotFound, alreadySubscribed
    case noSubscription, noCustomer, rateLimited, stripeError, `internal`
    case unknown(String)

    public init(wire: String) {
        switch wire {
        case "unauthorized": self = .unauthorized
        case "invalid_request": self = .invalidRequest
        case "consent_required": self = .consentRequired
        case "purchase_not_available": self = .purchaseNotAvailable
        case "plan_not_found": self = .planNotFound
        case "already_subscribed": self = .alreadySubscribed
        case "no_subscription": self = .noSubscription
        case "no_customer": self = .noCustomer
        case "rate_limited": self = .rateLimited
        case "stripe_error": self = .stripeError
        case "internal": self = .internal
        default: self = .unknown(wire)
        }
    }

    public var wire: String {
        switch self {
        case .unauthorized: return "unauthorized"
        case .invalidRequest: return "invalid_request"
        case .consentRequired: return "consent_required"
        case .purchaseNotAvailable: return "purchase_not_available"
        case .planNotFound: return "plan_not_found"
        case .alreadySubscribed: return "already_subscribed"
        case .noSubscription: return "no_subscription"
        case .noCustomer: return "no_customer"
        case .rateLimited: return "rate_limited"
        case .stripeError: return "stripe_error"
        case .internal: return "internal"
        case .unknown(let raw): return raw
        }
    }
}

struct ErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: BillingErrorCode
        let message: String
    }
    let error: Body
}

public enum BillingError: Error, Equatable, Sendable {
    /// No valid session, even after one retry with a fresh token. The user has to sign in again.
    case unauthorized
    /// The server answered with a contract error.
    case api(code: BillingErrorCode, status: Int, message: String)
    /// The request did not reach the server or no answer came back.
    case network(String)
    /// The answer was not what the contract promises.
    case invalidResponse(String)
}
