package com.robinjungerich.pulse.billing.android.ui

import com.robinjungerich.pulse.billing.BillingStrings
import com.robinjungerich.pulse.billing.PlanInterval
import com.robinjungerich.pulse.billing.PurchaseFailure
import com.robinjungerich.pulse.billing.PurchaseState
import com.robinjungerich.pulse.billing.TaxBehavior
import com.robinjungerich.pulse.billing.UnavailableReason
import com.robinjungerich.pulse.billing.testing.offers
import com.robinjungerich.pulse.billing.testing.plan
import com.robinjungerich.pulse.billing.testing.premiumEntitlement
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

class PaywallModelTest {

    private val en = BillingStrings.forLocale(Locale.US)
    private val de = BillingStrings.forLocale(Locale.GERMANY)

    private fun plans(model: PaywallModel) = model as PaywallModel.Plans

    @Test
    fun readyOffersShowThePlansWithServerPrices() {
        val model = plans(paywallModel(PurchaseState.Ready(offers()), offers(), en))

        assertEquals(listOf("premium_monthly", "premium_yearly"), model.items.map { it.id })
        assertEquals(listOf("Monthly", "Yearly"), model.items.map { it.title })
        assertEquals(listOf("€9.99 / month", "€79.99 / year"), model.items.map { it.priceLine })
        assertTrue(model.requiresConsent)
        assertFalse(model.busy)
        assertNull(model.banner)
        assertNull(model.progress)
    }

    @Test
    fun theGermanPaywallFormatsPricesForGermany() {
        val model = plans(paywallModel(PurchaseState.Ready(offers()), offers(), de))

        assertEquals("9,99 € / Monat", model.items[0].priceLine.replace('\u00a0', ' ').replace('\u202f', ' '))
    }

    @Test
    fun aZeroDecimalCurrencyIsShownWithoutDecimals() {
        val yen = offers(plans = listOf(plan(currency = "jpy", unitAmount = 500)))

        val model = plans(paywallModel(PurchaseState.Ready(yen), yen, en))

        val price = model.items.single().priceLine
        assertTrue(price, price.endsWith("500 / month"))
        assertFalse(price, price.contains('.'))
    }

    @Test
    fun aThreeDecimalCurrencyIsShownWithThreeDecimals() {
        val dinar = offers(plans = listOf(plan(currency = "kwd", unitAmount = 1500)))

        val model = plans(paywallModel(PurchaseState.Ready(dinar), dinar, en))

        assertTrue(model.items.single().priceLine, model.items.single().priceLine.endsWith("1.500 / month"))
    }

    @Test
    fun aTrialShowsTheBadgeAndTheTrialNote() {
        val item = planItem(plan(trialDays = 7), en)

        assertEquals("7 days free", item.trialBadge)
        assertTrue(item.notes.first().startsWith("Free for the first 7 days, then €9.99 / month"))
    }

    @Test
    fun noTrialMeansNoTrialText() {
        val item = planItem(plan(trialDays = 0), en)

        assertNull(item.trialBadge)
        assertFalse(item.notes.any { it.contains("Free for the first") })
    }

    @Test
    fun theTaxNoteFollowsTheTaxBehavior() {
        assertTrue(planItem(plan(taxBehavior = TaxBehavior.INCLUSIVE), en).notes.contains(en.taxInclusiveNote))
        assertTrue(planItem(plan(taxBehavior = TaxBehavior.EXCLUSIVE), en).notes.contains(en.taxExclusiveNote))
        for (behavior in listOf(TaxBehavior.UNSPECIFIED, TaxBehavior.UNKNOWN)) {
            val notes = planItem(plan(taxBehavior = behavior), en).notes
            assertFalse(notes.contains(en.taxInclusiveNote) || notes.contains(en.taxExclusiveNote))
        }
    }

    @Test
    fun everyPlanStatesAutoRenewalAndCancellation() {
        val item = planItem(plan("premium_yearly", PlanInterval.YEAR, unitAmount = 7999), en)

        assertTrue(item.notes.last().contains("Renews automatically at €79.99 / year until you cancel"))
        assertTrue(item.notes.last().contains("cancel at any time"))
    }

