package com.robinjungerich.pulse.billing.android.ui

import com.robinjungerich.pulse.billing.testing.plan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

class PriceFormatterTest {

    /** Formats differ in the space they use between number and symbol; compare with a plain space. */
    private fun format(amount: Long, currency: String, locale: Locale) =
        PriceFormatter.format(amount, currency, locale).replace('\u00a0', ' ').replace('\u202f', ' ')

    @Test
    fun twoDecimalCurrencyUsesMinorUnits() {
        assertEquals("€9.99", format(999, "eur", Locale.US))
        assertEquals("€79.99", format(7999, "eur", Locale.US))
        assertEquals("€0.05", format(5, "eur", Locale.US))
        assertEquals("€0.00", format(0, "eur", Locale.US))
    }

    @Test
    fun theLocaleDecidesSeparatorsAndSymbolPosition() {
        assertEquals("9,99 €", format(999, "eur", Locale.GERMANY))
        assertEquals("1.234,50 €", format(123450, "eur", Locale.GERMANY))
        assertEquals("€1,234.50", format(123450, "eur", Locale.US))
    }

    @Test
    fun aZeroDecimalCurrencyHasNoFractionDigits() {
        val price = format(999, "jpy", Locale.US)
        assertTrue(price, price.endsWith("999"))
        assertFalse(price, price.contains('.'))
        assertTrue(format(1_000_000, "jpy", Locale.US).endsWith("1,000,000"))
    }

    @Test
    fun aThreeDecimalCurrencyUsesThreeFractionDigits() {
        val price = format(1234, "kwd", Locale.US)
        assertTrue(price, price.endsWith("1.234"))
    }

    @Test
    fun theCurrencyCodeIsCaseInsensitive() {
        assertEquals(format(999, "EUR", Locale.US), format(999, "eur", Locale.US))
    }

    @Test
    fun anUnknownCurrencyKeepsTheNumberAndTheCode() {
        assertEquals("999 XYZ", format(999, "xyz", Locale.US))
    }

    @Test
    fun aPlanIsFormattedFromItsAmountAndCurrency() {
        assertEquals("€9.99", PriceFormatter.format(plan(unitAmount = 999, currency = "eur"), Locale.US))
    }
}
