package com.robinjungerich.pulse.billing

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** Parses every file of billing/contract/fixtures with the client's models. */
class ContractFixturesTest {

    /** Every fixture must be listed here, so a new fixture cannot be added to the contract without a client model. */
    private val parsers: Map<String, (String) -> Any> = mapOf(
        "offers_available.json" to { json: String -> BillingJson.decodeFromString(Offers.serializer(), json) },
        "offers_unavailable_region.json" to { json: String -> BillingJson.decodeFromString(Offers.serializer(), json) },
        "entitlement_none.json" to { json: String -> BillingJson.decodeFromString(EntitlementResponse.serializer(), json) },
        "entitlement_active.json" to { json: String -> BillingJson.decodeFromString(EntitlementResponse.serializer(), json) },
        "entitlement_canceling.json" to { json: String -> BillingJson.decodeFromString(EntitlementResponse.serializer(), json) },
        "entitlement_past_due.json" to { json: String -> BillingJson.decodeFromString(EntitlementResponse.serializer(), json) },
        "subscription_payment.json" to { json: String -> BillingJson.decodeFromString(CreateSubscriptionResponse.serializer(), json) },
        "subscription_trial_setup.json" to { json: String -> BillingJson.decodeFromString(CreateSubscriptionResponse.serializer(), json) },
        "portal.json" to { json: String -> BillingJson.decodeFromString(PortalResponse.serializer(), json) },
        "account_deleted.json" to { json: String -> BillingJson.decodeFromString(AccountDeletedResponse.serializer(), json) },
        "error_already_subscribed.json" to { json: String -> BillingJson.decodeFromString(ErrorResponse.serializer(), json) },
        "error_purchase_not_available.json" to { json: String -> BillingJson.decodeFromString(ErrorResponse.serializer(), json) },
        "error_consent_required.json" to { json: String -> BillingJson.decodeFromString(ErrorResponse.serializer(), json) },
    )

    @Test
    fun fixturesDirectoryExists() {
        assertTrue(Fixtures.names().isNotEmpty())
    }

    @Test
    fun everyFixtureFileIsCoveredByAParser() {
        assertEquals(
            "A fixture was added or removed without updating ContractFixturesTest",
            parsers.keys.sorted(),
            Fixtures.names(),
        )
    }

    @Test
    fun everyFixtureParses() {
        for (name in Fixtures.names()) {
            val parse = parsers[name] ?: error("No parser for $name")
            try {
                parse(Fixtures.text(name))
            } catch (e: Exception) {
                throw AssertionError("$name does not parse: ${e.message}", e)
            }
        }
    }

    @Test
    fun offersAvailable() {
        val offers = decode<Offers>("offers_available.json")
        assertTrue(offers.purchase.available)
        assertNull(offers.purchase.reason)
        assertTrue(offers.requiresWithdrawalConsent)
        assertEquals("pk_test_FIXTURE", offers.publishableKey)
        assertEquals("Pulse", offers.merchantDisplayName)
        assertEquals(listOf("premium_monthly", "premium_yearly"), offers.plans.map { it.id })
        val monthly = offers.plans[0]
        assertEquals(PlanInterval.MONTH, monthly.interval)
        assertEquals(1, monthly.intervalCount)
        assertEquals("eur", monthly.currency)
        assertEquals(999L, monthly.unitAmount)
        assertEquals(TaxBehavior.INCLUSIVE, monthly.taxBehavior)
        assertEquals(7, monthly.trialDays)
        assertTrue(monthly.hasTrial)
        assertEquals(PlanInterval.YEAR, offers.plans[1].interval)
        assertEquals(7999L, offers.plans[1].unitAmount)
    }

    @Test
    fun offersUnavailableInRegion() {
        val offers = decode<Offers>("offers_unavailable_region.json")
        assertFalse(offers.purchase.available)
        assertEquals(UnavailableReason.REGION_NOT_SUPPORTED, offers.purchase.reason)
        assertTrue(offers.plans.isEmpty())
    }

    @Test
    fun entitlementNone() {
        val response = decode<EntitlementResponse>("entitlement_none.json")
        assertEquals(Entitlement.NONE, response.entitlement)
        assertEquals(Instant.parse("2026-10-16T10:00:00Z"), response.serverTime)
    }

