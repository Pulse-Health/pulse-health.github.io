package com.robinjungerich.pulse.billing

import com.robinjungerich.pulse.billing.testing.FakeBillingApi
import com.robinjungerich.pulse.billing.testing.FakePresenter
import com.robinjungerich.pulse.billing.testing.apiError
import com.robinjungerich.pulse.billing.testing.offers
import com.robinjungerich.pulse.billing.testing.premiumEntitlement
import com.robinjungerich.pulse.billing.testing.response
import com.robinjungerich.pulse.billing.testing.subscription
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.util.UUID
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

@OptIn(ExperimentalCoroutinesApi::class)
class PurchaseCoordinatorTest {

    private val api = FakeBillingApi()
    private val presenter = FakePresenter()
    private val waits = mutableListOf<Duration>()
    private var keyCounter = 0

    private val coordinator = PurchaseCoordinator(
        api = api,
        presenter = presenter,
        country = "DE",
        consentLocale = "de-DE",
        delay = { waits += it },
        newIdempotencyKey = { "key-${++keyCounter}" },
    )

    private val premium = premiumEntitlement()
    private val notPremium = Entitlement.NONE

    private fun TestScope.recordStates(target: PurchaseCoordinator = coordinator): List<PurchaseState> {
        val seen = mutableListOf<PurchaseState>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { target.state.toList(seen) }
        return seen
    }

    private fun networkError() = BillingError.Network(IOException("offline"))

    private suspend fun loadReadyOffers(requiresConsent: Boolean = true) {
        api.offersResults += Result.success(offers(requiresWithdrawalConsent = requiresConsent))
        coordinator.loadOffers()
        assertTrue(coordinator.state.value is PurchaseState.Ready)
    }

    // MARK: - Offers

    @Test
    fun loadOffersMovesToReady() = runTest {
        val states = recordStates()
        val loaded = offers()
        api.offersResults += Result.success(loaded)

        coordinator.loadOffers()

        assertEquals(listOf("DE"), api.offersCalls)
        assertEquals(listOf(PurchaseState.Idle, PurchaseState.LoadingOffers, PurchaseState.Ready(loaded)), states)
        assertEquals(loaded, coordinator.offers.value)
    }

    @Test
    fun offersThatAreUnavailableInTheRegionMoveToUnavailable() = runTest {
        val states = recordStates()
        api.offersResults += Result.success(
            offers(available = false, reason = UnavailableReason.REGION_NOT_SUPPORTED, plans = emptyList()),
        )

        coordinator.loadOffers()

        assertEquals(PurchaseState.Unavailable(UnavailableReason.REGION_NOT_SUPPORTED), states.last())
        assertEquals(listOf(PurchaseState.Idle, PurchaseState.LoadingOffers), states.take(2))
    }

    @Test
    fun anAvailablePurchaseWithoutPlansIsUnavailable() = runTest {
        api.offersResults += Result.success(offers(available = true, plans = emptyList()))

        coordinator.loadOffers()

        assertEquals(PurchaseState.Unavailable(null), coordinator.state.value)
    }

    @Test
    fun aNetworkErrorWhileLoadingOffersFails() = runTest {
        api.offersResults += Result.failure(networkError())

        coordinator.loadOffers()

        assertEquals(PurchaseState.Failed(PurchaseFailure.Network), coordinator.state.value)
        assertNull(coordinator.offers.value)
    }

    @Test
    fun loadingOffersAgainAfterAFailureRecovers() = runTest {
        api.offersResults += Result.failure(apiError(ErrorCode.INTERNAL, 500))
        api.offersResults += Result.success(offers())

        coordinator.loadOffers()
        assertEquals(PurchaseState.Failed(PurchaseFailure.Server(ErrorCode.INTERNAL, 500)), coordinator.state.value)
        coordinator.loadOffers()

        assertTrue(coordinator.state.value is PurchaseState.Ready)
    }

    // MARK: - Happy paths

