import XCTest
@testable import PulseBillingCore

final class ContractTests: XCTestCase {
    override func setUpWithError() throws {
        // These fixtures are the contract. Missing them must fail loudly here; only a copy of the package outside the repository may opt out.
        if !Fixtures.isAvailable, ProcessInfo.processInfo.environment["PULSE_BILLING_FIXTURES_OPTIONAL"] == "1" {
            throw XCTSkip("contract fixtures not present in this checkout")
        }
        XCTAssertTrue(Fixtures.isAvailable, "billing/contract/fixtures not found at \(Fixtures.directory.path)")
    }

    /// Every fixture file, by the type it must decode to. A new fixture without an entry here fails `testEveryFixtureIsCovered`.
    private func check(_ name: String) throws {
        switch name {
        case "offers_available.json":
            let offers = try Fixtures.decode(Offers.self, name)
            XCTAssertEqual(offers.purchase, PurchaseAvailability(available: true, reason: nil))
            XCTAssertTrue(offers.requiresWithdrawalConsent)
            XCTAssertEqual(offers.publishableKey, "pk_test_FIXTURE")
            XCTAssertEqual(offers.merchantDisplayName, "Pulse")
            XCTAssertEqual(offers.plans.map(\.id), ["premium_monthly", "premium_yearly"])
            XCTAssertEqual(offers.plans[0], Plan(id: "premium_monthly", name: "Pulse Premium", interval: .month, currency: "eur", unitAmount: 999, taxBehavior: .inclusive, trialDays: 7))
            XCTAssertEqual(offers.plans[1].interval, .year)
            XCTAssertEqual(offers.plans[1].unitAmount, 7999)
        case "offers_unavailable_region.json":
            let offers = try Fixtures.decode(Offers.self, name)
            XCTAssertEqual(offers.purchase, PurchaseAvailability(available: false, reason: .regionNotSupported))
            XCTAssertTrue(offers.plans.isEmpty)
        case "entitlement_none.json":
            let r = try Fixtures.decode(EntitlementResponse.self, name)
            XCTAssertEqual(r.entitlement, .none)
            XCTAssertEqual(r.serverTime, Date(timeIntervalSince1970: 1_792_144_800)) // 2026-10-16T10:00:00Z
        case "entitlement_active.json":
            let e = try Fixtures.decode(EntitlementResponse.self, name).entitlement
            XCTAssertTrue(e.premium)
            XCTAssertEqual(e.status, .active)
            XCTAssertEqual(e.planID, "premium_monthly")
            XCTAssertEqual(e.source, .stripe)
            XCTAssertFalse(e.cancelAtPeriodEnd)
            XCTAssertEqual(e.premiumUntil, BillingJSON.parseDate("2026-11-17T10:00:00Z"))
        case "entitlement_canceling.json":
            let e = try Fixtures.decode(EntitlementResponse.self, name).entitlement
            XCTAssertTrue(e.premium)
            XCTAssertTrue(e.cancelAtPeriodEnd)
            XCTAssertEqual(e.premiumUntil, e.currentPeriodEnd)
        case "entitlement_past_due.json":
            let e = try Fixtures.decode(EntitlementResponse.self, name).entitlement
            XCTAssertEqual(e.status, .pastDue)
            XCTAssertTrue(e.premium)
        case "subscription_payment.json":
            let s = try Fixtures.decode(SubscriptionStart.self, name)
            XCTAssertEqual(s.subscriptionID, "sub_FIXTURE")
            XCTAssertEqual(s.customerID, "cus_FIXTURE")
            XCTAssertEqual(s.customerEphemeralKeySecret, "ek_test_FIXTURE")
            XCTAssertEqual(s.intent, PaymentIntentInfo(kind: .payment, clientSecret: "pi_FIXTURE_secret_FIXTURE"))
        case "subscription_trial_setup.json":
            let s = try Fixtures.decode(SubscriptionStart.self, name)
            XCTAssertEqual(s.status, "trialing")
            XCTAssertEqual(s.intent?.kind, .setup)
        case "portal.json":
            XCTAssertEqual(try Fixtures.decode(PortalResponse.self, name).url.host, "billing.stripe.com")
        case "account_deleted.json":
            XCTAssertTrue(try Fixtures.decode(AccountDeletedResponse.self, name).deleted)
        case "error_already_subscribed.json":
            XCTAssertEqual(try Fixtures.decode(ErrorEnvelope.self, name).error.code, .alreadySubscribed)
        case "error_purchase_not_available.json":
            XCTAssertEqual(try Fixtures.decode(ErrorEnvelope.self, name).error.code, .purchaseNotAvailable)
        case "error_consent_required.json":
            XCTAssertEqual(try Fixtures.decode(ErrorEnvelope.self, name).error.code, .consentRequired)
        default:
            XCTFail("fixture \(name) has no decoding test")
        }
    }

