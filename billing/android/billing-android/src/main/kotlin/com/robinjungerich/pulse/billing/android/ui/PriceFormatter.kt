// PriceFormatter.kt
// Prices are never hard-coded in the app: the server reports the amount in minor units and the currency, and this
// formats them for the user's locale.

package com.robinjungerich.pulse.billing.android.ui

import com.robinjungerich.pulse.billing.Plan
import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

object PriceFormatter {

    /**
     * [unitAmount] minor units of [currencyCode] as a price: 999 eur is "€9.99" or "9,99 €", 999 jpy is "¥999". The
     * number of decimals is the currency's default fraction digits.
     */
    fun format(unitAmount: Long, currencyCode: String, locale: Locale): String {
        val currency = try {
            Currency.getInstance(currencyCode.uppercase(Locale.ROOT))
        } catch (_: IllegalArgumentException) {
            return "${NumberFormat.getNumberInstance(locale).format(unitAmount)} ${currencyCode.uppercase(Locale.ROOT)}"
        }
        // Pseudo-currencies report -1.
        val digits = currency.defaultFractionDigits.coerceAtLeast(0)
        val format = NumberFormat.getCurrencyInstance(locale).apply {
            this.currency = currency
            minimumFractionDigits = digits
            maximumFractionDigits = digits
        }
        return format.format(BigDecimal.valueOf(unitAmount, digits))
    }

    fun format(plan: Plan, locale: Locale): String = format(plan.unitAmount, plan.currency, locale)
}
