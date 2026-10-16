package com.robinjungerich.pulse.billing

import com.robinjungerich.pulse.billing.testing.plan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.time.Instant
import java.time.ZoneOffset
import java.util.Locale

class BillingStringsTest {

    private val en = BillingStrings.forLocale(Locale.ENGLISH)
    private val de = BillingStrings.forLocale(Locale.GERMANY)
    private val monthly = plan()
    private val yearly = plan("premium_yearly", PlanInterval.YEAR, unitAmount = 7999)
    private val quarterly = plan("premium_quarterly", PlanInterval.MONTH, intervalCount = 3)

    @Test
    fun theLocaleSelectsTheLanguage() {
        assertTrue(BillingStrings.forLocale(Locale.GERMANY) is GermanBillingStrings)
        assertTrue(BillingStrings.forLocale(Locale.forLanguageTag("de-AT")) is GermanBillingStrings)
        assertTrue(BillingStrings.forLocale(Locale.US) is EnglishBillingStrings)
        assertTrue(BillingStrings.forLocale(Locale.FRANCE) is EnglishBillingStrings)
    }

    @Test
    fun theStringsKnowTheLanguageOfTheTextTheBuyerSees() {
        assertEquals("de-DE", de.locale.toLanguageTag())
        assertEquals("en-US", BillingStrings.forLocale(Locale.US).locale.toLanguageTag())
        assertEquals("en", BillingStrings.forLocale(Locale.FRANCE).locale.toLanguageTag())
    }

    @Test
    fun theBuyButtonStatesTheObligationToPay() {
        assertEquals("Zahlungspflichtig abonnieren", de.buyButton)
        assertTrue(en.buyButton.contains("obligation to pay"))
    }

    @Test
    fun theConsentMentionsTheWithdrawalRight() {
        assertTrue(de.withdrawalConsent.contains("Widerrufsrecht"))
        assertTrue(en.withdrawalConsent.contains("right of withdrawal"))
    }

    @Test
    fun planTitlesAndPriceLines() {
        assertEquals("Monthly", en.planTitle(monthly))
        assertEquals("Yearly", en.planTitle(yearly))
        assertEquals("Every 3 months", en.planTitle(quarterly))
        assertEquals("Monatlich", de.planTitle(monthly))
        assertEquals("Jährlich", de.planTitle(yearly))
        assertEquals("Alle 3 Monate", de.planTitle(quarterly))

        assertEquals("€9.99 / month", en.priceLine("€9.99", monthly))
        assertEquals("€79.99 / year", en.priceLine("€79.99", yearly))
        assertEquals("€27.00 every 3 months", en.priceLine("€27.00", quarterly))
        assertEquals("9,99 € / Monat", de.priceLine("9,99 €", monthly))
        assertEquals("27,00 € alle 3 Monate", de.priceLine("27,00 €", quarterly))
    }

    @Test
    fun trialTextsPluralise() {
        assertEquals("7 days free", en.trialBadge(7))
        assertEquals("1 day free", en.trialBadge(1))
        assertEquals("7 Tage kostenlos", de.trialBadge(7))
        assertEquals("1 Tag kostenlos", de.trialBadge(1))
        assertTrue(en.trialNote(7, "€9.99 / month").contains("then €9.99 / month"))
        assertTrue(de.trialNote(7, "9,99 € / Monat").contains("danach 9,99 € / Monat"))
    }

    @Test
    fun datesAreFormattedForTheLanguage() {
        val instant = Instant.parse("2026-11-16T10:00:00Z")
        assertEquals("November 16, 2026", en.formatDate(instant, ZoneOffset.UTC))
        assertEquals("16. November 2026", de.formatDate(instant, ZoneOffset.UTC))
    }

    @Test
    fun theUnavailableTextIsNeutralAndPointsNowhere() {
        val steering = listOf("http", "www", "web", "browser", "online", "internet", "elsewhere", "anderswo", "store", "link")
        for (strings in listOf(en, de)) {
            for (reason in UnavailableReason.entries + null) {
                val text = strings.unavailableMessage(reason).lowercase()
                for (word in steering) assertFalse("'$text' mentions '$word'", text.contains(word))
            }
        }
        assertEquals(en.unavailable, en.unavailableMessage(UnavailableReason.REGION_NOT_SUPPORTED))
        assertEquals(en.alreadySubscribed, en.unavailableMessage(UnavailableReason.ALREADY_SUBSCRIBED))
    }

