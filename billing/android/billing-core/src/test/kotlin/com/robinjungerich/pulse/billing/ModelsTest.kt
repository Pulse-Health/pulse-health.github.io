package com.robinjungerich.pulse.billing

import kotlinx.serialization.SerializationException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class ModelsTest {

    private fun entitlementJson(
        status: String = "active",
        source: String = "stripe",
        currentPeriodEnd: String? = "\"2026-11-16T10:00:00Z\"",
        extra: String = "",
    ) = """
        {
          "entitlement": {
            "premium": true, "status": "$status", "planId": "premium_monthly", "source": "$source",
            "currentPeriodEnd": $currentPeriodEnd, "cancelAtPeriodEnd": false, "trialEnd": null,
            "premiumUntil": "2026-11-17T10:00:00Z"$extra
          },
          "serverTime": "2026-10-16T10:00:00Z"
        }
    """.trimIndent()

    private fun decodeEntitlement(json: String) = BillingJson.decodeFromString(EntitlementResponse.serializer(), json)

    @Test
    fun unknownEntitlementStatusDecodesToUnknown() {
        assertEquals(EntitlementStatus.UNKNOWN, decodeEntitlement(entitlementJson(status = "somethingNew")).entitlement.status)
    }

    @Test
    fun unknownEntitlementSourceDecodesToUnknownAndStaysPremium() {
        val e = decodeEntitlement(entitlementJson(source = "appstore")).entitlement
        assertEquals(EntitlementSource.UNKNOWN, e.source)
        assertTrue(e.premium)
    }

    @Test
    fun unknownValuesOfEveryOtherEnumDecodeToUnknown() {
        val offers = BillingJson.decodeFromString(
            Offers.serializer(),
            """
            {"purchase": {"available": false, "reason": "maintenance"}, "requiresWithdrawalConsent": false,
             "publishableKey": "pk", "merchantDisplayName": "Pulse",
             "plans": [{"id": "p", "name": "P", "interval": "week", "intervalCount": 1, "currency": "eur",
                        "unitAmount": 100, "taxBehavior": "reverse_charge", "trialDays": 0}]}
            """.trimIndent(),
        )
        assertEquals(UnavailableReason.UNKNOWN, offers.purchase.reason)
        assertEquals(PlanInterval.UNKNOWN, offers.plans.single().interval)
        assertEquals(TaxBehavior.UNKNOWN, offers.plans.single().taxBehavior)

        val intent = BillingJson.decodeFromString(StripeIntent.serializer(), """{"kind": "deferred", "clientSecret": "x"}""")
        assertEquals(IntentKind.UNKNOWN, intent.kind)

        val error = BillingJson.decodeFromString(ErrorResponse.serializer(), """{"error": {"code": "teapot", "message": "m"}}""")
        assertEquals(ErrorCode.UNKNOWN, error.error.code)
    }

    @Test
    fun aKnownValueNeverFallsBackToUnknown() {
        for (status in EntitlementStatus.entries.filter { it != EntitlementStatus.UNKNOWN }) {
            assertEquals(status, decodeEntitlement(entitlementJson(status = status.wire)).entitlement.status)
        }
        for (code in ErrorCode.entries.filter { it != ErrorCode.UNKNOWN }) {
            val body = BillingJson.decodeFromString(ErrorResponse.serializer(), """{"error": {"code": "${code.wire}", "message": ""}}""")
            assertEquals(code, body.error.code)
        }
    }

    @Test
    fun unknownFieldsAreIgnoredAtEveryLevel() {
        val response = decodeEntitlement(entitlementJson(extra = ""","futureField": {"a": [1, 2]}""").replace(
            "\"serverTime\"",
            "\"alsoNew\": true, \"serverTime\"",
        ))
        assertTrue(response.entitlement.premium)
    }

    @Test
    fun datesAcceptFractionalSecondsAndOffsets() {
        assertEquals(Instant.parse("2026-11-16T10:00:00Z"), parseInstant("2026-11-16T10:00:00Z"))
        assertEquals(Instant.parse("2026-11-16T10:00:00.250Z"), parseInstant("2026-11-16T10:00:00.250Z"))
        assertEquals(Instant.parse("2026-11-16T10:00:00.123456Z"), parseInstant("2026-11-16T10:00:00.123456Z"))
        assertEquals(Instant.parse("2026-11-16T09:00:00Z"), parseInstant("2026-11-16T10:00:00+01:00"))

        val e = decodeEntitlement(entitlementJson(currentPeriodEnd = "\"2026-11-16T10:00:00.5Z\"")).entitlement
        assertEquals(Instant.parse("2026-11-16T10:00:00.5Z"), e.currentPeriodEnd)
    }

    @Test
    fun aMalformedDateFailsTheDecode() {
        assertThrows(SerializationException::class.java) {
            decodeEntitlement(entitlementJson(currentPeriodEnd = "\"next tuesday\""))
        }
    }

    @Test
    fun aMissingRequiredFieldFailsTheDecode() {
        assertThrows(SerializationException::class.java) {
            BillingJson.decodeFromString(EntitlementResponse.serializer(), """{"serverTime": "2026-10-16T10:00:00Z"}""")
        }
    }

    @Test
    fun aMissingNullableFieldDecodesToNull() {
        val response = decodeEntitlement(
            """{"entitlement": {"premium": false, "status": "none", "source": "none", "cancelAtPeriodEnd": false},
                "serverTime": "2026-10-16T10:00:00Z"}""",
        )
        assertEquals(Entitlement.NONE, response.entitlement)
    }

    @Test
    fun subscriptionResponseWithoutIntentDecodes() {
        val s = BillingJson.decodeFromString(
            CreateSubscriptionResponse.serializer(),
            """{"subscriptionId": "s", "status": "active", "customerId": "c", "customerEphemeralKeySecret": "e",
                "publishableKey": "pk", "intent": null}""",
        )
        assertNull(s.intent)
    }

    @Test
    fun secretsAreRedactedInToString() {
        val s = subscriptionForRedaction()
        val text = s.toString()
        assertFalse(text, text.contains("ek_secret_1"))
        assertFalse(text, text.contains("pi_secret_1"))
        assertTrue(text.contains("sub_1"))

        val session = PaymentSession("cus_1", "ek_secret_1", "pk_test", "Pulse", IntentKind.PAYMENT, "pi_secret_1")
        assertFalse(session.toString().contains("ek_secret_1"))
        assertFalse(session.toString().contains("pi_secret_1"))
    }

    @Test
    fun requestBodyOmitsNullsAndNamesTheWireValues() {
        val body = BillingJson.encodeToString(
            CreateSubscriptionRequest.serializer(),
            CreateSubscriptionRequest("premium_monthly", Platform.ANDROID, country = "DE"),
        )
        assertEquals("""{"planId":"premium_monthly","platform":"android","country":"DE"}""", body)
    }

    private fun subscriptionForRedaction() = CreateSubscriptionResponse(
        subscriptionId = "sub_1",
        status = "incomplete",
        customerId = "cus_1",
        customerEphemeralKeySecret = "ek_secret_1",
        publishableKey = "pk_test",
        intent = StripeIntent(IntentKind.PAYMENT, "pi_secret_1"),
    )
}
