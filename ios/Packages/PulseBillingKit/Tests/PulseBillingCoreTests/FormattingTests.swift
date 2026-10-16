import XCTest
@testable import PulseBillingCore

final class FormattingTests: XCTestCase {
    func testPricesUseTheCurrencysOwnDecimals() {
        XCTAssertTrue(BillingFormat.price(unitAmount: 999, currency: "eur", locale: Locale(identifier: "de_DE")).contains("9,99"))
        XCTAssertTrue(BillingFormat.price(unitAmount: 999, currency: "EUR", locale: Locale(identifier: "en_US")).contains("9.99"))
        XCTAssertTrue(BillingFormat.price(unitAmount: 7999, currency: "usd", locale: Locale(identifier: "en_US")).contains("79.99"))
        // zero-decimal currency: 500 minor units are 500 yen, not 5.00
        let yen = BillingFormat.price(unitAmount: 500, currency: "jpy", locale: Locale(identifier: "en_US"))
        XCTAssertTrue(yen.contains("500"), yen)
        XCTAssertFalse(yen.contains("5.00"), yen)
    }

    func testMinorUnitsFollowStripesTable() {
        XCTAssertEqual(BillingFormat.minorUnitDigits(currency: "jpy"), 0)
        XCTAssertEqual(BillingFormat.minorUnitDigits(currency: "KRW"), 0)
        XCTAssertEqual(BillingFormat.minorUnitDigits(currency: "kwd"), 3)
        XCTAssertEqual(BillingFormat.minorUnitDigits(currency: "eur"), 2)
        XCTAssertEqual(BillingFormat.minorUnitDigits(currency: "usd"), 2)
        XCTAssertTrue(BillingFormat.price(unitAmount: 1500, currency: "kwd", locale: Locale(identifier: "en_US")).contains("1.500"))
    }

    func testPriceOfAPlan() {
        let plan = Plan(id: "premium_yearly", name: "P", interval: .year, currency: "eur", unitAmount: 7999)
        XCTAssertTrue(BillingFormat.price(of: plan, locale: Locale(identifier: "de_DE")).contains("79,99"))
    }

    func testStringsFollowTheLanguageAndCoverEveryStatus() {
        XCTAssertEqual(BillingStrings.forLocale(Locale(identifier: "de_AT")).buyButton, "Zahlungspflichtig abonnieren")
        XCTAssertEqual(BillingStrings.forLocale(Locale(identifier: "fr_FR")).buyButton, "Subscribe and pay")
        let statuses: [EntitlementStatus] = [.none, .trialing, .active, .pastDue, .incomplete, .unpaid, .canceled, .paused, .unknown("x")]
        for strings in [BillingStrings.english, .german] {
            for status in statuses { XCTAssertFalse(strings.statusText(status).isEmpty) }
        }
    }

    func testThePayButtonAlwaysStatesThePaymentObligation() {
        // § 312j BGB: the order button must make clear that the order creates an obligation to pay.
        XCTAssertTrue(BillingStrings.german.buyButton.localizedCaseInsensitiveContains("zahlungspflichtig"))
        XCTAssertTrue(BillingStrings.german.buyButtonWithTrial.localizedCaseInsensitiveContains("zahlungspflichtig"))
    }

    func testPeriodAndTrialWording() {
        let monthly = Plan(id: "m", name: "P", interval: .month, currency: "eur", unitAmount: 999, trialDays: 7)
        let yearly = Plan(id: "y", name: "P", interval: .year, currency: "eur", unitAmount: 7999)
        XCTAssertEqual(BillingStrings.english.period(of: monthly), "per month")
        XCTAssertEqual(BillingStrings.german.period(of: yearly), "pro Jahr")
        XCTAssertEqual(BillingStrings.english.trialLine(7, "€9.99", "per month"), "Free for 7 days, then €9.99 per month.")
    }

    func testFailuresHaveText() {
        let s = BillingStrings.english
        XCTAssertEqual(s.message(for: .network), s.errorNetwork)
        XCTAssertEqual(s.message(for: .message("Your card was declined.")), "Your card was declined.")
        XCTAssertEqual(s.message(for: .message("")), s.errorGeneric)
    }

    func testStorefrontCodesBecomeTwoLetterCodes() {
        XCTAssertEqual(ISOCountry.alpha2(fromAlpha3: "USA"), "US")
        XCTAssertEqual(ISOCountry.alpha2(fromAlpha3: "deu"), "DE")
        XCTAssertEqual(ISOCountry.alpha2(from: "GBR"), "GB")
        XCTAssertEqual(ISOCountry.alpha2(from: "fr"), "FR")
        XCTAssertNil(ISOCountry.alpha2(from: nil))
        XCTAssertNil(ISOCountry.alpha2(from: ""))
        XCTAssertNil(ISOCountry.alpha2(fromAlpha3: "XXX"))
        XCTAssertEqual(ISOCountry.alpha3ToAlpha2.count, 249)
        XCTAssertEqual(Set(ISOCountry.alpha3ToAlpha2.values).count, 249, "two-letter codes are unique")
        XCTAssertTrue(ISOCountry.alpha3ToAlpha2.allSatisfy { $0.key.count == 3 && $0.value.count == 2 })
    }
}