    @Test
    fun anUnavailableRegionShowsOnlyANeutralLine() {
        val unavailable = offers(available = false, reason = UnavailableReason.REGION_NOT_SUPPORTED, plans = emptyList())

        val fromOffers = paywallModel(PurchaseState.Unavailable(UnavailableReason.REGION_NOT_SUPPORTED), unavailable, en)

        assertEquals(PaywallModel.Unavailable(en.unavailable), fromOffers)
    }

    @Test
    fun unavailableOffersThatReachThePaywallInAnyStateShowTheNeutralLine() {
        val unavailable = offers(available = false, reason = UnavailableReason.PLATFORM_NOT_SUPPORTED, plans = emptyList())

        assertEquals(PaywallModel.Unavailable(en.unavailable), paywallModel(PurchaseState.Idle, unavailable, en))
        assertEquals(PaywallModel.Unavailable(en.unavailable), paywallModel(PurchaseState.Canceled, unavailable, en))
    }

    @Test
    fun anAvailablePurchaseWithoutPlansIsNeutralToo() {
        val noPlans = offers(available = true, plans = emptyList())

        assertEquals(PaywallModel.Unavailable(en.unavailable), paywallModel(PurchaseState.Idle, noPlans, en))
    }

    @Test
    fun alreadySubscribedSaysSo() {
        val model = paywallModel(PurchaseState.Unavailable(UnavailableReason.ALREADY_SUBSCRIBED), null, en)

        assertEquals(PaywallModel.Unavailable(en.alreadySubscribed), model)
    }

    @Test
    fun beforeTheOffersArriveThePaywallLoads() {
        assertEquals(PaywallModel.Loading, paywallModel(PurchaseState.Idle, null, en))
        assertEquals(PaywallModel.Loading, paywallModel(PurchaseState.LoadingOffers, null, en))
    }

    @Test
    fun offersThatCouldNotBeLoadedOfferARetry() {
        val model = paywallModel(PurchaseState.Failed(PurchaseFailure.Network), null, en)

        assertEquals(PaywallModel.LoadFailed(en.errorNetwork), model)
    }

    @Test
    fun whileAFlowIsInFlightTheBuyingIsDisabledAndProgressIsShown() {
        val expectations = mapOf(
            PurchaseState.Preparing to en.preparing,
            PurchaseState.AwaitingPayment to en.awaitingPayment,
            PurchaseState.Confirming to en.confirming,
            PurchaseState.LoadingOffers to en.loadingOffers,
        )
        for ((state, progress) in expectations) {
            val model = plans(paywallModel(state, offers(), en))
            assertTrue(state.toString(), model.busy)
            assertEquals(progress, model.progress)
        }
    }

    @Test
    fun aCanceledSheetKeepsThePlansAndSaysNothingWasCharged() {
        val model = plans(paywallModel(PurchaseState.Canceled, offers(), en))

        assertEquals(en.canceled, model.banner)
        assertFalse(model.bannerIsError)
        assertFalse(model.busy)
    }

    @Test
    fun aFailureKeepsThePlansAndShowsTheMessage() {
        val model = plans(paywallModel(PurchaseState.Failed(PurchaseFailure.Payment("Card declined")), offers(), en))

        assertEquals("Card declined", model.banner)
        assertTrue(model.bannerIsError)
    }

    @Test
    fun aMissingConsentFailureKeepsTheConsentCheckboxVisible() {
        val model = plans(paywallModel(PurchaseState.Failed(PurchaseFailure.ConsentRequired), offers(requiresWithdrawalConsent = true), en))

        assertTrue(model.requiresConsent)
        assertEquals(en.consentRequiredHint, model.banner)
    }

    @Test
    fun noConsentCheckboxWhenTheServerDoesNotRequireIt() {
        val model = plans(paywallModel(PurchaseState.Ready(offers()), offers(requiresWithdrawalConsent = false), en))

        assertFalse(model.requiresConsent)
    }

    @Test
    fun aFinishedPurchaseShowsOnlyTheResult() {
        assertEquals(PaywallModel.Finished(en.activated), paywallModel(PurchaseState.Activated(premiumEntitlement()), offers(), en))
        assertEquals(PaywallModel.Finished(en.pendingActivation), paywallModel(PurchaseState.PendingActivation, offers(), en))
    }
}
