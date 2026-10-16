package com.robinjungerich.pulse.billing.android

import com.robinjungerich.pulse.billing.BillingError
import com.robinjungerich.pulse.billing.BillingStrings
import com.robinjungerich.pulse.billing.CachedEntitlement
import com.robinjungerich.pulse.billing.Entitlement
import com.robinjungerich.pulse.billing.ErrorCode
import com.robinjungerich.pulse.billing.InMemoryEntitlementCache
import com.robinjungerich.pulse.billing.PurchaseCoordinator
import com.robinjungerich.pulse.billing.PurchaseState
import com.robinjungerich.pulse.billing.testing.FakeBillingApi
import com.robinjungerich.pulse.billing.testing.FakePresenter
import com.robinjungerich.pulse.billing.testing.MutableClock
import com.robinjungerich.pulse.billing.testing.NOW
import com.robinjungerich.pulse.billing.testing.apiError
import com.robinjungerich.pulse.billing.testing.offers
import com.robinjungerich.pulse.billing.testing.premiumEntitlement
import com.robinjungerich.pulse.billing.testing.response
import com.robinjungerich.pulse.billing.testing.subscription
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.IOException
import java.time.Duration
import java.util.Locale

@OptIn(ExperimentalCoroutinesApi::class)
class BillingViewModelTest {

    private val api = FakeBillingApi()
    private val cache = InMemoryEntitlementCache()
    private val clock = MutableClock()
    private val presenter = FakePresenter()
    private val links = BillingLinks("https://pulse.example/terms", "https://pulse.example/privacy", "pulse://billing/return")
    private val strings = BillingStrings.forLocale(Locale.US)
    private val premium = premiumEntitlement()

    private val coordinator = PurchaseCoordinator(api, presenter, "DE", "en-US", delay = { }, newIdempotencyKey = { "key" })
    private lateinit var viewModel: BillingViewModel

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        viewModel = BillingViewModel(api, coordinator, cache, "user_1", links, strings, clock)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun networkError() = BillingError.Network(IOException("offline"))

    // MARK: - Purchase

    @Test
    fun loadOffersExposesTheCoordinatorsState() = runTest {
        api.offersResults += Result.success(offers())

        viewModel.loadOffers()

        assertTrue(viewModel.purchaseState.value is PurchaseState.Ready)
        assertEquals(2, viewModel.offers.value?.plans?.size)
    }

    @Test
    fun anActivatedPurchaseUpdatesTheEntitlement() = runTest {
        api.offersResults += Result.success(offers())
        api.startResults += Result.success(subscription())
        api.syncResults += Result.success(response(premium))
        viewModel.loadOffers()

        viewModel.purchase("premium_monthly", consentGiven = true)

        assertEquals(PurchaseState.Activated(premium), viewModel.purchaseState.value)
        val state = viewModel.entitlement.value
        assertEquals(premium, state.entitlement)
        assertTrue(state.isPremium)
        assertFalse(state.isOffline)
    }

    @Test
    fun aPurchaseThatIsStillPendingRefreshesTheEntitlementOnce() = runTest {
        api.offersResults += Result.success(offers())
        api.startResults += Result.success(subscription())
        repeat(6) { api.syncResults += Result.success(response(Entitlement.NONE)) }
        api.entitlementResults += Result.success(response(premium))
        viewModel.loadOffers()

        viewModel.purchase("premium_monthly", consentGiven = true)

        assertEquals(PurchaseState.PendingActivation, viewModel.purchaseState.value)
        assertEquals(premium, viewModel.entitlement.value.entitlement)
    }

    @Test
    fun resetPurchaseLeavesAFinishedPurchase() = runTest {
        api.offersResults += Result.success(offers())
        api.startResults += Result.success(subscription(intent = null))
        api.syncResults += Result.success(response(premium))
        viewModel.loadOffers()
        viewModel.purchase("premium_monthly", consentGiven = true)

        viewModel.resetPurchase()

        assertEquals(PurchaseState.Idle, viewModel.purchaseState.value)
    }

    // MARK: - Entitlement

    @Test
    fun refreshShowsTheServersAnswer() = runTest {
        api.entitlementResults += Result.success(response(premium))

        viewModel.refreshEntitlement()

        val state = viewModel.entitlement.value
        assertEquals(premium, state.entitlement)
        assertEquals(NOW, state.confirmedAt)
        assertTrue(state.isPremium)
        assertFalse(state.isLoading)
        assertNull(state.error)
    }

    @Test
    fun offlineTheCachedAnswerIsShownAndTrustedWithinTheWindow() = runTest {
        cache.save("user_1", CachedEntitlement(premium, confirmedAt = NOW.minus(Duration.ofDays(2))))
        api.entitlementResults += Result.failure(networkError())

        viewModel.refreshEntitlement()

        val state = viewModel.entitlement.value
        assertEquals(premium, state.entitlement)
        assertTrue(state.isOffline)
        assertTrue(state.error is BillingError.Network)
        assertTrue(state.isPremium)
        assertEquals(NOW.minus(Duration.ofDays(2)), state.confirmedAt)
    }