    func testEveryFixtureIsCovered() throws {
        let names = try Fixtures.names()
        XCTAssertGreaterThanOrEqual(names.count, 12)
        for name in names { try check(name) }
    }

    func testUnknownEnumValuesAndFieldsNeverBreakDecoding() throws {
        let json = """
        {
          "entitlement": {
            "premium": true, "status": "something_new", "planId": "premium_x", "source": "apple",
            "currentPeriodEnd": "2026-11-16T10:00:00.250Z", "cancelAtPeriodEnd": false, "trialEnd": null,
            "premiumUntil": "2026-11-17T10:00:00Z", "aFieldFromTheFuture": [1, 2, 3]
          },
          "serverTime": "2026-10-16T10:00:00Z"
        }
        """
        let e = try BillingJSON.makeDecoder().decode(EntitlementResponse.self, from: Data(json.utf8)).entitlement
        XCTAssertEqual(e.status, .unknown("something_new"))
        XCTAssertEqual(e.source, .unknown("apple"))
        XCTAssertNotNil(e.currentPeriodEnd, "fractional seconds must be accepted")

        let offers = """
        {"purchase":{"available":false,"reason":"brand_new_reason"},"requiresWithdrawalConsent":false,"publishableKey":"pk","merchantDisplayName":"P",
         "plans":[{"id":"x","name":"X","interval":"week","intervalCount":2,"currency":"usd","unitAmount":1,"taxBehavior":"weird","trialDays":0}]}
        """
        let o = try BillingJSON.makeDecoder().decode(Offers.self, from: Data(offers.utf8))
        XCTAssertEqual(o.purchase.reason, .unknown("brand_new_reason"))
        XCTAssertEqual(o.plans[0].interval, .unknown("week"))
        XCTAssertEqual(o.plans[0].taxBehavior, .unknown("weird"))

        let err = try BillingJSON.makeDecoder().decode(ErrorEnvelope.self, from: Data(#"{"error":{"code":"teapot","message":"m"}}"#.utf8))
        XCTAssertEqual(err.error.code, .unknown("teapot"))
    }

    func testEntitlementSurvivesAnEncodeDecodeRoundTrip() throws {
        let original = Entitlement(premium: true, status: .pastDue, planID: "premium_yearly", source: .code, currentPeriodEnd: Date(timeIntervalSince1970: 1_800_000_000), cancelAtPeriodEnd: true, trialEnd: nil, premiumUntil: Date(timeIntervalSince1970: 1_800_086_400))
        let data = try BillingJSON.makeEncoder().encode(original)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"planId\""), "the wire key is planId")
        XCTAssertEqual(try BillingJSON.makeDecoder().decode(Entitlement.self, from: data), original)
    }

    func testMalformedDatesAreRejected() {
        let json = #"{"entitlement":{"premium":true,"status":"active","planId":null,"source":"stripe","currentPeriodEnd":"yesterday","cancelAtPeriodEnd":false,"trialEnd":null,"premiumUntil":null},"serverTime":"2026-10-16T10:00:00Z"}"#
        XCTAssertThrowsError(try BillingJSON.makeDecoder().decode(EntitlementResponse.self, from: Data(json.utf8)))
    }
}