    @Test
    fun aPaymentGoesThroughTheSheetAndActivates() = runTest {
        loadReadyOffers()
        val states = recordStates()
        api.startResults += Result.success(subscription())
        api.syncResults += Result.success(response(premium))

        coordinator.purchase("premium_monthly", consentGiven = true)

        assertEquals(
            listOf(
                PurchaseState.Ready(offers()),
                PurchaseState.Preparing,
                PurchaseState.AwaitingPayment,
                PurchaseState.Confirming,
                PurchaseState.Activated(premium),
            ),
            states,
        )
        val call = api.startCalls.single()
        assertEquals("premium_monthly", call.planId)
        assertEquals("DE", call.country)
        assertEquals(WithdrawalConsent(withdrawalWaiver = true, locale = "de-DE"), call.consent)
        assertEquals("key-1", call.idempotencyKey)
        assertEquals(
            PaymentSession(
                customerId = "cus_1",
                customerEphemeralKeySecret = "ek_secret_1",
                publishableKey = "pk_test_FIXTURE",
                merchantDisplayName = "Pulse",
                intentKind = IntentKind.PAYMENT,
                intentClientSecret = "pi_secret_1",
            ),
            presenter.sessions.single(),
        )
        assertEquals(listOf(0.seconds), waits)
    }

    @Test
    fun aTrialCollectsAPaymentMethodWithASetupIntent() = runTest {
        loadReadyOffers()
        api.startResults += Result.success(subscription(StripeIntent(IntentKind.SETUP, "seti_secret_1")))
        api.syncResults += Result.success(response(premiumEntitlement().copy(status = EntitlementStatus.TRIALING)))

        coordinator.purchase("premium_monthly", consentGiven = true)

        val session = presenter.sessions.single()
        assertEquals(IntentKind.SETUP, session.intentKind)
        assertEquals("seti_secret_1", session.intentClientSecret)
        assertTrue(coordinator.state.value is PurchaseState.Activated)
    }

    @Test
    fun withoutAnIntentThereIsNothingToCollectAndTheFlowSyncs() = runTest {
        loadReadyOffers()
        val states = recordStates()
        api.startResults += Result.success(subscription(intent = null))
        api.syncResults += Result.success(response(premium))

        coordinator.purchase("premium_monthly", consentGiven = true)

        assertTrue(presenter.sessions.isEmpty())
        assertEquals(
            listOf(PurchaseState.Preparing, PurchaseState.Confirming, PurchaseState.Activated(premium)),
            states.drop(2),
        )
    }

    // MARK: - Sheet outcomes

    @Test
    fun aCanceledSheetIsNotAnError() = runTest {
        loadReadyOffers()
        presenter.outcome = { PaymentSheetOutcome.Canceled }
        api.startResults += Result.success(subscription())

        coordinator.purchase("premium_monthly", consentGiven = true)

        assertEquals(PurchaseState.Canceled, coordinator.state.value)
        assertEquals(0, api.syncCalls)
        assertNotNull("the paywall keeps its plans", coordinator.offers.value)
    }

    @Test
    fun aFailedSheetFailsWithTheSheetsMessage() = runTest {
        loadReadyOffers()
        presenter.outcome = { PaymentSheetOutcome.Failed("Your card was declined.") }
        api.startResults += Result.success(subscription())

        coordinator.purchase("premium_monthly", consentGiven = true)

        assertEquals(PurchaseState.Failed(PurchaseFailure.Payment("Your card was declined.")), coordinator.state.value)
        assertEquals(0, api.syncCalls)
    }

    @Test
    fun aPresenterThatThrowsFailsTheFlow() = runTest {
        loadReadyOffers()
        presenter.outcome = { throw IllegalStateException("no activity") }
        api.startResults += Result.success(subscription())

        coordinator.purchase("premium_monthly", consentGiven = true)

        assertEquals(PurchaseState.Failed(PurchaseFailure.Payment(null)), coordinator.state.value)
    }