    @Test
    fun offlineACachedAnswerOlderThanTheTrustWindowIsShownButNotPremium() = runTest {
        cache.save("user_1", CachedEntitlement(premium, confirmedAt = NOW.minus(Duration.ofDays(8))))
        api.entitlementResults += Result.failure(networkError())

        viewModel.refreshEntitlement()

        val state = viewModel.entitlement.value
        assertNotNull(state.entitlement)
        assertTrue(state.isOffline)
        assertFalse(state.isPremium)
    }

    @Test
    fun offlineWithoutACacheThereIsNothingToShow() = runTest {
        api.entitlementResults += Result.failure(networkError())

        viewModel.refreshEntitlement()

        val state = viewModel.entitlement.value
        assertNull(state.entitlement)
        assertTrue(state.isOffline)
        assertFalse(state.isPremium)
        assertFalse(state.isLoading)
    }

    @Test
    fun aServerErrorKeepsTheLastAnswerAndIsNotOffline() = runTest {
        api.entitlementResults += Result.success(response(premium))
        viewModel.refreshEntitlement()
        api.entitlementResults += Result.failure(apiError(ErrorCode.INTERNAL, 500))

        viewModel.refreshEntitlement()

        val state = viewModel.entitlement.value
        assertEquals(premium, state.entitlement)
        assertFalse(state.isOffline)
        assertEquals(ErrorCode.INTERNAL, (state.error as BillingError.Api).code)
    }

    @Test
    fun aSuccessfulNotPremiumAnswerReplacesAPremiumOne() = runTest {
        api.entitlementResults += Result.success(response(premium))
        viewModel.refreshEntitlement()
        api.entitlementResults += Result.success(response(Entitlement.NONE))

        viewModel.refreshEntitlement()

        assertFalse(viewModel.entitlement.value.isPremium)
        assertEquals(Entitlement.NONE, viewModel.entitlement.value.entitlement)
    }

    // MARK: - Actions

    @Test
    fun cancelUpdatesTheEntitlement() = runTest {
        api.cancelResults += Result.success(response(premium.copy(cancelAtPeriodEnd = true)))

        viewModel.cancelSubscription()

        val state = viewModel.entitlement.value
        assertTrue(state.entitlement!!.cancelAtPeriodEnd)
        assertFalse(state.isWorking)
        assertNull(state.error)
    }

    @Test
    fun aFailedCancelKeepsTheEntitlementAndShowsTheError() = runTest {
        api.entitlementResults += Result.success(response(premium))
        viewModel.refreshEntitlement()
        api.cancelResults += Result.failure(apiError(ErrorCode.NO_SUBSCRIPTION, 404))

        viewModel.cancelSubscription()

        val state = viewModel.entitlement.value
        assertEquals(premium, state.entitlement)
        assertFalse(state.isWorking)
        assertEquals(ErrorCode.NO_SUBSCRIPTION, (state.error as BillingError.Api).code)

        viewModel.dismissError()
        assertNull(viewModel.entitlement.value.error)
    }

    @Test
    fun resumeUndoesTheCancellation() = runTest {
        api.resumeResults += Result.success(response(premium))

        viewModel.resumeSubscription()

        assertFalse(viewModel.entitlement.value.entitlement!!.cancelAtPeriodEnd)
    }

    @Test
    fun openPortalAsksForTheHostsReturnUrlAndEmitsTheLink() = runTest {
        val events = collectEvents()
        api.portalResults += Result.success("https://billing.stripe.com/p/session/x")

        viewModel.openPortal()

        assertEquals(listOf("pulse://billing/return"), api.portalCalls)
        assertEquals(listOf<BillingEvent>(BillingEvent.OpenPortal("https://billing.stripe.com/p/session/x")), events)
        assertFalse(viewModel.entitlement.value.isWorking)
    }

    @Test
    fun aFailedPortalRequestShowsTheErrorAndEmitsNothing() = runTest {
        val events = collectEvents()
        api.portalResults += Result.failure(apiError(ErrorCode.NO_CUSTOMER, 404))

        viewModel.openPortal()

        assertTrue(events.isEmpty())
        assertEquals(ErrorCode.NO_CUSTOMER, (viewModel.entitlement.value.error as BillingError.Api).code)
    }

    @Test
    fun theLinksAndStringsAreTheHosts() {
        assertEquals("https://pulse.example/terms", viewModel.links.termsUrl)
        assertEquals(strings, viewModel.strings)
    }

    private fun TestScope.collectEvents(): List<BillingEvent> {
        val events = mutableListOf<BillingEvent>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.events.toList(events) }
        return events
    }
}
