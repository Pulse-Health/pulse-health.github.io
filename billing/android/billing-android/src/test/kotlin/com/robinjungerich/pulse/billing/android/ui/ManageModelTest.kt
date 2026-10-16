package com.robinjungerich.pulse.billing.android.ui

import com.robinjungerich.pulse.billing.BillingError
import com.robinjungerich.pulse.billing.BillingStrings
import com.robinjungerich.pulse.billing.Entitlement
import com.robinjungerich.pulse.billing.EntitlementSource
import com.robinjungerich.pulse.billing.EntitlementStatus
import com.robinjungerich.pulse.billing.ErrorCode
import com.robinjungerich.pulse.billing.android.EntitlementUiState
import com.robinjungerich.pulse.billing.testing.NOW
import com.robinjungerich.pulse.billing.testing.premiumEntitlement
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.time.Instant
import java.time.ZoneOffset
import java.util.Locale

class ManageModelTest {

    private val en = BillingStrings.forLocale(Locale.US)
    private val periodEnd = Instant.parse("2026-11-16T10:00:00Z")

    private fun loaded(state: EntitlementUiState) = manageModel(state, en, ZoneOffset.UTC) as ManageModel.Loaded

    private fun state(entitlement: Entitlement?, offline: Boolean = false, error: BillingError? = null) = EntitlementUiState(
        entitlement = entitlement,
        confirmedAt = NOW.takeIf { entitlement != null },
        isPremium = entitlement?.premium == true,
        isOffline = offline,
        error = error,
    )

    @Test
    fun anActiveSubscriptionShowsTheRenewalDateAndTheActions() {
        val model = loaded(state(premiumEntitlement(until = periodEnd).copy(premiumUntil = periodEnd.plusSeconds(86_400))))

        assertEquals("Active", model.status)
        assertEquals(listOf("Renews on November 16, 2026"), model.details)
        assertTrue(model.canCancel)
        assertFalse(model.canResume)
        assertTrue(model.canManagePayments)
    }

    @Test
    fun aSubscriptionThatEndsAtPeriodEndOffersToUndoTheCancellation() {
        val model = loaded(state(premiumEntitlement(until = periodEnd).copy(cancelAtPeriodEnd = true)))

        assertEquals(listOf("Premium ends on November 16, 2026"), model.details)
        assertFalse(model.canCancel)
        assertTrue(model.canResume)
        assertEquals("November 16, 2026", model.endDate)
    }

    @Test
    fun aTrialShowsWhenItEnds() {
        val trial = premiumEntitlement(until = periodEnd).copy(status = EntitlementStatus.TRIALING, trialEnd = periodEnd)

        val model = loaded(state(trial))

        assertEquals("Free trial", model.status)
        assertEquals(listOf("Free trial ends on November 16, 2026"), model.details)
        assertTrue(model.canCancel)
    }

    @Test
    fun pastDueExplainsWhatToDo() {
        val model = loaded(state(premiumEntitlement(until = periodEnd).copy(status = EntitlementStatus.PAST_DUE)))

        assertEquals("Payment overdue", model.status)
        assertEquals(listOf(en.pastDueNote), model.notes)
        assertTrue(model.canManagePayments)
    }

    @Test
    fun noSubscriptionOffersNothing() {
        val model = loaded(state(Entitlement.NONE))

        assertEquals("No subscription", model.status)
        assertTrue(model.details.isEmpty())
        assertFalse(model.canCancel || model.canResume || model.canManagePayments)
    }

    @Test
    fun aCanceledSubscriptionOnlyOffersThePortal() {
        val canceled = Entitlement(
            premium = false,
            status = EntitlementStatus.CANCELED,
            planId = "premium_monthly",
            source = EntitlementSource.STRIPE,
            cancelAtPeriodEnd = false,
        )

        val model = loaded(state(canceled))

        assertEquals("Canceled", model.status)
        assertFalse(model.canCancel || model.canResume)
        assertTrue(model.canManagePayments)
    }

    @Test
    fun premiumFromAnAccessCodeHasNothingToCancel() {
        val code = Entitlement(
            premium = true,
            status = EntitlementStatus.NONE,
            source = EntitlementSource.CODE,
            cancelAtPeriodEnd = false,
            premiumUntil = periodEnd,
        )

        val model = loaded(state(code))

        assertEquals("Active", model.status)
        assertEquals(listOf(en.premiumWithoutSubscription), model.details)
        assertFalse(model.canCancel || model.canResume || model.canManagePayments)
    }

    @Test
    fun premiumFromAnUnknownSourceIsStillPremiumAndHasNoStripeActions() {
        val future = premiumEntitlement().copy(source = EntitlementSource.UNKNOWN, status = EntitlementStatus.UNKNOWN)

        val model = loaded(state(future))

        assertEquals("Active", model.status)
        assertFalse(model.canCancel || model.canResume || model.canManagePayments)
    }

    @Test
    fun offlineShowsTheCachedAnswerWithItsDateAndDisablesTheActions() {
        val model = loaded(state(premiumEntitlement(until = periodEnd), offline = true, error = BillingError.Network(IOException())))

        assertEquals("Active", model.status)
        assertEquals(listOf("You are offline. Showing the status from October 16, 2026."), model.notes)
        assertNull(model.error)
        assertFalse(model.canCancel || model.canResume || model.canManagePayments)
    }

    @Test
    fun aServerErrorOverTheCachedAnswerIsShown() {
        val model = loaded(state(premiumEntitlement(), error = BillingError.Api(ErrorCode.RATE_LIMITED, 429, "slow")))

        assertEquals(en.errorRateLimited, model.error)
    }

    @Test
    fun withoutAnAnswerTheScreenLoadsOrFails() {
        assertEquals(ManageModel.Loading, manageModel(EntitlementUiState(isLoading = true), en))
        assertEquals(ManageModel.Loading, manageModel(EntitlementUiState(), en))
        assertEquals(
            ManageModel.LoadFailed(en.errorNetwork),
            manageModel(EntitlementUiState(error = BillingError.Network(IOException()), isOffline = true), en),
        )
    }

    @Test
    fun theCancelConfirmationNamesTheDatePremiumEnds() {
        val model = loaded(state(premiumEntitlement(until = periodEnd)))

        assertEquals("Premium stays active until November 16, 2026. After that you will not be charged again.", en.cancelConfirmBody(model.endDate))
    }
}
