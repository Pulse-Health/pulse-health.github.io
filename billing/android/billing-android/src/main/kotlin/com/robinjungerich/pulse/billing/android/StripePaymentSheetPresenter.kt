// StripePaymentSheetPresenter.kt
// PaymentSheetPresenting on the Stripe Android SDK.
//
// The presenter outlives the Activity (the BillingViewModel owns it) so that a sheet that is open while the Activity is
// recreated still resumes the suspended purchase: each composition binds its own PaymentSheet to the presenter, and the
// pending result stays here. The SDK is configured per purchase from the session, not at app start.

package com.robinjungerich.pulse.billing.android

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.robinjungerich.pulse.billing.IntentKind
import com.robinjungerich.pulse.billing.PaymentSession
import com.robinjungerich.pulse.billing.PaymentSheetOutcome
import com.robinjungerich.pulse.billing.PaymentSheetPresenting
import com.stripe.android.PaymentConfiguration
import com.stripe.android.paymentsheet.PaymentSheet
import com.stripe.android.paymentsheet.PaymentSheetResult
import com.stripe.android.paymentsheet.rememberPaymentSheet
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Google Pay in the payment sheet. Off unless the host passes this to [BillingConfig]. */
data class GooglePayConfig(
    val production: Boolean,
    /** ISO 3166-1 alpha-2 country code of the merchant. */
    val countryCode: String,
    /** ISO 4217 code; needed by Google Pay for setup intents (trials). */
    val currencyCode: String? = null,
)

/** Shows the sheet for a session. The only part of the presenter that touches the Stripe SDK. */
internal fun interface SheetLauncher {
    fun launch(session: PaymentSession, googlePay: GooglePayConfig?)
}

class StripePaymentSheetPresenter internal constructor(
    private val googlePay: GooglePayConfig?,
    private val mainDispatcher: CoroutineDispatcher,
) : PaymentSheetPresenting {

    constructor(googlePay: GooglePayConfig? = null) :
        this(googlePay, Dispatchers.Main.immediate)

    private var launcher: SheetLauncher? = null
    private var pending: CompletableDeferred<PaymentSheetOutcome>? = null

    override suspend fun present(session: PaymentSession): PaymentSheetOutcome {
        val launcher = launcher ?: return PaymentSheetOutcome.Failed("The payment sheet is not attached to a screen.")
        if (pending != null) return PaymentSheetOutcome.Failed("A payment sheet is already open.")

        val result = CompletableDeferred<PaymentSheetOutcome>()
        pending = result
        try {
            withContext(mainDispatcher) { launcher.launch(session, googlePay) }
            return result.await()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return PaymentSheetOutcome.Failed(e.message)
        } finally {
            if (pending === result) pending = null
        }
    }

    internal fun attach(launcher: SheetLauncher) {
        this.launcher = launcher
    }

    internal fun detach(launcher: SheetLauncher) {
        if (this.launcher === launcher) this.launcher = null
    }

    /** The sheet closed. A result that nobody waits for (the process was recreated meanwhile) is dropped. */
    internal fun onOutcome(outcome: PaymentSheetOutcome) {
        pending?.complete(outcome)
    }
}

/**
 * Binds the Stripe PaymentSheet of this composition to [presenter]. The sheet is created while composing, which is
 * before the Activity is started, as the SDK requires. Call it from the screen that shows the paywall.
 */
@Composable
fun rememberStripePaymentSheetPresenter(presenter: StripePaymentSheetPresenter): StripePaymentSheetPresenter {
    val appContext = LocalContext.current.applicationContext
    val sheet = rememberPaymentSheet { result -> presenter.onOutcome(result.toOutcome()) }
    DisposableEffect(presenter, sheet) {
        val launcher = StripeSheetLauncher(appContext, sheet)
        presenter.attach(launcher)
        onDispose { presenter.detach(launcher) }
    }
    return presenter
}

/** A presenter owned by this composition. Prefer the overload that takes the view model's presenter. */
@Composable
fun rememberStripePaymentSheetPresenter(
    googlePay: GooglePayConfig? = null,
): StripePaymentSheetPresenter = rememberStripePaymentSheetPresenter(remember(googlePay) { StripePaymentSheetPresenter(googlePay) })

internal fun PaymentSheetResult.toOutcome(): PaymentSheetOutcome = when (this) {
    is PaymentSheetResult.Completed -> PaymentSheetOutcome.Completed
    is PaymentSheetResult.Canceled -> PaymentSheetOutcome.Canceled
    is PaymentSheetResult.Failed -> PaymentSheetOutcome.Failed(error.localizedMessage ?: error.message)
}

private class StripeSheetLauncher(
    private val context: Context,
    private val sheet: PaymentSheet,
) : SheetLauncher {

    override fun launch(session: PaymentSession, googlePay: GooglePayConfig?) {
        PaymentConfiguration.init(context, session.publishableKey)
        val configuration = paymentSheetConfiguration(session, googlePay)
        when (session.intentKind) {
            IntentKind.PAYMENT -> sheet.presentWithPaymentIntent(session.intentClientSecret, configuration)
            IntentKind.SETUP -> sheet.presentWithSetupIntent(session.intentClientSecret, configuration)
            IntentKind.UNKNOWN -> throw IllegalArgumentException("Unsupported intent kind")
        }
    }
}

internal fun paymentSheetConfiguration(
    session: PaymentSession,
    googlePay: GooglePayConfig?,
): PaymentSheet.Configuration {
    val builder = PaymentSheet.Configuration.Builder(merchantDisplayName = session.merchantDisplayName)
        .customer(PaymentSheet.CustomerConfiguration(id = session.customerId, ephemeralKeySecret = session.customerEphemeralKeySecret))
        // SEPA debit and similar methods confirm later; the server's webhook activates Premium when they do.
        .allowsDelayedPaymentMethods(true)
    if (googlePay != null) {
        builder.googlePay(
            PaymentSheet.GooglePayConfiguration(
                environment = if (googlePay.production) {
                    PaymentSheet.GooglePayConfiguration.Environment.Production
                } else {
                    PaymentSheet.GooglePayConfiguration.Environment.Test
                },
                countryCode = googlePay.countryCode,
                currencyCode = googlePay.currencyCode,
            ),
        )
    }
    return builder.build()
}
