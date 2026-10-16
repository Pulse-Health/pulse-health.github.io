import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Supplies the user's current Clerk session token (in the Pulse app: `try await Clerk.shared.session?.getToken()`).
/// Called for every request, so the host can hand out a fresh token each time; it is called again once after a 401.
public protocol SessionTokenProviding: Sendable {
    func sessionToken() async throws -> String
}

public struct ClosureSessionTokenProvider: SessionTokenProviding {
    private let body: @Sendable () async throws -> String

    public init(_ body: @escaping @Sendable () async throws -> String) {
        self.body = body
    }

    public func sessionToken() async throws -> String {
        try await body()
    }
}

public struct BillingConfiguration: Sendable {
    /// Origin of the billing API, for example `https://api.pulse.example`.
    public var baseURL: URL
    public var platform: BillingPlatform

    public init(baseURL: URL, platform: BillingPlatform = .ios) {
        self.baseURL = baseURL
        self.platform = platform
    }
}

/// What the purchase coordinator and the screens need from the server. `BillingAPI` is the implementation; tests use fakes.
public protocol BillingServing: Sendable {
    func offers(country: String?) async throws -> Offers
    func entitlement() async throws -> Entitlement
    func startSubscription(planID: String, country: String?, billingCountry: String?, consent: WithdrawalConsent?, idempotencyKey: String) async throws -> SubscriptionStart
    func sync() async throws -> Entitlement
    func cancel() async throws -> Entitlement
    func resume() async throws -> Entitlement
    func portalURL(returnURL: String) async throws -> URL
    func deleteAccount() async throws
}

public final class BillingAPI: BillingServing {
    private let configuration: BillingConfiguration
    private let tokens: SessionTokenProviding
    private let transport: BillingTransport

    public init(configuration: BillingConfiguration, tokens: SessionTokenProviding, transport: BillingTransport = URLSessionTransport()) {
        self.configuration = configuration
        self.tokens = tokens
        self.transport = transport
    }

    public func offers(country: String?) async throws -> Offers {
        var query = [URLQueryItem(name: "platform", value: configuration.platform.rawValue)]
        if let country = Self.normalized(country) { query.append(URLQueryItem(name: "country", value: country)) }
        return try decode(Offers.self, from: try await perform("GET", "offers", query: query))
    }

    public func entitlement() async throws -> Entitlement {
        try decode(EntitlementResponse.self, from: try await perform("GET", "entitlement")).entitlement
    }

    public func startSubscription(planID: String, country: String?, billingCountry: String?, consent: WithdrawalConsent?, idempotencyKey: String) async throws -> SubscriptionStart {
        let body = CreateSubscriptionRequest(
            planId: planID,
            platform: configuration.platform,
            country: Self.normalized(country),
            billingCountry: Self.normalized(billingCountry),
            consent: consent
        )
        let data = try await perform("POST", "subscriptions", body: try BillingJSON.makeEncoder().encode(body), headers: ["Idempotency-Key": idempotencyKey])
        return try decode(SubscriptionStart.self, from: data)
    }

    public func sync() async throws -> Entitlement {
        try decode(EntitlementResponse.self, from: try await perform("POST", "sync")).entitlement
    }

    public func cancel() async throws -> Entitlement {
        try decode(EntitlementResponse.self, from: try await perform("POST", "subscription/cancel")).entitlement
    }

    public func resume() async throws -> Entitlement {
        try decode(EntitlementResponse.self, from: try await perform("POST", "subscription/resume")).entitlement
    }

    public func portalURL(returnURL: String) async throws -> URL {
        let body = try BillingJSON.makeEncoder().encode(PortalRequest(returnUrl: returnURL))
        return try decode(PortalResponse.self, from: try await perform("POST", "portal", body: body)).url
    }

    public func deleteAccount() async throws {
        let response = try decode(AccountDeletedResponse.self, from: try await perform("DELETE", "account"))
        guard response.deleted else { throw BillingError.invalidResponse("account was not deleted") }
    }

    // MARK: - Plumbing

    private static func normalized(_ country: String?) -> String? {
        guard let value = country?.trimmingCharacters(in: .whitespaces), value.count == 2 else { return nil }
        return value.uppercased()
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try BillingJSON.makeDecoder().decode(type, from: data)
        } catch {
            throw BillingError.invalidResponse("could not read \(T.self): \(error)")
        }
    }

    private func makeRequest(_ method: String, _ path: String, query: [URLQueryItem], body: Data?, headers: [String: String], token: String) throws -> URLRequest {
        let endpoint = configuration.baseURL.appendingPathComponent("v1/billing/\(path)")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw BillingError.invalidResponse("bad URL")
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw BillingError.invalidResponse("bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    /// Sends one request. A 401 is retried once with a fresh token; contract errors are mapped to `BillingError.api`.
    private func perform(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil, headers: [String: String] = [:]) async throws -> Data {
        for attempt in 0..<2 {
            let token: String
            do {
                token = try await tokens.sessionToken()
            } catch {
                throw BillingError.unauthorized
            }
            let request = try makeRequest(method, path, query: query, body: body, headers: headers, token: token)
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.send(request)
            } catch let error as BillingError {
                throw error
            } catch {
                throw BillingError.network(error.localizedDescription)
            }
            if response.statusCode == 401 {
                if attempt == 0 { continue }
                throw BillingError.unauthorized
            }
            guard (200..<300).contains(response.statusCode) else {
                if let envelope = try? BillingJSON.makeDecoder().decode(ErrorEnvelope.self, from: data) {
                    throw BillingError.api(code: envelope.error.code, status: response.statusCode, message: envelope.error.message)
                }
                throw BillingError.api(code: .unknown("http_\(response.statusCode)"), status: response.statusCode, message: "")
            }
            return data
        }
        throw BillingError.unauthorized
    }
}
