import Foundation

/// Formats prices and periods for the paywall. Prices always come from the server (`Plan.unitAmount`, minor units).
public enum BillingFormat {
    /// How many decimals Stripe's minor unit has for a currency: 0 for the zero-decimal currencies, 3 for the three-decimal ones,
    /// 2 for everything else (https://docs.stripe.com/currencies#minor-units). Stripe's table, not the platform's, because the
    /// server's `unitAmount` follows it.
    public static func minorUnitDigits(currency: String) -> Int {
        let code = currency.uppercased()
        if zeroDecimal.contains(code) { return 0 }
        if threeDecimal.contains(code) { return 3 }
        return 2
    }

    private static let zeroDecimal: Set<String> = ["BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"]
    private static let threeDecimal: Set<String> = ["BHD", "JOD", "KWD", "OMR", "TND"]

    /// "9,99 €" / "$9.99" / "¥500": the amount in the currency's own number of decimals, in the given locale.
    public static func price(unitAmount: Int, currency: String, locale: Locale = .current) -> String {
        let digits = minorUnitDigits(currency: currency)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currency.uppercased()
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        let divisor = (0..<digits).reduce(Decimal(1)) { result, _ in result * 10 }
        let amount = Decimal(unitAmount) / divisor
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(unitAmount) \(currency.uppercased())"
    }

    public static func price(of plan: Plan, locale: Locale = .current) -> String {
        price(unitAmount: plan.unitAmount, currency: plan.currency, locale: locale)
    }
}
