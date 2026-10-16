#if os(iOS)
import SwiftUI
import StoreKit
import PulseBillingCore
#if canImport(StripePaymentSheet)
import StripePaymentSheet
#endif

/// Entry points for the host app.
public enum PulseBilling {
    /// The country the user shops in, as a two-letter code: the App Store storefront. Nil when StoreKit does not know it, in
    /// which case the server does not offer a purchase (it fails closed).
    public static func storefrontCountry() async -> String? {
        ISOCountry.alpha2(from: await Storefront.current?.countryCode)
    }

    #if canImport(StripePaymentSheet)
    /// Builds everything for one signed-in user: API client, purchase coordinator with the Stripe sheet, and the view model for
    /// `PaywallView` and `ManageSubscriptionView`.
    ///
    /// - Parameters:
    ///   - userID: the Clerk user id (only used to key the offline cache).
    ///   - tokens: returns the current Clerk session token.
    ///   - stripeReturnURL: an URL of the app for redirect-based payment methods; its scheme must be registered in Info.plist.
    ///   - countryProvider: where the country comes from; the App Store storefront by default. Override in debug builds only.
    @MainActor
    public static func makeViewModel(
        configuration: BillingConfiguration,
        userID: String,
        tokens: SessionTokenProviding,
        links: BillingLinks,
        stripeReturnURL: String,
        applePayMerchantID: String? = nil,
        strings: BillingStrings = .forLocale(),
        cache: EntitlementCache = UserDefaultsEntitlementCache(),
        countryProvider: @escaping @Sendable () async -> String? = { await PulseBilling.storefrontCountry() }
    ) -> BillingViewModel {
        let api = BillingAPI(configuration: configuration, tokens: tokens)
        let presenter = StripePaymentSheetPresenter(options: .init(returnURL: stripeReturnURL, applePayMerchantID: applePayMerchantID))
        let coordinator = PurchaseCoordinator(userID: userID, api: api, presenter: presenter, cache: cache, country: countryProvider)
        return BillingViewModel(coordinator: coordinator, links: links, strings: strings)
    }

    /// Call from `onOpenURL` / the scene delegate for every URL the app is opened with. Returns true if Stripe consumed it.
    @discardableResult
    public static func handle(url: URL) -> Bool {
        StripeAPI.handleURLCallback(with: url)
    }
    #endif
}
#endif
