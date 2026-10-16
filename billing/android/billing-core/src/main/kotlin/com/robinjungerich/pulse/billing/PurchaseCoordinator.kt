// PurchaseCoordinator.kt
// The purchase flow of billing/docs/client-design.md as a state machine:
//
//   idle ─ loadOffers() ─▶ loadingOffers ─▶ ready(offers) | unavailable(reason)
//        ─ purchase()   ─▶ preparing ─▶ awaitingPayment ─▶ confirming ─▶ activated | pendingActivation
//                                         └▶ canceled | failed        (intent == null skips the sheet)

package com.robinjungerich.pulse.billing

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.UUID
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

sealed interface PurchaseState {
    data object Idle : PurchaseState
    data object LoadingOffers : PurchaseState

    /** Purchase is available and there is at least one plan. */
    data class Ready(val offers: Offers) : PurchaseState

    /** Hide the buy button; the manage UI may still show. [reason] is null when the server offered no plans. */
    data class Unavailable(val reason: UnavailableReason?) : PurchaseState

    data object Preparing : PurchaseState
    data object AwaitingPayment : PurchaseState
    data object Confirming : PurchaseState
    data class Activated(val entitlement: Entitlement) : PurchaseState

    /** Paid, but the entitlement did not turn Premium within the polling window (the webhook is late). */
    data object PendingActivation : PurchaseState

    /** The user closed the sheet. Not an error. */
    data object Canceled : PurchaseState
    data class Failed(val failure: PurchaseFailure) : PurchaseState
}

/** A state in which a request or the sheet is in flight; no other flow may start. */
val PurchaseState.isBusy: Boolean
    get() = this is PurchaseState.LoadingOffers ||
        this is PurchaseState.Preparing ||
        this is PurchaseState.AwaitingPayment ||
        this is PurchaseState.Confirming

/** Why a flow ended in [PurchaseState.Failed], typed so the UI can react (for example show the consent checkbox). */
sealed interface PurchaseFailure {
    /** The withdrawal consent is required and was not given. */
    data object ConsentRequired : PurchaseFailure

    data object Network : PurchaseFailure

    /** The Stripe sheet reported a failure; [message] is Stripe's localized text, if any. */
    data class Payment(val message: String?) : PurchaseFailure

    /** The server refused the request. */
    data class Server(val code: ErrorCode, val status: Int) : PurchaseFailure

    /** An answer or state the client cannot work with (unreadable response, unknown intent kind). */
    data object Unexpected : PurchaseFailure
}

