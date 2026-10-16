#if os(iOS)
import UIKit
import PulseBillingCore
#if canImport(StripePaymentSheet)
import StripePaymentSheet

/// Shows Stripe's PaymentSheet for one `PaymentSession` and reports how it ended.
///
/// The host app must forward the URLs it is opened with to `PulseBilling.handle(url:)` (for 3-D Secure and bank redirects) and
/// register the scheme of `Options.returnURL` in its Info.plist.
public struct StripePaymentSheetPresenter: PaymentSheetPresenting {
    public struct Options: Sendable {
        /// URL of the app that Stripe opens after a redirect-based authentication, for example `pulse://stripe-redirect`.
        public var returnURL: String
        /// Apple Pay is offered only when a merchant id is given (it also needs the Apple Pay capability in the app).
        public var applePayMerchantID: String?
        public var applePayCountryCode: String
        /// SEPA debit and other methods that confirm later.
        public var allowsDelayedPaymentMethods: Bool

        public init(returnURL: String, applePayMerchantID: String? = nil, applePayCountryCode: String = "DE", allowsDelayedPaymentMethods: Bool = true) {
            self.returnURL = returnURL
            self.applePayMerchantID = applePayMerchantID
            self.applePayCountryCode = applePayCountryCode
            self.allowsDelayedPaymentMethods = allowsDelayedPaymentMethods
        }
    }

    private let options: Options

    public init(options: Options) {
        self.options = options
    }

    public func present(_ session: PaymentSession) async -> PaymentSheetOutcome {
        await Self.run(session, options: options)
    }

    @MainActor
    private static func run(_ session: PaymentSession, options: Options) async -> PaymentSheetOutcome {
        // The key comes with every session, so nothing has to be configured at app start.
        STPAPIClient.shared.publishableKey = session.publishableKey

        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = session.merchantDisplayName
        configuration.customer = PaymentSheet.CustomerConfiguration(id: session.customerID, ephemeralKeySecret: session.ephemeralKeySecret)
        configuration.returnURL = options.returnURL
        configuration.allowsDelayedPaymentMethods = options.allowsDelayedPaymentMethods
        if let merchantID = options.applePayMerchantID {
            configuration.applePay = PaymentSheet.ApplePayConfiguration(merchantId: merchantID, merchantCountryCode: options.applePayCountryCode)
        }

        let sheet: PaymentSheet
        switch session.intent.kind {
        case .setup:
            sheet = PaymentSheet(setupIntentClientSecret: session.intent.clientSecret, configuration: configuration)
        default:
            sheet = PaymentSheet(paymentIntentClientSecret: session.intent.clientSecret, configuration: configuration)
        }

        guard let presenter = topViewController() else {
            return .failed("There is no window to show the payment sheet in.")
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<PaymentSheetOutcome, Never>) in
            sheet.present(from: presenter) { result in
                withExtendedLifetime(sheet) {}
                switch result {
                case .completed:
                    continuation.resume(returning: .completed)
                case .canceled:
                    continuation.resume(returning: .canceled)
                case .failed(let error):
                    continuation.resume(returning: .failed(error.localizedDescription))
                }
            }
        }
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
#endif
#endif
