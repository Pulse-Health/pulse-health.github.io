import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PulseBillingCore

final class BillingAPITests: XCTestCase {
    private func makeAPI(base: String = "https://api.pulse.test", transport: MockTransport, tokens: CountingTokens = CountingTokens()) -> BillingAPI {
        BillingAPI(configuration: BillingConfiguration(baseURL: URL(string: base)!), tokens: tokens, transport: transport)
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(Fixtures.isAvailable || ProcessInfo.processInfo.environment["PULSE_BILLING_FIXTURES_OPTIONAL"] != "1")
        XCTAssertTrue(Fixtures.isAvailable, "billing/contract/fixtures not found")
    }

    func testOffersRequestAndResponse() async throws {
        let transport = MockTransport()
        try transport.enqueue("GET /v1/billing/offers", .init(fixture: "offers_available.json"))
        let offers = try await makeAPI(transport: transport).offers(country: "de")

        XCTAssertEqual(offers.plans.count, 2)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/v1/billing/offers")
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "platform" }?.value, "ios")
        XCTAssertEqual(items.first { $0.name == "country" }?.value, "DE")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(request.httpBody)
    }

    func testCountryIsOmittedWhenUnknownOrMalformed() async throws {
        let transport = MockTransport()
        for _ in 0..<2 { try transport.enqueue("GET /v1/billing/offers", .init(fixture: "offers_unavailable_region.json")) }
        let api = makeAPI(transport: transport)
        _ = try await api.offers(country: nil)
        _ = try await api.offers(country: "USA")
        for request in transport.requests {
            XCTAssertNil(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "country" })
        }
    }

    func testBaseURLWithAPathPrefixIsKept() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/billing/entitlement", try .init(fixture: "entitlement_active.json"))
        let entitlement = try await makeAPI(base: "https://pulse.test/api", transport: transport).entitlement()
        XCTAssertTrue(entitlement.premium)
    }

    func testStartSubscriptionSendsTheContractBodyAndIdempotencyKey() async throws {
        let transport = MockTransport()
        try transport.enqueue("POST /v1/billing/subscriptions", .init(fixture: "subscription_payment.json"))
        let start = try await makeAPI(transport: transport).startSubscription(
            planID: "premium_monthly", country: "de", billingCountry: nil,
            consent: WithdrawalConsent(withdrawalWaiver: true, locale: "de-DE"), idempotencyKey: "tap-123"
        )
        XCTAssertEqual(start.intent?.kind, .payment)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "tap-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["planId"] as? String, "premium_monthly")
        XCTAssertEqual(body["platform"] as? String, "ios")
        XCTAssertEqual(body["country"] as? String, "DE")
        XCTAssertNil(body["billingCountry"], "absent values must not be sent as null")
        let consent = try XCTUnwrap(body["consent"] as? [String: Any])
        XCTAssertEqual(consent["withdrawalWaiver"] as? Bool, true)
        XCTAssertEqual(consent["locale"] as? String, "de-DE")
        XCTAssertEqual(Set(body.keys), ["planId", "platform", "country", "consent"])
    }

    func testEntitlementEndpointsUseTheirContractPaths() async throws {
        let transport = MockTransport()
        for key in ["POST /v1/billing/sync", "POST /v1/billing/subscription/cancel", "POST /v1/billing/subscription/resume"] {
            try transport.enqueue(key, .init(fixture: "entitlement_canceling.json"))
        }
        let api = makeAPI(transport: transport)
        _ = try await api.sync()
        let canceled = try await api.cancel()
        _ = try await api.resume()
        XCTAssertTrue(canceled.cancelAtPeriodEnd)
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/v1/billing/sync", "/v1/billing/subscription/cancel", "/v1/billing/subscription/resume"])
    }

    func testPortalAndAccountDeletion() async throws {
        let transport = MockTransport()
        try transport.enqueue("POST /v1/billing/portal", .init(fixture: "portal.json"))
        try transport.enqueue("DELETE /v1/billing/account", .init(fixture: "account_deleted.json"))
        let api = makeAPI(transport: transport)
        let url = try await api.portalURL(returnURL: "pulse://billing/return")
        XCTAssertEqual(url.host, "billing.stripe.com")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(transport.requests[0].httpBody)) as? [String: String])
        XCTAssertEqual(body, ["returnUrl": "pulse://billing/return"])
        try await api.deleteAccount()
        XCTAssertEqual(transport.requests[1].httpMethod, "DELETE")
    }

    // MARK: - Authentication

    func testA401IsRetriedOnceWithAFreshToken() async throws {
        let transport = MockTransport()
        let tokens = CountingTokens()
        transport.enqueue("GET /v1/billing/entitlement", .init(401, json: #"{"error":{"code":"unauthorized","message":"Sign in again."}}"#))
        try transport.enqueue("GET /v1/billing/entitlement", .init(fixture: "entitlement_active.json"))
        let entitlement = try await makeAPI(transport: transport, tokens: tokens).entitlement()
        XCTAssertTrue(entitlement.premium)
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer token-1", "Bearer token-2"])
    }

    func testASecond401BecomesUnauthorizedWithoutAThirdAttempt() async {
        let transport = MockTransport()
        for _ in 0..<3 { transport.enqueue("GET /v1/billing/entitlement", .init(401)) }
        await XCTAssertThrowsBillingError(try await makeAPI(transport: transport).entitlement(), .unauthorized)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testNoSessionTokenMeansUnauthorizedAndNothingIsSent() async {
        let transport = MockTransport()
        let tokens = CountingTokens()
        tokens.failing = true
        await XCTAssertThrowsBillingError(try await makeAPI(transport: transport, tokens: tokens).entitlement(), .unauthorized)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    // MARK: - Errors

    func testContractErrorsKeepTheirCodeStatusAndMessage() async throws {
        let transport = MockTransport()
        try transport.enqueue("POST /v1/billing/subscriptions", .init(409, fixture: "error_already_subscribed.json"))
        try transport.enqueue("POST /v1/billing/subscriptions", .init(400, fixture: "error_consent_required.json"))
        let api = makeAPI(transport: transport)
        await XCTAssertThrowsBillingError(
            try await api.startSubscription(planID: "p", country: "US", billingCountry: nil, consent: nil, idempotencyKey: "k"),
            .api(code: .alreadySubscribed, status: 409, message: "This account already has an active subscription.")
        )
        do {
            _ = try await api.startSubscription(planID: "p", country: "DE", billingCountry: nil, consent: nil, idempotencyKey: "k")
            XCTFail("expected an error")
        } catch let BillingError.api(code, status, _) {
            XCTAssertEqual(code, .consentRequired)
            XCTAssertEqual(status, 400)
        }
    }

    func testUnknownErrorCodesAndBodiesThatAreNotJSON() async {
        let transport = MockTransport()
        transport.enqueue("GET /v1/billing/entitlement", .init(418, json: #"{"error":{"code":"teapot","message":"short and stout"}}"#))
        transport.enqueue("GET /v1/billing/entitlement", .init(502, json: "<html>Bad Gateway</html>"))
        let api = makeAPI(transport: transport)
        await XCTAssertThrowsBillingError(try await api.entitlement(), .api(code: .unknown("teapot"), status: 418, message: "short and stout"))
        await XCTAssertThrowsBillingError(try await api.entitlement(), .api(code: .unknown("http_502"), status: 502, message: ""))
    }

    func testTransportFailuresAreNetworkErrorsAndGarbageIsAnInvalidResponse() async {
        let transport = MockTransport()
        transport.enqueue("GET /v1/billing/entitlement", error: URLError(.notConnectedToInternet))
        transport.enqueue("GET /v1/billing/entitlement", .init(200, json: "[]"))
        let api = makeAPI(transport: transport)
        do {
            _ = try await api.entitlement()
            XCTFail("expected an error")
        } catch let BillingError.network(message) {
            XCTAssertFalse(message.isEmpty)
        } catch {
            XCTFail("unexpected \(error)")
        }
        do {
            _ = try await api.entitlement()
            XCTFail("expected an error")
        } catch BillingError.invalidResponse {
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