    @Test
    fun anIntentOfAnUnknownKindIsNotPresented() = runTest {
        loadReadyOffers()
        api.startResults += Result.success(subscription(StripeIntent(IntentKind.UNKNOWN, "x_secret")))

        coordinator.purchase("premium_monthly", consentGiven = true)

        assertEquals(PurchaseState.Failed(PurchaseFailure.Unexpected), coordinator.state.value)
        assertTrue(presenter.sessions.isEmpty())
    }

    // MARK: - Confirming

    @Test
    fun syncPollsOnTheScheduleAndEndsInPendingActivation() = runTest {
        loadReadyOffers()
        api.startResults += Result.success(subscription())
        repeat(6) { api.syncResults += Result.success(response(notPremium)) }

        coordinator.purchase("premium_monthly", consentGiven = true)

        assertEquals(PurchaseState.PendingActivation, coordinator.state.value)
        assertEquals(6, api.syncCalls)
        assertEquals(listOf(0, 1, 2, 3, 5, 8).map { it.seconds }, waits)
        assertEquals(PurchaseCoordinator.SYNC_SCHEDULE, waits)
    }

    @Test
    fun pollingStopsAsSoonAsTheEntitlementIsPremium() = runTest {
        loadReadyOffers()
        api.startResults += Result.success(subscription())
        repeat(3) { api.syncResults += Result.success(response(notPremium)) }
        api.syncResults += Result.success(response(premium))

        coordinator.purchase("premium_monthly", consentGiven = true)

        assertEquals(PurchaseState.Activated(premium), coordinator.state.value)
        assertEquals(4, api.syncCalls)
        assertEquals(listOf(0, 1, 2, 3).map { it.seconds }, waits)
    }

    @Test
    fun aFailedSyncAttemptCountsAsNotYet() = runTest {
        loadReadyOffers()
        api.startResults += Result.success(subscription())
        api.syncResults += Result.failure(networkError())
        api.syncResults += Result.failure(apiError(ErrorCode.RATE_LIMITED, 429))
        api.syncResults += Result.success(response(premium))

        coordinator.purchase("premium_monthly", consentGiven = true)

        assertEquals(PurchaseState.Activated(premium), coordinator.state.value)
    }

    @Test
    fun whenEverySyncFailsAfterPaymentTheFlowIsPendingNotFailed() = runTest {
        loadReadyOffers()
        api.startResults += Result.success(subscription())
        repeat(6) { api.syncResults += Result.failure(networkError()) }

        coordinator.purchase("premium_monthly", consentGiven = true)

        assertEquals(PurchaseState.PendingActivation, coordinator.state.value)
    }

    // MARK: - Server answers to the purchase

    @Test
    fun alreadySubscribedSyncsAndActivates() = runTest {
        loadReadyOffers()
        api.startResults += Result.failure(apiError(ErrorCode.ALREADY_SUBSCRIBED, 409))
        api.syncResults += Result.success(response(premium))

        coordinator.purchase("premium_monthly", consentGiven = true)

        assertEquals(PurchaseState.Activated(premium), coordinator.state.value)
        assertEquals(1, api.syncCalls)
        assertTrue(presenter.sessions.isEmpty())
    }

    @Test
    fun alreadySubscribedWithoutPremiumAfterTheSyncFails() = runTest {
        loadReadyOffers()
        api.startResults += Result.failure(apiError(ErrorCode.ALREADY_SUBSCRIBED, 409))
        api.syncResults += Result.success(response(notPremium))

        coordinator.purchase("premium_monthly", consentGiven = true)

        assertEquals(PurchaseState.Failed(PurchaseFailure.Server(ErrorCode.ALREADY_SUBSCRIBED, 409)), coordinator.state.value)
    }

    @Test
    fun consentRequiredFromTheServerFailsWithATypedReason() = runTest {
        loadReadyOffers(requiresConsent = false)
        api.startResults += Result.failure(apiError(ErrorCode.CONSENT_REQUIRED, 400))

        coordinator.purchase("premium_monthly", consentGiven = false)

        assertEquals(PurchaseState.Failed(PurchaseFailure.ConsentRequired), coordinator.state.value)
        assertNull(api.startCalls.single().consent)
    }