    @Test
    fun failuresMapToMessages() {
        assertEquals(en.errorNetwork, en.failureMessage(PurchaseFailure.Network))
        assertEquals(en.consentRequiredHint, en.failureMessage(PurchaseFailure.ConsentRequired))
        assertEquals("Card declined", en.failureMessage(PurchaseFailure.Payment("Card declined")))
        assertEquals(en.errorPaymentFailed, en.failureMessage(PurchaseFailure.Payment(null)))
        assertEquals(en.errorPaymentFailed, en.failureMessage(PurchaseFailure.Payment("  ")))
        assertEquals(en.errorRateLimited, en.failureMessage(PurchaseFailure.Server(ErrorCode.RATE_LIMITED, 429)))
        assertEquals(en.errorUnauthorized, en.failureMessage(PurchaseFailure.Server(ErrorCode.UNAUTHORIZED, 401)))
        assertEquals(en.alreadySubscribed, en.failureMessage(PurchaseFailure.Server(ErrorCode.ALREADY_SUBSCRIBED, 409)))
        assertEquals(en.errorGeneric, en.failureMessage(PurchaseFailure.Server(ErrorCode.STRIPE_ERROR, 502)))
        assertEquals(en.errorGeneric, en.failureMessage(PurchaseFailure.Unexpected))
        assertEquals(de.errorNetwork, de.errorMessage(BillingError.Network(IOException())))
        assertEquals(de.errorGeneric, de.errorMessage(BillingError.Decoding(IllegalStateException())))
        assertEquals(de.errorUnauthorized, de.errorMessage(BillingError.Api(ErrorCode.UNAUTHORIZED, 401, "x")))
    }

    @Test
    fun aHostCanOverrideSingleStringsByDelegation() {
        val custom = object : BillingStrings by en {
            override val errorNetwork = "Offline!"
            override val buyButton = "Buy now"
        }

        assertEquals("Buy now", custom.buyButton)
        assertEquals("Offline!", custom.failureMessage(PurchaseFailure.Network))
        assertEquals("Offline!", custom.errorMessage(BillingError.Network(IOException())))
        assertEquals(en.done, custom.done)
    }

    @Test
    fun everyStringIsFilledInBothLanguages() {
        for (strings in listOf(en, de)) {
            val all = buildList {
                add(strings.paywallTitle); add(strings.choosePlan); add(strings.taxInclusiveNote); add(strings.taxExclusiveNote)
                add(strings.termsLink); add(strings.privacyLink); add(strings.withdrawalConsent); add(strings.consentRequiredHint)
                add(strings.buyButton); add(strings.retry); add(strings.done); add(strings.opensInBrowser)
                add(strings.loadingOffers); add(strings.preparing); add(strings.awaitingPayment); add(strings.confirming)
                add(strings.activated); add(strings.pendingActivation); add(strings.canceled); add(strings.unavailable)
                add(strings.alreadySubscribed); add(strings.manageTitle); add(strings.loadingStatus)
                add(strings.pastDueNote); add(strings.noSubscription); add(strings.premiumWithoutSubscription)
                add(strings.cancelSubscription); add(strings.undoCancellation); add(strings.cancelConfirmTitle)
                add(strings.cancelConfirmKeep); add(strings.managePayments); add(strings.errorNetwork)
                add(strings.errorUnauthorized); add(strings.errorRateLimited); add(strings.errorPaymentFailed); add(strings.errorGeneric)
                add(strings.cancelConfirmBody("16 Nov")); add(strings.cancelConfirmBody(null))
                add(strings.renewsOn("d")); add(strings.endsOn("d")); add(strings.trialEndsOn("d")); add(strings.lastKnownStatus("d"))
                add(strings.renewalNote("p")); add(strings.trialNote(7, "p")); add(strings.trialBadge(3))
                EntitlementStatus.entries.forEach { add(strings.status(it)) }
            }
            assertTrue(all.all { it.isNotBlank() })
        }
        assertTrue(en.buyButton != de.buyButton && en.managePayments != de.managePayments)
    }
}
