// PaymentSheet.kt
// The seam between the purchase flow and the Stripe PaymentSheet, so the flow is testable without Stripe.

package com.robinjungerich.pulse.billing

/** What the Stripe sheet needs, taken from the subscription the server created. */
data class PaymentSession(
    val customerId: String,
    val customerEphemeralKeySecret: String,
    val publishableKey: String,
    val merchantDisplayName: String,
    val intentKind: IntentKind,
    val intentClientSecret: String,
) {
    override fun toString() =
        "PaymentSession(customerId=$customerId, merchantDisplayName=$merchantDisplayName, intentKind=$intentKind, secrets=<redacted>)"
}

sealed interface PaymentSheetOutcome {
    data object Completed : PaymentSheetOutcome
    data object Canceled : PaymentSheetOutcome

    /** [message] is the SDK's description of the failure, already localized by Stripe; null when there is none. */
    data class Failed(val message: String?) : PaymentSheetOutcome
}

fun interface PaymentSheetPresenting {
    /** Shows the sheet and suspends until the user is done with it. Does not throw for payment problems. */
    suspend fun present(session: PaymentSession): PaymentSheetOutcome
}
