package com.robinjungerich.pulse.billing.testing

import com.robinjungerich.pulse.billing.*
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset

val NOW: Instant = Instant.parse("2026-10-16T10:00:00Z")

class MutableClock(var instant: Instant = NOW) : Clock() {
    override fun getZone(): ZoneId = ZoneOffset.UTC
    override fun withZone(zone: ZoneId): Clock = this
    override fun instant(): Instant = instant
    fun advance(by: Duration) {
        instant = instant.plus(by)
    }
}

fun plan(
    id: String = "premium_monthly",
    interval: PlanInterval = PlanInterval.MONTH,
    intervalCount: Int = 1,
    currency: String = "eur",
    unitAmount: Long = 999,
    taxBehavior: TaxBehavior = TaxBehavior.INCLUSIVE,
    trialDays: Int = 7,
) = Plan(id, "Pulse Premium", interval, intervalCount, currency, unitAmount, taxBehavior, trialDays)

fun offers(
    available: Boolean = true,
    reason: UnavailableReason? = null,
    requiresWithdrawalConsent: Boolean = true,
    plans: List<Plan> = listOf(plan(), plan("premium_yearly", PlanInterval.YEAR, unitAmount = 7999)),
) = Offers(
    purchase = PurchaseAvailability(available, reason),
    requiresWithdrawalConsent = requiresWithdrawalConsent,
    publishableKey = "pk_test_FIXTURE",
    merchantDisplayName = "Pulse",
    plans = plans,
)

fun premiumEntitlement(until: Instant = NOW.plus(Duration.ofDays(30))) = Entitlement(
    premium = true,
    status = EntitlementStatus.ACTIVE,
    planId = "premium_monthly",
    source = EntitlementSource.STRIPE,
    currentPeriodEnd = until,
    cancelAtPeriodEnd = false,
    premiumUntil = until,
)

fun response(entitlement: Entitlement) = EntitlementResponse(entitlement, NOW)

fun subscription(intent: StripeIntent? = StripeIntent(IntentKind.PAYMENT, "pi_secret_1")) = CreateSubscriptionResponse(
    subscriptionId = "sub_1",
    status = "incomplete",
    customerId = "cus_1",
    customerEphemeralKeySecret = "ek_secret_1",
    publishableKey = "pk_test_FIXTURE",
    intent = intent,
)

fun apiError(code: ErrorCode, status: Int) = BillingError.Api(code, status, code.wire)

/** A scriptable [BillingApi]: each operation takes its next result from a queue and records the call. */
class FakeBillingApi : BillingApi {
    class StartCall(
        val planId: String,
        val country: String?,
        val billingCountry: String?,
        val consent: WithdrawalConsent?,
        val idempotencyKey: String,
    )

    val offersResults = ArrayDeque<Result<Offers>>()
    val entitlementResults = ArrayDeque<Result<EntitlementResponse>>()
    val startResults = ArrayDeque<Result<CreateSubscriptionResponse>>()
    val syncResults = ArrayDeque<Result<EntitlementResponse>>()
    val cancelResults = ArrayDeque<Result<EntitlementResponse>>()
    val resumeResults = ArrayDeque<Result<EntitlementResponse>>()
    val portalResults = ArrayDeque<Result<String>>()

    val offersCalls = mutableListOf<String?>()
    val startCalls = mutableListOf<StartCall>()
    var syncCalls = 0
    var deleteCalls = 0

    override suspend fun offers(country: String?): Offers {
        offersCalls += country
        return offersResults.removeFirst().getOrThrow()
    }

    override suspend fun entitlement(): EntitlementResponse = entitlementResults.removeFirst().getOrThrow()

    override suspend fun startSubscription(
        planId: String,
        country: String?,
        billingCountry: String?,
        consent: WithdrawalConsent?,
        idempotencyKey: String,
    ): CreateSubscriptionResponse {
        startCalls += StartCall(planId, country, billingCountry, consent, idempotencyKey)
        return startResults.removeFirst().getOrThrow()
    }

    override suspend fun sync(): EntitlementResponse {
        syncCalls++
        return syncResults.removeFirst().getOrThrow()
    }

    override suspend fun cancel(): EntitlementResponse = cancelResults.removeFirst().getOrThrow()

    override suspend fun resume(): EntitlementResponse = resumeResults.removeFirst().getOrThrow()

    override suspend fun portalUrl(returnUrl: String): String = portalResults.removeFirst().getOrThrow()

    override suspend fun deleteAccount() {
        deleteCalls++
    }
}

class FakePresenter(var outcome: () -> PaymentSheetOutcome = { PaymentSheetOutcome.Completed }) : PaymentSheetPresenting {
    val sessions = mutableListOf<PaymentSession>()

    override suspend fun present(session: PaymentSession): PaymentSheetOutcome {
        sessions += session
        return outcome()
    }
}