    @Test
    fun withoutTheRequiredConsentNothingIsSent() = runTest {
        loadReadyOffers(requiresConsent = true)

        coordinator.purchase("premium_monthly", consentGiven = false)

        assertEquals(PurchaseState.Failed(PurchaseFailure.ConsentRequired), coordinator.state.value)
        assertTrue(api.startCalls.isEmpty())
    }

    @Test
    fun consentIsOnlySentWhenGiven() = runTest {
        loadReadyOffers(requiresConsent = false)
        api.startResults += Result.success(subscription(intent = null))
        api.syncResults += Result.success(response(premium))

        coordinator.purchase("premium_monthly", consentGiven = false)

        assertNull(api.startCalls.single().consent)
    }

    @Test
    fun aPurchaseTheServerRefusesMovesToUnavailable() = runTest {
        loadReadyOffers()
        api.startResults += Result.failure(apiError(ErrorCode.PURCHASE_NOT_AVAILABLE, 403))

        coordinator.purchase("premium_monthly", consentGiven = true)

        assertEquals(PurchaseState.Unavailable(null), coordinator.state.value)
    }

    @Test
    fun otherServerErrorsKeepTheirCode() = runTest {
        loadReadyOffers()
        api.startResults += Result.failure(apiError(ErrorCode.PLAN_NOT_FOUND, 404))
        api.startResults += Result.failure(BillingError.Decoding(IllegalStateException("bad json")))

        coordinator.purchase("nope", consentGiven = true)
        assertEquals(PurchaseState.Failed(PurchaseFailure.Server(ErrorCode.PLAN_NOT_FOUND, 404)), coordinator.state.value)

        coordinator.purchase("premium_monthly", consentGiven = true)
        assertEquals(PurchaseState.Failed(PurchaseFailure.Unexpected), coordinator.state.value)
    }

    @Test
    fun aNetworkErrorWhilePreparingFailsAndTheNextTapStartsAgain() = runTest {
        loadReadyOffers()
        api.startResults += Result.failure(networkError())
        api.startResults += Result.success(subscription())
        api.syncResults += Result.success(response(premium))

        coordinator.purchase("premium_monthly", consentGiven = true)
        assertEquals(PurchaseState.Failed(PurchaseFailure.Network), coordinator.state.value)
        assertNotNull(coordinator.offers.value)

        coordinator.purchase("premium_monthly", consentGiven = true)
        assertEquals(PurchaseState.Activated(premium), coordinator.state.value)
        assertEquals(listOf("key-1", "key-2"), api.startCalls.map { it.idempotencyKey })
    }

    @Test
    fun theBillingCountryIsPassedOn() = runTest {
        loadReadyOffers()
        api.startResults += Result.success(subscription(intent = null))
        api.syncResults += Result.success(response(premium))

        coordinator.purchase("premium_monthly", consentGiven = true, billingCountry = "AT")

        assertEquals("AT", api.startCalls.single().billingCountry)
    }

    // MARK: - Guards

    @Test
    fun everyPurchaseCallGetsAFreshIdempotencyKey() = runTest {
        val real = PurchaseCoordinator(api, presenter, "DE", "de-DE", delay = { })
        api.offersResults += Result.success(offers())
        real.loadOffers()
        repeat(2) {
            api.startResults += Result.failure(apiError(ErrorCode.INTERNAL, 500))
            real.purchase("premium_monthly", consentGiven = true)
        }

        val keys = api.startCalls.map { it.idempotencyKey }
        assertEquals(2, keys.toSet().size)
        keys.forEach { UUID.fromString(it) }
    }

