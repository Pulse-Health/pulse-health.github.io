// BillingConfig.kt
// What the host app supplies. The module depends on neither Clerk nor the host's theme.

package com.robinjungerich.pulse.billing.android

import com.robinjungerich.pulse.billing.BillingStrings
import com.robinjungerich.pulse.billing.SessionTokenProvider
import okhttp3.OkHttpClient
import java.util.Locale

/** Where the billing UI sends the user. */
data class BillingLinks(
    val termsUrl: String,
    val privacyUrl: String,
    /**
     * A URL scheme or App Link of the host app that brings the user back from the Stripe portal. It must be in the
     * server's `BILLING_PORTAL_RETURN_URLS`.
     */
    val portalReturnUrl: String,
)

class BillingConfig(
    /** Origin of the billing API, e.g. `https://billing.example.com`. */
    val baseUrl: String,
    /** Returns the user's current Clerk session token. */
    val sessionTokens: SessionTokenProvider,
    /** The signed-in user (Clerk user id); the offline entitlement cache is kept per user. */
    val userId: String,
    val links: BillingLinks,
    /** The Play country if known, otherwise the device region. Advisory: the server decides. */
    val country: String? = Locale.getDefault().country.takeIf { it.length == 2 },
    val strings: BillingStrings = BillingStrings.forLocale(Locale.getDefault()),
    /** Google Pay in the payment sheet is off unless the host passes this. */
    val googlePay: GooglePayConfig? = null,
    /** Where the Stripe SDK returns to after a payment method that redirects (3-D Secure, bank apps), if the host has such a link. */
    val stripeReturnUrl: String? = null,
    val client: OkHttpClient = OkHttpClient(),
)
