// BillingError.kt
// Everything BillingApi can throw. Messages never contain tokens, client secrets or ephemeral keys.

package com.robinjungerich.pulse.billing

import java.io.IOException

sealed class BillingError(cause: Throwable? = null) : Exception(cause) {

    /**
     * The server answered with a non-2xx status. [code] is the contract's error code ([ErrorCode.UNKNOWN] when the
     * body was not the contract's error body); [message] is meant for logs, not for users.
     */
    class Api(
        val code: ErrorCode,
        val status: Int,
        override val message: String,
        cause: Throwable? = null,
    ) : BillingError(cause) {
        val isUnauthorized: Boolean get() = code == ErrorCode.UNAUTHORIZED
    }

    /** The request did not complete: no connection, timeout, TLS failure. */
    class Network(override val cause: IOException) : BillingError(cause) {
        override val message: String get() = "Network error: ${cause::class.java.simpleName}"
    }

    /** A 2xx answer that is not the contract's response body. */
    class Decoding(override val cause: Throwable) : BillingError(cause) {
        override val message: String get() = "Unreadable response: ${cause::class.java.simpleName}"
    }
}