    @Test
    fun aSecondTapWhileThePaymentSheetIsOpenIsIgnored() = runTest {
        val sheetClosed = CompletableDeferred<PaymentSheetOutcome>()
        val suspendingPresenter = PaymentSheetPresenting { sheetClosed.await() }
        val busy = PurchaseCoordinator(api, suspendingPresenter, "DE", "de-DE", delay = { })
        api.offersResults += Result.success(offers())
        busy.loadOffers()
        api.startResults += Result.success(subscription())
        api.syncResults += Result.success(response(premium))

        val first = launch(UnconfinedTestDispatcher(testScheduler)) { busy.purchase("premium_monthly", consentGiven = true) }
        assertEquals(PurchaseState.AwaitingPayment, busy.state.value)
        busy.purchase("premium_yearly", consentGiven = true)
        busy.loadOffers()

        assertEquals(1, api.startCalls.size)
        assertEquals(PurchaseState.AwaitingPayment, busy.state.value)
        sheetClosed.complete(PaymentSheetOutcome.Completed)
        first.join()
        assertEquals(PurchaseState.Activated(premium), busy.state.value)
    }

    @Test
    fun purchasingBeforeTheOffersAreLoadedFails() = runTest {
        coordinator.purchase("premium_monthly", consentGiven = true)

        assertEquals(PurchaseState.Failed(PurchaseFailure.Unexpected), coordinator.state.value)
        assertTrue(api.startCalls.isEmpty())
    }

    @Test
    fun purchasingWhereItIsUnavailableSendsNothing() = runTest {
        api.offersResults += Result.success(offers(available = false, reason = UnavailableReason.PLATFORM_NOT_SUPPORTED, plans = emptyList()))
        coordinator.loadOffers()

        coordinator.purchase("premium_monthly", consentGiven = true)

        assertEquals(PurchaseState.Unavailable(UnavailableReason.PLATFORM_NOT_SUPPORTED), coordinator.state.value)
        assertTrue(api.startCalls.isEmpty())
    }

    @Test
    fun aCancelledFlowDoesNotBlockTheNextOne() = runTest {
        val sheet = CompletableDeferred<PaymentSheetOutcome>()
        val hanging = PurchaseCoordinator(api, { sheet.await() }, "DE", "de-DE", delay = { })
        api.offersResults += Result.success(offers())
        hanging.loadOffers()
        api.startResults += Result.success(subscription())

        val job = launch(UnconfinedTestDispatcher(testScheduler)) { hanging.purchase("premium_monthly", consentGiven = true) }
        assertEquals(PurchaseState.AwaitingPayment, hanging.state.value)
        job.cancel()
        job.join()

        assertEquals(PurchaseState.Idle, hanging.state.value)
        api.startResults += Result.failure(apiError(ErrorCode.INTERNAL, 500))
        hanging.purchase("premium_monthly", consentGiven = true)
        assertEquals(2, api.startCalls.size)
    }

    @Test
    fun resetReturnsToIdleButNotWhileBusy() = runTest {
        loadReadyOffers()
        coordinator.reset()
        assertEquals(PurchaseState.Idle, coordinator.state.value)

        val sheet = CompletableDeferred<PaymentSheetOutcome>()
        val hanging = PurchaseCoordinator(api, { sheet.await() }, "DE", "de-DE", delay = { })
        api.offersResults += Result.success(offers())
        hanging.loadOffers()
        api.startResults += Result.success(subscription())
        val job = launch(UnconfinedTestDispatcher(testScheduler)) { hanging.purchase("premium_monthly", consentGiven = true) }
        hanging.reset()
        assertEquals(PurchaseState.AwaitingPayment, hanging.state.value)
        job.cancel()
    }

    @Test
    fun onlyInFlightStatesAreBusy() {
        val busy = listOf(PurchaseState.LoadingOffers, PurchaseState.Preparing, PurchaseState.AwaitingPayment, PurchaseState.Confirming)
        val idle = listOf(
            PurchaseState.Idle,
            PurchaseState.Ready(offers()),
            PurchaseState.Unavailable(null),
            PurchaseState.Activated(premium),
            PurchaseState.PendingActivation,
            PurchaseState.Canceled,
            PurchaseState.Failed(PurchaseFailure.Network),
        )
        assertTrue(busy.all { it.isBusy })
        assertTrue(idle.none { it.isBusy })
    }
}
