// BillingApi.kt
// One suspend function per operation of billing/contract/openapi.yaml.

package com.robinjungerich.pulse.billing

import okhttp3.OkHttpClient

/**
 * The host's seam to Clerk. Called for every request and once more after a 401, so it must return a token that is
 * valid now (Clerk Android: `Clerk.session?.fetchToken()`), and may throw when nobody is signed in.
 */
fun interface SessionTokenProvider {
    suspend fun sessionToken(): String
}

interface BillingApi {
    /** What can this user buy here? [country] is advisory (Play country if known, else the device region). */
    suspend fun offers(country: String?): Offers

    suspend fun entitlement(): EntitlementResponse

    /** Starts or resumes a subscription. Use a fresh [idempotencyKey] per user tap; retries of one tap reuse it. */
    suspend fun startSubscription(
        planId: String,
        country: String?,
        billingCountry: String?,
        consent: WithdrawalConsent?,
        idempotencyKey: String,
    ): CreateSubscriptionResponse

    /** Re-reads the subscriptions from Stripe; call it after the PaymentSheet reported success. */
    suspend fun sync(): EntitlementResponse

    /** Cancels at the end of the paid period. */
    suspend fun cancel(): EntitlementResponse

    /** Undoes a pending cancellation. */
    suspend fun resume(): EntitlementResponse

    /** A Stripe Customer Portal link. [returnUrl] must be on the server's allow-list. */
    suspend fun portalUrl(returnUrl: String): String

    /** Closes the billing account; call it when the user deletes their Pulse account. */
    suspend fun deleteAccount()
}

/**
 * The production [BillingApi].
 *
 * @param baseUrl origin of the billing API, e.g. `https://billing.example.com`.
 * @param client inject the host's client to share its connection pool and TLS settings. Do not add an interceptor
 *   that logs headers or bodies to it: bearer tokens, client secrets and ephemeral keys pass through.
 */
fun BillingApi(
    baseUrl: String,
    sessionTokens: SessionTokenProvider,
    client: OkHttpClient = OkHttpClient(),
): BillingApi = OkHttpBillingApi(baseUrl, sessionTokens, client)
