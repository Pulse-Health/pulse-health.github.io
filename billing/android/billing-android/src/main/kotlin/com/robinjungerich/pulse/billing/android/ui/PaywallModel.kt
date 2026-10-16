// PaywallModel.kt
// What the paywall shows for a purchase state, as plain data, so the rules (when is the buy button there, what is said
// when purchase is unavailable) are unit-tested on the JVM and the composable only draws.

package com.robinjungerich.pulse.billing.android.ui

import com.robinjungerich.pulse.billing.BillingStrings
import com.robinjungerich.pulse.billing.Offers
import com.robinjungerich.pulse.billing.Plan
import com.robinjungerich.pulse.billing.PurchaseState
import com.robinjungerich.pulse.billing.TaxBehavior
import com.robinjungerich.pulse.billing.failureMessage
import com.robinjungerich.pulse.billing.isBusy
import com.robinjungerich.pulse.billing.unavailableMessage

internal data class PlanItem(
    val id: String,
    val title: String,
    /** "€9.99 / month". */
    val priceLine: String,
    /** "7 days free", when the plan has a trial. */
    val trialBadge: String?,
    /** The fine print for this plan: trial, tax, auto-renewal. */
    val notes: List<String>,
)

internal sealed interface PaywallModel {
    data object Loading : PaywallModel

    /** The offers could not be loaded. */
    data class LoadFailed(val message: String) : PaywallModel

    /** Neutral line only: no buy button, no link or hint to buy elsewhere. */
    data class Unavailable(val message: String) : PaywallModel

    /** The purchase went through (or is being activated); nothing left to buy. */
    data class Finished(val message: String) : PaywallModel

    data class Plans(
        val items: List<PlanItem>,
        val requiresConsent: Boolean,
        /** A request or the sheet is in flight: the picker and the buy button are disabled. */
        val busy: Boolean,
        /** What is going on while [busy]. */
        val progress: String?,
        /** "Payment canceled" or the failure message of the last attempt. */
        val banner: String?,
        val bannerIsError: Boolean,
    ) : PaywallModel
}

internal fun paywallModel(state: PurchaseState, offers: Offers?, strings: BillingStrings): PaywallModel {
    when (state) {
        is PurchaseState.Activated -> return PaywallModel.Finished(strings.activated)
        PurchaseState.PendingActivation -> return PaywallModel.Finished(strings.pendingActivation)
        is PurchaseState.Unavailable -> return PaywallModel.Unavailable(strings.unavailableMessage(state.reason))
        else -> Unit
    }
    if (offers == null) {
        return if (state is PurchaseState.Failed) PaywallModel.LoadFailed(strings.failureMessage(state.failure)) else PaywallModel.Loading
    }
    if (!offers.purchase.available || offers.plans.isEmpty()) {
        return PaywallModel.Unavailable(strings.unavailableMessage(offers.purchase.reason))
    }
    return PaywallModel.Plans(
        items = offers.plans.map { planItem(it, strings) },
        requiresConsent = offers.requiresWithdrawalConsent,
        busy = state.isBusy,
        progress = when (state) {
            PurchaseState.LoadingOffers -> strings.loadingOffers
            PurchaseState.Preparing -> strings.preparing
            PurchaseState.AwaitingPayment -> strings.awaitingPayment
            PurchaseState.Confirming -> strings.confirming
            else -> null
        },
        banner = when (state) {
            PurchaseState.Canceled -> strings.canceled
            is PurchaseState.Failed -> strings.failureMessage(state.failure)
            else -> null
        },
        bannerIsError = state is PurchaseState.Failed,
    )
}

internal fun planItem(plan: Plan, strings: BillingStrings): PlanItem {
    val priceLine = strings.priceLine(PriceFormatter.format(plan, strings.locale), plan)
    return PlanItem(
        id = plan.id,
        title = strings.planTitle(plan),
        priceLine = priceLine,
        trialBadge = if (plan.hasTrial) strings.trialBadge(plan.trialDays) else null,
        notes = listOfNotNull(
            if (plan.hasTrial) strings.trialNote(plan.trialDays, priceLine) else null,
            when (plan.taxBehavior) {
                TaxBehavior.INCLUSIVE -> strings.taxInclusiveNote
                TaxBehavior.EXCLUSIVE -> strings.taxExclusiveNote
                TaxBehavior.UNSPECIFIED, TaxBehavior.UNKNOWN -> null
            },
            strings.renewalNote(priceLine),
        ),
    )
}
