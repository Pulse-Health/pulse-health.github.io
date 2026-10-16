package com.robinjungerich.pulse.billing.android

import com.robinjungerich.pulse.billing.IntentKind
import com.robinjungerich.pulse.billing.PaymentSession
import com.robinjungerich.pulse.billing.PaymentSheetOutcome
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class StripePaymentSheetPresenterTest {

    private val session = PaymentSession("cus_1", "ek_1", "pk_test_1", "Pulse", IntentKind.PAYMENT, "pi_secret_1")
    private val googlePay = GooglePayConfig(production = false, countryCode = "DE", currencyCode = "EUR")

    private class RecordingLauncher(val onLaunch: () -> Unit = {}) : SheetLauncher {
        val launched = mutableListOf<Pair<PaymentSession, GooglePayConfig?>>()

        override fun launch(session: PaymentSession, googlePay: GooglePayConfig?) {
            launched += session to googlePay
            onLaunch()
        }
    }

    private fun presenter(googlePay: GooglePayConfig? = null) =
        StripePaymentSheetPresenter(googlePay, Dispatchers.Unconfined)

    @Test
    fun presentLaunchesTheSheetAndResumesWithTheOutcome() = runTest {
        val presenter = presenter(googlePay)
        val launcher = RecordingLauncher()
        presenter.attach(launcher)

        val outcome = CompletableDeferred<PaymentSheetOutcome>()
        launch(UnconfinedTestDispatcher(testScheduler)) { outcome.complete(presenter.present(session)) }
        assertEquals(listOf(session to googlePay), launcher.launched)
        assertTrue(!outcome.isCompleted)

        presenter.onOutcome(PaymentSheetOutcome.Completed)

        assertEquals(PaymentSheetOutcome.Completed, outcome.await())
    }

    @Test
    fun canceledAndFailedResultsResume() = runTest {
        val presenter = presenter()
        presenter.attach(RecordingLauncher())
        for (expected in listOf(PaymentSheetOutcome.Canceled, PaymentSheetOutcome.Failed("declined"))) {
            val outcome = CompletableDeferred<PaymentSheetOutcome>()
            launch(UnconfinedTestDispatcher(testScheduler)) { outcome.complete(presenter.present(session)) }

            presenter.onOutcome(expected)

            assertEquals(expected, outcome.await())
        }
    }

    @Test
    fun googlePayIsOffUnlessTheHostPassesIt() = runTest {
        val presenter = presenter()
        val launcher = RecordingLauncher()
        presenter.attach(launcher)
        launch(UnconfinedTestDispatcher(testScheduler)) { presenter.present(session) }

        assertNull(launcher.launched.single().second)
        presenter.onOutcome(PaymentSheetOutcome.Canceled)
    }

    @Test
    fun withoutASheetBoundToAScreenPresentFails() = runTest {
        val outcome = presenter().present(session)

        assertTrue(outcome is PaymentSheetOutcome.Failed)
    }

    @Test
    fun aDetachedLauncherIsNotUsed() = runTest {
        val presenter = presenter()
        val launcher = RecordingLauncher()
        presenter.attach(launcher)
        presenter.detach(launcher)

        assertTrue(presenter.present(session) is PaymentSheetOutcome.Failed)
        assertTrue(launcher.launched.isEmpty())
    }

    @Test
    fun aNewLauncherReplacesTheOldOneAndTheOldCannotDetachIt() = runTest {
        val presenter = presenter()
        val old = RecordingLauncher()
        val new = RecordingLauncher()
        presenter.attach(old)
        presenter.attach(new)
        presenter.detach(old)
        launch(UnconfinedTestDispatcher(testScheduler)) { presenter.present(session) }

        assertTrue(old.launched.isEmpty())
        assertEquals(1, new.launched.size)
        presenter.onOutcome(PaymentSheetOutcome.Canceled)
    }

    @Test
    fun theResultSurvivesTheScreenBeingRecreatedWhileTheSheetIsOpen() = runTest {
        val presenter = presenter()
        val first = RecordingLauncher()
        presenter.attach(first)
        val outcome = CompletableDeferred<PaymentSheetOutcome>()
        launch(UnconfinedTestDispatcher(testScheduler)) { outcome.complete(presenter.present(session)) }

        presenter.detach(first)
        presenter.attach(RecordingLauncher())
        presenter.onOutcome(PaymentSheetOutcome.Completed)

        assertEquals(PaymentSheetOutcome.Completed, outcome.await())
    }

    @Test
    fun aSecondSheetWhileOneIsOpenIsRefused() = runTest {
        val presenter = presenter()
        val launcher = RecordingLauncher()
        presenter.attach(launcher)
        launch(UnconfinedTestDispatcher(testScheduler)) { presenter.present(session) }

        val second = presenter.present(session)

        assertTrue(second is PaymentSheetOutcome.Failed)
        assertEquals(1, launcher.launched.size)
        presenter.onOutcome(PaymentSheetOutcome.Canceled)
    }

    @Test
    fun aLauncherThatThrowsFailsTheOutcomeAndFreesThePresenter() = runTest {
        val presenter = presenter()
        presenter.attach(SheetLauncher { _, _ -> throw IllegalArgumentException("The publishable key is invalid") })

        val outcome = presenter.present(session)

        assertEquals(PaymentSheetOutcome.Failed("The publishable key is invalid"), outcome)
        val launcher = RecordingLauncher()
        presenter.attach(launcher)
        launch(UnconfinedTestDispatcher(testScheduler)) { presenter.present(session) }
        assertEquals(1, launcher.launched.size)
        presenter.onOutcome(PaymentSheetOutcome.Canceled)
    }

    @Test
    fun aResultNobodyWaitsForIsDropped() {
        presenter().onOutcome(PaymentSheetOutcome.Completed)
    }

    // Not unit-testable here, on purpose: the Stripe SDK keeps the PaymentSheetResult constructors and the PaymentSheet.Configuration
    // getters internal, so a JVM test can neither build a result nor read a configuration back. The result mapping (three lines)
    // and the configuration builder are covered by the compile step and by reading them; a device test would exercise the real sheet.
}