class PurchaseCoordinator(
    private val api: BillingApi,
    private val presenter: PaymentSheetPresenting,
    /** Advisory country for offers and purchases; see the contract. */
    private val country: String?,
    /** BCP 47 language of the consent text the buyer sees, e.g. `de-DE`. */
    private val consentLocale: String,
    private val delay: suspend (Duration) -> Unit = { kotlinx.coroutines.delay(it) },
    private val newIdempotencyKey: () -> String = { UUID.randomUUID().toString() },
) {
    private val _state = MutableStateFlow<PurchaseState>(PurchaseState.Idle)
    val state: StateFlow<PurchaseState> = _state.asStateFlow()

    private val _offers = MutableStateFlow<Offers?>(null)

    /** The last offers the server returned; survives [PurchaseState.Canceled] and [PurchaseState.Failed] so the paywall can stay up. */
    val offers: StateFlow<Offers?> = _offers.asStateFlow()

    suspend fun loadOffers() {
        if (!enter(PurchaseState.LoadingOffers)) return
        try {
            val loaded = api.offers(country)
            _offers.value = loaded
            _state.value =
                if (loaded.purchase.available && loaded.plans.isNotEmpty()) {
                    PurchaseState.Ready(loaded)
                } else {
                    PurchaseState.Unavailable(loaded.purchase.reason)
                }
        } catch (e: BillingError) {
            _state.value = PurchaseState.Failed(e.toFailure())
        } finally {
            leaveIfBusy()
        }
    }

    /**
     * Buys [planId]. Does nothing while another flow is in flight. A fresh idempotency key is used per call, so a
     * second tap after a failure is a new attempt; the server resumes an unpaid subscription for the same plan.
     */
    suspend fun purchase(planId: String, consentGiven: Boolean, billingCountry: String? = null) {
        if (!enter(PurchaseState.Preparing)) return
        try {
            val offers = _offers.value
            if (offers == null) {
                _state.value = PurchaseState.Failed(PurchaseFailure.Unexpected)
            } else if (!offers.purchase.available) {
                _state.value = PurchaseState.Unavailable(offers.purchase.reason)
            } else if (offers.requiresWithdrawalConsent && !consentGiven) {
                _state.value = PurchaseState.Failed(PurchaseFailure.ConsentRequired)
            } else {
                run(offers, planId, consentGiven, billingCountry)
            }
        } finally {
            leaveIfBusy()
        }
    }

    /** Back to [PurchaseState.Idle], unless a flow is in flight. */
    fun reset() {
        _state.value.let { if (!it.isBusy) _state.value = PurchaseState.Idle }
    }

    private suspend fun run(offers: Offers, planId: String, consentGiven: Boolean, billingCountry: String?) {
        val created = try {
            api.startSubscription(
                planId = planId,
                country = country,
                billingCountry = billingCountry,
                consent = if (consentGiven) WithdrawalConsent(withdrawalWaiver = true, locale = consentLocale) else null,
                idempotencyKey = newIdempotencyKey(),
            )
        } catch (e: BillingError) {
            _state.value = whenStartFailed(e)
            return
        }

        val intent = created.intent
        if (intent == null) {
            confirm()
            return
        }
        if (intent.kind == IntentKind.UNKNOWN) {
            _state.value = PurchaseState.Failed(PurchaseFailure.Unexpected)
            return
        }

        _state.value = PurchaseState.AwaitingPayment
        val session = PaymentSession(
            customerId = created.customerId,
            customerEphemeralKeySecret = created.customerEphemeralKeySecret,
            publishableKey = created.publishableKey,
            merchantDisplayName = offers.merchantDisplayName,
            intentKind = intent.kind,
            intentClientSecret = intent.clientSecret,
        )
        val outcome = try {
            presenter.present(session)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            PaymentSheetOutcome.Failed(null)
        }
        when (outcome) {
            PaymentSheetOutcome.Completed -> confirm()
            PaymentSheetOutcome.Canceled -> _state.value = PurchaseState.Canceled
            is PaymentSheetOutcome.Failed -> _state.value = PurchaseState.Failed(PurchaseFailure.Payment(outcome.message))
        }
    }

    /**
     * The sheet reported success (or there was nothing to collect), but the `invoice.paid` webhook may not have
     * arrived yet. A failed attempt counts as "not yet": the user has paid, so a flaky connection must not turn the
     * flow into an error.
     */
    private suspend fun confirm() {
        _state.value = PurchaseState.Confirming
        for (wait in SYNC_SCHEDULE) {
            delay(wait)
            val entitlement = try {
                api.sync().entitlement
            } catch (_: BillingError) {
                null
            }
            if (entitlement?.premium == true) {
                _state.value = PurchaseState.Activated(entitlement)
                return
            }
        }
        _state.value = PurchaseState.PendingActivation
    }

    private suspend fun whenStartFailed(error: BillingError): PurchaseState {
        if (error !is BillingError.Api) return PurchaseState.Failed(error.toFailure())
        return when (error.code) {
            ErrorCode.CONSENT_REQUIRED -> PurchaseState.Failed(PurchaseFailure.ConsentRequired)
            ErrorCode.PURCHASE_NOT_AVAILABLE -> PurchaseState.Unavailable(reason = null)
            // The user simply already has Premium.
            ErrorCode.ALREADY_SUBSCRIBED -> try {
                val entitlement = api.sync().entitlement
                if (entitlement.premium) PurchaseState.Activated(entitlement) else PurchaseState.Failed(error.toFailure())
            } catch (e: BillingError) {
                PurchaseState.Failed(e.toFailure())
            }
            else -> PurchaseState.Failed(error.toFailure())
        }
    }

    /** Moves to [next] unless a flow is in flight. */
    private fun enter(next: PurchaseState): Boolean {
        while (true) {
            val current = _state.value
            if (current.isBusy) return false
            if (_state.compareAndSet(current, next)) return true
        }
    }

    /** Only a cancelled coroutine gets here still busy; it must not block the next flow forever. */
    private fun leaveIfBusy() {
        if (_state.value.isBusy) _state.value = PurchaseState.Idle
    }

    private fun BillingError.toFailure(): PurchaseFailure = when (this) {
        is BillingError.Api -> PurchaseFailure.Server(code, status)
        is BillingError.Network -> PurchaseFailure.Network
        is BillingError.Decoding -> PurchaseFailure.Unexpected
    }

    companion object {
        /** Waits before each of the six `sync()` attempts: 0, 1, 2, 3, 5, 8 seconds. */
        val SYNC_SCHEDULE: List<Duration> = listOf(0, 1, 2, 3, 5, 8).map { it.seconds }
    }
}