    @Test
    fun entitlementActive() {
        val e = decode<EntitlementResponse>("entitlement_active.json").entitlement
        assertTrue(e.premium)
        assertEquals(EntitlementStatus.ACTIVE, e.status)
        assertEquals("premium_monthly", e.planId)
        assertEquals(EntitlementSource.STRIPE, e.source)
        assertEquals(Instant.parse("2026-11-16T10:00:00Z"), e.currentPeriodEnd)
        assertFalse(e.cancelAtPeriodEnd)
        assertNull(e.trialEnd)
        assertEquals(Instant.parse("2026-11-17T10:00:00Z"), e.premiumUntil)
    }

    @Test
    fun entitlementCanceling() {
        val e = decode<EntitlementResponse>("entitlement_canceling.json").entitlement
        assertTrue(e.premium)
        assertTrue(e.cancelAtPeriodEnd)
        assertEquals("premium_yearly", e.planId)
        assertEquals(e.currentPeriodEnd, e.premiumUntil)
    }

    @Test
    fun entitlementPastDue() {
        val e = decode<EntitlementResponse>("entitlement_past_due.json").entitlement
        assertTrue(e.premium)
        assertEquals(EntitlementStatus.PAST_DUE, e.status)
        assertEquals(Instant.parse("2026-10-18T10:00:00Z"), e.premiumUntil)
    }

    @Test
    fun subscriptionPayment() {
        val s = decode<CreateSubscriptionResponse>("subscription_payment.json")
        assertEquals("sub_FIXTURE", s.subscriptionId)
        assertEquals("incomplete", s.status)
        assertEquals("cus_FIXTURE", s.customerId)
        assertEquals("ek_test_FIXTURE", s.customerEphemeralKeySecret)
        assertEquals("pk_test_FIXTURE", s.publishableKey)
        assertEquals(IntentKind.PAYMENT, s.intent?.kind)
        assertEquals("pi_FIXTURE_secret_FIXTURE", s.intent?.clientSecret)
    }

    @Test
    fun subscriptionTrialSetup() {
        val s = decode<CreateSubscriptionResponse>("subscription_trial_setup.json")
        assertEquals("trialing", s.status)
        assertEquals(IntentKind.SETUP, s.intent?.kind)
        assertEquals("seti_FIXTURE_secret_FIXTURE", s.intent?.clientSecret)
    }

    @Test
    fun portal() {
        assertEquals("https://billing.stripe.com/p/session/test_FIXTURE", decode<PortalResponse>("portal.json").url)
    }

    @Test
    fun accountDeleted() {
        assertTrue(decode<AccountDeletedResponse>("account_deleted.json").deleted)
    }

    @Test
    fun errorBodies() {
        val expected = mapOf(
            "error_already_subscribed.json" to ErrorCode.ALREADY_SUBSCRIBED,
            "error_purchase_not_available.json" to ErrorCode.PURCHASE_NOT_AVAILABLE,
            "error_consent_required.json" to ErrorCode.CONSENT_REQUIRED,
        )
        for ((file, code) in expected) {
            val body = decode<ErrorResponse>(file).error
            assertEquals(file, code, body.code)
            assertTrue(file, body.message.isNotBlank())
        }
    }

    @Test
    fun noFixtureDecodesToAnUnknownCase() {
        // The fixtures are the contract's own examples: if one decodes to UNKNOWN, a client enum is missing a value.
        val offers = decode<Offers>("offers_available.json")
        assertTrue(offers.plans.none { it.interval == PlanInterval.UNKNOWN || it.taxBehavior == TaxBehavior.UNKNOWN })
        for (file in listOf("entitlement_none.json", "entitlement_active.json", "entitlement_canceling.json", "entitlement_past_due.json")) {
            val e = decode<EntitlementResponse>(file).entitlement
            assertNotNull(e)
            assertTrue(file, e.status != EntitlementStatus.UNKNOWN && e.source != EntitlementSource.UNKNOWN)
        }
        for (file in listOf("subscription_payment.json", "subscription_trial_setup.json")) {
            assertTrue(file, decode<CreateSubscriptionResponse>(file).intent!!.kind != IntentKind.UNKNOWN)
        }
        for (file in listOf("error_already_subscribed.json", "error_purchase_not_available.json", "error_consent_required.json")) {
            assertTrue(file, decode<ErrorResponse>(file).error.code != ErrorCode.UNKNOWN)
        }
        assertTrue(decode<Offers>("offers_unavailable_region.json").purchase.reason != UnavailableReason.UNKNOWN)
    }

    private inline fun <reified T : Any> decode(file: String): T = parsers.getValue(file)(Fixtures.text(file)) as T
}
