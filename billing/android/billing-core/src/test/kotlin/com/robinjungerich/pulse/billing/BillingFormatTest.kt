package com.robinjungerich.pulse.billing

import com.robinjungerich.pulse.billing.testing.plan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

class BillingFormatTest {

    /** Locales differ in the space between number and symbol; compare with a plain space. */
    private fun price(amount: Long, currency: String, locale: Locale) =
        BillingFormat.price(amount, currency, locale).replace(' ', ' ').replace(' ', ' ')

    private val germany = Locale.GERMANY

    @Test
    fun theMinorUnitTableIsStripes() {
        val zero = listOf("BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF")
        val three = listOf("BHD", "JOD", "KWD", "OMR", "TND")
        zero.forEach { assertEquals(it, 0, BillingFormat.minorUnitDigits(it)) }
        three.forEach { assertEquals(it, 3, BillingFormat.minorUnitDigits(it)) }
        listOf("EUR", "USD", "GBP", "CHF", "ISK", "HUF", "TWD", "XYZ").forEach { assertEquals(it, 2, BillingFormat.minorUnitDigits(it)) }
    }

    @Test
    fun theCurrencyCodeIsCaseInsensitive() {
        assertEquals(0, BillingFormat.minorUnitDigits("jpy"))
        assertEquals(3, BillingFormat.minorUnitDigits("kwd"))
        assertEquals(price(999, "EUR", Locale.US), price(999, "eur", Locale.US))
    }

    @Test
    fun euroInGermanyUsesTwoDecimalsAndTheGermanFormat() {
        assertEquals("9,99 €", price(999, "eur", germany))
        assertEquals("79,99 €", price(7999, "eur", germany))
        assertEquals("1.234,50 €", price(123450, "eur", germany))
    }

    @Test
    fun euroInTheUsUsesTheUsFormat() {
        assertEquals("€9.99", price(999, "eur", Locale.US))
        assertEquals("€0.05", price(5, "eur", Locale.US))
        assertEquals("€0.00", price(0, "eur", Locale.US))
        assertEquals("$9.99", price(999, "usd", Locale.US))
    }

    @Test
    fun aZeroDecimalCurrencyShowsTheAmountAsIs() {
        val yen = price(500, "jpy", Locale.US)
        assertTrue(yen, yen.endsWith("500"))
        assertTrue(yen, !yen.contains('.') && !yen.contains(','))
        assertTrue(price(1_000_000, "jpy", Locale.US).endsWith("1,000,000"))
        assertTrue(price(5000, "krw", Locale.US).endsWith("5,000"))
    }

    @Test
    fun aThreeDecimalCurrencyShowsThreeDecimals() {
        val dinar = price(1500, "kwd", Locale.US)
        assertTrue(dinar, dinar.endsWith("1.500"))
        assertTrue(price(1500, "kwd", germany).contains("1,500"))
        assertTrue(price(7, "bhd", Locale.US).endsWith("0.007"))
    }

    @Test
    fun aCurrencyJavaTreatsDifferentlyFollowsStripesTable() {
        // java.util.Currency says ISK has no decimals; Stripe's minor unit for it has two.
        val krona = price(50_000, "isk", Locale.US)
        assertTrue(krona, krona.endsWith("500.00"))
    }

    @Test
    fun anUnknownCurrencyKeepsTheCodeAndUsesTwoDecimals() {
        assertEquals("9.99 XYZ", price(999, "xyz", Locale.US))
    }

    @Test
    fun aPlanIsFormattedFromItsAmountAndCurrency() {
        assertEquals("9,99 €", BillingFormat.price(plan(unitAmount = 999, currency = "eur"), germany).replace(' ', ' '))
        assertTrue(BillingFormat.price(plan(unitAmount = 500, currency = "jpy"), Locale.US).endsWith("500"))
    }
}
