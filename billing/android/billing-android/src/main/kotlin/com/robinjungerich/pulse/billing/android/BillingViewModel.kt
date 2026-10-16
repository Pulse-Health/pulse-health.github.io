// BillingViewModel.kt
// The state the paywall and the manage screen render: the purchase coordinator's state, the offers, and the user's
// entitlement (server answer, or the cached one when the server cannot be reached).

package com.robinjungerich.pulse.billing.android

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.robinjungerich.pulse.billing.BillingApi
import com.robinjungerich.pulse.billing.BillingError
import com.robinjungerich.pulse.billing.BillingStrings
import com.robinjungerich.pulse.billing.CachedEntitlement
import com.robinjungerich.pulse.billing.CachingBillingApi
import com.robinjungerich.pulse.billing.Entitlement
import com.robinjungerich.pulse.billing.EntitlementCache
import com.robinjungerich.pulse.billing.Offers
import com.robinjungerich.pulse.billing.PurchaseCoordinator
import com.robinjungerich.pulse.billing.PurchaseState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Clock
import java.time.Instant

/** What the manage screen knows about the user's subscription. */
data class EntitlementUiState(
    /** The last known entitlement: from the server, or from the cache while the server cannot be reached. */
    val entitlement: Entitlement? = null,
    /** When the server last vouched for [entitlement]. */
    val confirmedAt: Instant? = null,
    /** [entitlement] under the offline rule: premium, not expired, confirmed within the trust window. */
    val isPremium: Boolean = false,
    val isLoading: Boolean = false,
    /** A cancel, resume or portal request is in flight. */
    val isWorking: Boolean = false,
    /** The last refresh did not reach the server; [entitlement] is the cached answer, if any. */
    val isOffline: Boolean = false,
    /** The last failed request, until the next one starts or [BillingViewModel.dismissError]. */
    val error: BillingError? = null,
)

/** One-shot things the UI has to do. */
sealed interface BillingEvent {
    /** Open the Stripe Customer Portal; use a Custom Tab. */
    data class OpenPortal(val url: String) : BillingEvent
}

class BillingViewModel(
    private val api: BillingApi,
    private val coordinator: PurchaseCoordinator,
    private val cache: EntitlementCache,
    private val userId: String,
    val links: BillingLinks,
    val strings: BillingStrings,
    private val clock: Clock = Clock.systemUTC(),
    /** The Stripe presenter the coordinator uses, so the screen can bind the sheet to it. Null in tests. */
    val paymentSheet: StripePaymentSheetPresenter? = null,
) : ViewModel() {

    val purchaseState: StateFlow<PurchaseState> = coordinator.state

    /** The last offers the server returned; kept while a purchase is canceled or failed so the paywall stays up. */
    val offers: StateFlow<Offers?> = coordinator.offers

    private val _entitlement = MutableStateFlow(EntitlementUiState())
    val entitlement: StateFlow<EntitlementUiState> = _entitlement.asStateFlow()

    private val _events = Channel<BillingEvent>(Channel.BUFFERED)
    val events: Flow<BillingEvent> = _events.receiveAsFlow()

    fun loadOffers() {
        viewModelScope.launch { coordinator.loadOffers() }
    }

    fun purchase(planId: String, consentGiven: Boolean) {
        viewModelScope.launch {
            coordinator.purchase(planId, consentGiven)
            when (val state = coordinator.state.value) {
                is PurchaseState.Activated -> show(state.entitlement, clock.instant())
                PurchaseState.PendingActivation -> refreshEntitlement()
                else -> Unit
            }
        }
    }

    /** Leaves a finished purchase (activated, canceled, failed) so the paywall can be closed or shown again. */
    fun resetPurchase() = coordinator.reset()

    fun refreshEntitlement() {
        viewModelScope.launch { refresh() }
    }

    fun cancelSubscription() = work { show(api.cancel().entitlement, clock.instant()) }

    fun resumeSubscription() = work { show(api.resume().entitlement, clock.instant()) }

    fun openPortal() = work { _events.send(BillingEvent.OpenPortal(api.portalUrl(links.portalReturnUrl))) }

    fun dismissError() = _entitlement.update { it.copy(error = null) }

    private suspend fun refresh() {
        _entitlement.update { it.copy(isLoading = true, error = null) }
        if (_entitlement.value.entitlement == null) {
            cache.load(userId)?.let { cached -> showCached(cached) }
        }
        try {
            show(api.entitlement().entitlement, clock.instant())
        } catch (e: BillingError) {
            _entitlement.update { it.copy(isLoading = false, isOffline = e is BillingError.Network, error = e) }
        }
    }

    private fun work(block: suspend () -> Unit) {
        if (_entitlement.value.isWorking) return
        _entitlement.update { it.copy(isWorking = true, error = null) }
        viewModelScope.launch {
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: BillingError) {
                _entitlement.update { it.copy(error = e) }
            } finally {
                _entitlement.update { it.copy(isWorking = false) }
            }
        }
    }

    private fun show(entitlement: Entitlement, confirmedAt: Instant) {
        _entitlement.value = EntitlementUiState(
            entitlement = entitlement,
            confirmedAt = confirmedAt,
            isPremium = CachedEntitlement(entitlement, confirmedAt).isPremium(clock.instant()),
        )
    }

    private fun showCached(cached: CachedEntitlement) {
        _entitlement.update {
            it.copy(
                entitlement = cached.entitlement,
                confirmedAt = cached.confirmedAt,
                isPremium = cached.isPremium(clock.instant()),
            )
        }
    }
}

/**
 * Builds a [BillingViewModel] for one signed-in user. Use the user id as the ViewModel key, so signing in as someone
 * else never shows the previous user's subscription:
 *
 *     viewModel<BillingViewModel>(key = config.userId, factory = BillingViewModelFactory(context, config))
 */
class BillingViewModelFactory(
    context: Context,
    private val config: BillingConfig,
    private val cache: EntitlementCache = SharedPreferencesEntitlementCache(context),
) : ViewModelProvider.Factory {

    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        val api = CachingBillingApi(
            delegate = BillingApi(config.baseUrl, config.sessionTokens, config.client),
            cache = cache,
            userId = config.userId,
        )
        val presenter = StripePaymentSheetPresenter(config.googlePay, config.stripeReturnUrl)
        val coordinator = PurchaseCoordinator(
            api = api,
            presenter = presenter,
            country = config.country,
            consentLocale = config.strings.locale.toLanguageTag(),
        )
        return BillingViewModel(api, coordinator, cache, config.userId, config.links, config.strings, paymentSheet = presenter) as T
    }
}
