// BillingFormat.kt
// Prices are never hard-coded in the app: the server reports the amount in minor units and the currency, and this
// formats them for the user's locale.

package com.robinjungerich.pulse.billing

import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

object BillingFormat {
    private val zeroDecimal = setOf("BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF")
    private val threeDecimal = setOf("BHD", "JOD", "KWD", "OMR", "TND")

    /**
     * How many decimals Stripe's minor unit has for [currency]: 0 for the zero-decimal currencies, 3 for the
     * three-decimal ones, 2 for everything else (https://docs.stripe.com/currencies#minor-units). Stripe's table, not
     * `java.util.Currency`'s, because the server's `unitAmount` follows it. Same table as the iOS package.
     */
    fun minorUnitDigits(currency: String): Int {
        val code = currency.uppercase(Locale.ROOT)
        return when (code) {
            in zeroDecimal -> 0
            in threeDecimal -> 3
            else -> 2
        }
    }

    /** "9,99 €" / "$9.99" / "¥500": [unitAmount] in the currency's own number of decimals, formatted for [locale]. */
    fun price(unitAmount: Long, currency: String, locale: Locale): String {
        val digits = minorUnitDigits(currency)
        val amount = BigDecimal.valueOf(unitAmount, digits)
        val code = currency.uppercase(Locale.ROOT)
        val known = try {
            Currency.getInstance(code)
        } catch (_: IllegalArgumentException) {
            null
        }
        val format = if (known != null) {
            NumberFormat.getCurrencyInstance(locale).apply { this.currency = known }
        } else {
            NumberFormat.getNumberInstance(locale)
        }
        format.minimumFractionDigits = digits
        format.maximumFractionDigits = digits
        val formatted = format.format(amount)
        return if (known != null) formatted else "$formatted $code"
    }

    fun price(plan: Plan, locale: Locale): String = price(plan.unitAmount, plan.currency, locale)
}
