// ManageModel.kt
// What the manage screen shows for an entitlement, as plain data (unit-tested on the JVM).

package com.robinjungerich.pulse.billing.android.ui

import com.robinjungerich.pulse.billing.BillingError
import com.robinjungerich.pulse.billing.BillingStrings
import com.robinjungerich.pulse.billing.Entitlement
import com.robinjungerich.pulse.billing.EntitlementSource
import com.robinjungerich.pulse.billing.EntitlementStatus
import com.robinjungerich.pulse.billing.android.EntitlementUiState
import com.robinjungerich.pulse.billing.errorMessage
import com.robinjungerich.pulse.billing.formatDate
import java.time.ZoneId

internal sealed interface ManageModel {
    data object Loading : ManageModel

    /** There is nothing to show: no cached answer and the server could not be reached. */
    data class LoadFailed(val message: String) : ManageModel

    data class Loaded(
        /** "Active", "Free trial", "No subscription". */
        val status: String,
        /** Renewal or end date, trial end, or the note that Premium comes from an access code. */
        val details: List<String>,
        /** Offline hint, past-due hint. */
        val notes: List<String>,
        /** The date Premium ends, for the cancel confirmation. */
        val endDate: String?,
        val canCancel: Boolean,
        val canResume: Boolean,
        val canManagePayments: Boolean,
        val working: Boolean,
        val error: String?,
    ) : ManageModel
}

internal fun manageModel(state: EntitlementUiState, strings: BillingStrings, zone: ZoneId = ZoneId.systemDefault()): ManageModel {
    val e = state.entitlement
    if (e == null) {
        val error = state.error
        return if (error != null && !state.isLoading) ManageModel.LoadFailed(strings.errorMessage(error)) else ManageModel.Loading
    }

    val stripe = e.source == EntitlementSource.STRIPE
    val periodEnd = e.currentPeriodEnd
    val trialEnd = e.trialEnd
    val endDate = (periodEnd ?: e.premiumUntil)?.let { strings.formatDate(it, zone) }

    val details = buildList {
        when {
            e.premium && !stripe -> add(strings.premiumWithoutSubscription)
            stripe && e.cancelAtPeriodEnd && endDate != null -> add(strings.endsOn(endDate))
            stripe && e.status == EntitlementStatus.TRIALING && trialEnd != null -> add(strings.trialEndsOn(strings.formatDate(trialEnd, zone)))
            stripe && e.premium && e.status == EntitlementStatus.ACTIVE && periodEnd != null -> add(strings.renewsOn(strings.formatDate(periodEnd, zone)))
        }
    }
    val confirmedAt = state.confirmedAt
    val notes = buildList {
        if (e.status == EntitlementStatus.PAST_DUE) add(strings.pastDueNote)
        if (state.isOffline && confirmedAt != null) add(strings.lastKnownStatus(strings.formatDate(confirmedAt, zone)))
    }
    val actionable = stripe && e.premium && !state.isOffline

    return ManageModel.Loaded(
        status = statusLabel(e, strings),
        details = details,
        notes = notes,
        endDate = endDate,
        canCancel = actionable && !e.cancelAtPeriodEnd,
        canResume = actionable && e.cancelAtPeriodEnd,
        canManagePayments = stripe && !state.isOffline,
        working = state.isWorking,
        // Being offline is already said by the note; every other failure is shown.
        error = state.error?.takeUnless { it is BillingError.Network }?.let { strings.errorMessage(it) },
    )
}

private fun statusLabel(e: Entitlement, strings: BillingStrings): String = when {
    // Premium from a source this client does not know, or from an access code: the flag is what counts.
    e.premium && (e.status == EntitlementStatus.NONE || e.status == EntitlementStatus.UNKNOWN) -> strings.status(EntitlementStatus.ACTIVE)
    else -> strings.status(e.status)
}
