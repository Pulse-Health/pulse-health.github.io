package com.robinjungerich.pulse.billing

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.mockwebserver.SocketPolicy
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.time.Instant
import java.util.concurrent.TimeUnit

class OkHttpBillingApiTest {

    private lateinit var server: MockWebServer
    private val tokens = ArrayDeque(listOf("token-1", "token-2", "token-3"))
    private var tokenRequests = 0

    private val provider = SessionTokenProvider {
        tokenRequests++
        tokens.removeFirstOrNull() ?: "token-n"
    }

    private lateinit var api: OkHttpBillingApi

    @Before
    fun setUp() {
        server = MockWebServer().apply { start() }
        api = OkHttpBillingApi(server.url("/").toString(), provider)
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    private fun json(body: String, code: Int = 200) = MockResponse().setResponseCode(code).setBody(body)
        .setHeader("Content-Type", "application/json")

    private fun fixture(name: String, code: Int = 200) = json(Fixtures.text(name), code)

    private fun takeRequest(): RecordedRequest = server.takeRequest(5, TimeUnit.SECONDS) ?: fail("No request arrived").let { error("unreachable") }

    private fun RecordedRequest.bodyJson(): JsonObject = Json.parseToJsonElement(body.readUtf8()).jsonObject

    // MARK: - Operations

    @Test
    fun offersIsAGetWithPlatformAndCountry() = runBlocking<Unit> {
        server.enqueue(fixture("offers_available.json"))

        val offers = api.offers("de")

        val request = takeRequest()
        assertEquals("GET", request.method)
        assertEquals("/v1/billing/offers?platform=android&country=DE", request.path)
        assertEquals("Bearer token-1", request.getHeader("Authorization"))
        assertEquals("application/json", request.getHeader("Accept"))
        assertEquals(0L, request.bodySize)
        assertEquals(2, offers.plans.size)
    }

    @Test
    fun offersOmitsACountryThatIsNotTwoLetters() = runBlocking<Unit> {
        for (country in listOf(null, "", "D", "DEU", "1A")) {
            server.enqueue(fixture("offers_available.json"))
            api.offers(country)
            assertEquals("/v1/billing/offers?platform=android", takeRequest().path)
        }
    }

    @Test
    fun entitlementIsAGet() = runBlocking<Unit> {
        server.enqueue(fixture("entitlement_active.json"))

        val response = api.entitlement()

        val request = takeRequest()
        assertEquals("GET", request.method)
        assertEquals("/v1/billing/entitlement", request.path)
        assertEquals("Bearer token-1", request.getHeader("Authorization"))
        assertTrue(response.entitlement.premium)
    }

    @Test
    fun startSubscriptionPostsTheBodyAndTheIdempotencyKey() = runBlocking<Unit> {
        server.enqueue(fixture("subscription_payment.json"))

        val response = api.startSubscription(
            planId = "premium_yearly",
            country = "at",
            billingCountry = "DE",
            consent = WithdrawalConsent(withdrawalWaiver = true, locale = "de-AT"),
            idempotencyKey = "key-123",
        )

        val request = takeRequest()
        assertEquals("POST", request.method)
        assertEquals("/v1/billing/subscriptions", request.path)
        assertEquals("Bearer token-1", request.getHeader("Authorization"))
        assertEquals("key-123", request.getHeader("Idempotency-Key"))
        assertTrue(request.getHeader("Content-Type")!!.startsWith("application/json"))
        val body = request.bodyJson()
        assertEquals(setOf("planId", "platform", "country", "billingCountry", "consent"), body.keys)
        assertEquals("premium_yearly", body.getValue("planId").jsonPrimitive.content)
        assertEquals("android", body.getValue("platform").jsonPrimitive.content)
        assertEquals("AT", body.getValue("country").jsonPrimitive.content)
        assertEquals("DE", body.getValue("billingCountry").jsonPrimitive.content)
        val consent = body.getValue("consent").jsonObject
        assertTrue(consent.getValue("withdrawalWaiver").jsonPrimitive.boolean)
        assertEquals("de-AT", consent.getValue("locale").jsonPrimitive.content)
        assertEquals("sub_FIXTURE", response.subscriptionId)
        assertEquals(IntentKind.PAYMENT, response.intent?.kind)
    }

    @Test
    fun startSubscriptionOmitsWhatIsNotGiven() = runBlocking<Unit> {
        server.enqueue(fixture("subscription_trial_setup.json"))

        api.startSubscription("premium_monthly", null, null, null, "key-1")

        val body = takeRequest().bodyJson()
        assertEquals(setOf("planId", "platform"), body.keys)
    }

    @Test
    fun syncCancelAndResumeArePostsWithoutABody() = runBlocking<Unit> {
        val operations = listOf<Pair<String, suspend () -> EntitlementResponse>>(
            "/v1/billing/sync" to { api.sync() },
            "/v1/billing/subscription/cancel" to { api.cancel() },
            "/v1/billing/subscription/resume" to { api.resume() },
        )
        for ((path, call) in operations) {
            server.enqueue(fixture("entitlement_canceling.json"))
            val response = call()
            val request = takeRequest()
            assertEquals(path, "POST", request.method)
            assertEquals(path, request.path)
            assertTrue(path, request.getHeader("Authorization")!!.startsWith("Bearer "))
            assertEquals(path, 0L, request.bodySize)
            assertTrue(response.entitlement.cancelAtPeriodEnd)
        }
    }

    @Test
    fun portalUrlPostsTheReturnUrl() = runBlocking<Unit> {
        server.enqueue(fixture("portal.json"))

        val url = api.portalUrl("pulse://billing/return")

        val request = takeRequest()
        assertEquals("POST", request.method)
        assertEquals("/v1/billing/portal", request.path)
        assertEquals("pulse://billing/return", request.bodyJson().getValue("returnUrl").jsonPrimitive.content)
        assertEquals("https://billing.stripe.com/p/session/test_FIXTURE", url)
    }

    @Test
    fun deleteAccountIsADelete() = runBlocking<Unit> {
        server.enqueue(fixture("account_deleted.json"))

        api.deleteAccount()

        val request = takeRequest()
        assertEquals("DELETE", request.method)
        assertEquals("/v1/billing/account", request.path)
        assertEquals("Bearer token-1", request.getHeader("Authorization"))
    }

    @Test
    fun deleteAccountThatIsNotReportedAsDeletedFails() = runBlocking<Unit> {
        server.enqueue(json("""{"deleted": false}"""))
        try {
            api.deleteAccount()
            fail("Expected a decoding error")
        } catch (e: BillingError.Decoding) {
            // expected
        }
    }

    @Test
    fun aBaseUrlWithAPathPrefixKeepsItsPrefix() = runBlocking<Unit> {
        val prefixed = OkHttpBillingApi(server.url("/api/").toString(), provider)
        server.enqueue(fixture("entitlement_none.json"))

        prefixed.entitlement()

        assertEquals("/api/v1/billing/entitlement", takeRequest().path)
    }

    // MARK: - 401 retry

    @Test
    fun aUnauthorizedAnswerIsRetriedOnceWithAFreshToken() = runBlocking<Unit> {
        server.enqueue(fixture("error_already_subscribed.json", code = 401).setBody("""{"error":{"code":"unauthorized","message":"expired"}}"""))
        server.enqueue(fixture("entitlement_active.json"))

        val response = api.entitlement()

        assertTrue(response.entitlement.premium)
        assertEquals(2, server.requestCount)
        assertEquals(2, tokenRequests)
        assertEquals("Bearer token-1", takeRequest().getHeader("Authorization"))
        assertEquals("Bearer token-2", takeRequest().getHeader("Authorization"))
    }

    @Test
    fun theRetryOfASubscriptionReusesTheIdempotencyKeyAndTheBody() = runBlocking<Unit> {
        server.enqueue(json("""{"error":{"code":"unauthorized","message":"expired"}}""", 401))
        server.enqueue(fixture("subscription_payment.json"))

        api.startSubscription("premium_monthly", "DE", null, null, "key-abc")

        val first = takeRequest()
        val second = takeRequest()
        assertEquals("key-abc", first.getHeader("Idempotency-Key"))
        assertEquals("key-abc", second.getHeader("Idempotency-Key"))
        assertEquals(first.bodyJson(), second.bodyJson())
        assertEquals("Bearer token-2", second.getHeader("Authorization"))
    }

    @Test
    fun aSecondUnauthorizedAnswerSurfacesAsUnauthorizedWithoutAThirdRequest() = runBlocking<Unit> {
        server.enqueue(json("""{"error":{"code":"unauthorized","message":"expired"}}""", 401))
        server.enqueue(json("""{"error":{"code":"unauthorized","message":"still expired"}}""", 401))
        server.enqueue(fixture("entitlement_active.json"))

        val error = expectApiError { api.entitlement() }

        assertEquals(ErrorCode.UNAUTHORIZED, error.code)
        assertEquals(401, error.status)
        assertTrue(error.isUnauthorized)
        assertEquals(2, server.requestCount)
    }

    @Test
    fun aUnauthorizedAnswerWithoutTheContractBodyIsStillUnauthorized() = runBlocking<Unit> {
        server.enqueue(MockResponse().setResponseCode(401).setBody("<html>nope</html>"))
        server.enqueue(MockResponse().setResponseCode(401))

        val error = expectApiError { api.sync() }

        assertEquals(ErrorCode.UNAUTHORIZED, error.code)
    }

    @Test
    fun otherErrorsAreNotRetried() = runBlocking<Unit> {
        server.enqueue(fixture("error_purchase_not_available.json", code = 403))
        server.enqueue(fixture("entitlement_active.json"))

        expectApiError { api.entitlement() }

        assertEquals(1, server.requestCount)
        assertEquals(1, tokenRequests)
    }

    @Test
    fun noRequestIsSentWhenThereIsNoSessionToken() = runBlocking<Unit> {
        val signedOut = OkHttpBillingApi(server.url("/").toString(), SessionTokenProvider { throw IllegalStateException("signed out") })

        val error = expectApiError { signedOut.entitlement() }

        assertEquals(ErrorCode.UNAUTHORIZED, error.code)
        assertEquals(0, server.requestCount)
    }

    @Test
    fun noRequestIsSentWithABlankToken() = runBlocking<Unit> {
        val blank = OkHttpBillingApi(server.url("/").toString(), SessionTokenProvider { "  " })

        expectApiError { blank.entitlement() }

        assertEquals(0, server.requestCount)
    }

    // MARK: - Errors

    @Test
    fun contractErrorBodiesBecomeTypedErrors() = runBlocking<Unit> {
        val cases = listOf(
            Triple("error_consent_required.json", 400, ErrorCode.CONSENT_REQUIRED),
            Triple("error_purchase_not_available.json", 403, ErrorCode.PURCHASE_NOT_AVAILABLE),
            Triple("error_already_subscribed.json", 409, ErrorCode.ALREADY_SUBSCRIBED),
        )
        for ((file, status, code) in cases) {
            server.enqueue(fixture(file, status))

            val error = expectApiError { api.startSubscription("premium_monthly", "DE", null, null, "key") }

            assertEquals(file, code, error.code)
            assertEquals(file, status, error.status)
            assertTrue(file, error.message.isNotBlank())
            takeRequest()
        }
    }

    @Test
    fun anUnknownErrorCodeBecomesUnknown() = runBlocking<Unit> {
        server.enqueue(json("""{"error":{"code":"quota_exceeded","message":"Over quota."}}""", 402))

        val error = expectApiError { api.sync() }

        assertEquals(ErrorCode.UNKNOWN, error.code)
        assertEquals(402, error.status)
        assertEquals("Over quota.", error.message)
    }

    @Test
    fun anErrorWithoutTheContractBodyKeepsTheStatus() = runBlocking<Unit> {
        server.enqueue(MockResponse().setResponseCode(502).setBody("<html>Bad gateway</html>"))

        val error = expectApiError { api.sync() }

        assertEquals(ErrorCode.UNKNOWN, error.code)
        assertEquals(502, error.status)
        assertEquals("HTTP 502", error.message)
    }

    @Test
    fun rateLimitedAndStripeErrorsKeepTheirCodes() = runBlocking<Unit> {
        server.enqueue(json("""{"error":{"code":"rate_limited","message":"slow down"}}""", 429))
        server.enqueue(json("""{"error":{"code":"stripe_error","message":"upstream"}}""", 502))

        assertEquals(ErrorCode.RATE_LIMITED, expectApiError { api.sync() }.code)
        assertEquals(ErrorCode.STRIPE_ERROR, expectApiError { api.sync() }.code)
    }

    @Test
    fun aDroppedConnectionIsANetworkError() = runBlocking<Unit> {
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AT_START))

        try {
            api.entitlement()
            fail("Expected a network error")
        } catch (e: BillingError.Network) {
            assertFalse(e.message.contains("token-1"))
        }
    }

    @Test
    fun aServerThatIsNotThereIsANetworkError() = runBlocking<Unit> {
        val url = server.url("/").toString()
        server.shutdown()

        try {
            OkHttpBillingApi(url, provider).entitlement()
            fail("Expected a network error")
        } catch (e: BillingError.Network) {
            // expected
        }
    }

    @Test
    fun aSuccessBodyThatIsNotTheContractIsADecodingError() = runBlocking<Unit> {
        server.enqueue(json("""{"hello": "world"}"""))
        server.enqueue(json("not json at all"))

        for (i in 1..2) {
            try {
                api.entitlement()
                fail("Expected a decoding error")
            } catch (e: BillingError.Decoding) {
                assertFalse(e.message.contains("world"))
            }
        }
    }

    @Test
    fun unknownEnumValuesAndFieldsInAResponseDoNotBreakTheCall() = runBlocking<Unit> {
        server.enqueue(
            json(
                """
                {"entitlement": {"premium": true, "status": "grace", "planId": "premium_monthly", "source": "appstore",
                 "currentPeriodEnd": "2026-11-16T10:00:00.250Z", "cancelAtPeriodEnd": false, "trialEnd": null,
                 "premiumUntil": "2026-11-17T10:00:00Z", "newField": 1},
                 "serverTime": "2026-10-16T10:00:00Z", "other": []}
                """.trimIndent(),
            ),
        )

        val e = api.entitlement().entitlement

        assertEquals(EntitlementStatus.UNKNOWN, e.status)
        assertEquals(EntitlementSource.UNKNOWN, e.source)
        assertTrue(e.premium)
        assertEquals(Instant.parse("2026-11-16T10:00:00.250Z"), e.currentPeriodEnd)
        assertNull(e.trialEnd)
    }

    // MARK: - Cancellation

    @Test
    fun cancellingTheCallerCancelsTheRequest() = runBlocking<Unit> {
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
        val job = async(Dispatchers.IO) { api.entitlement() }
        takeRequest()

        withTimeout(5_000) { job.cancelAndJoin() }

        assertTrue(job.isCancelled)
    }

    @Test
    fun theSecretsOfAResponseAreNotInTheErrorMessages() = runBlocking<Unit> {
        server.enqueue(json("""{"error":{"code":"invalid_request","message":"bad"}}""", 400))

        val error = expectApiError { api.startSubscription("p", null, null, null, "key-1") }

        assertFalse(error.message.contains("token-1"))
        assertFalse(error.toString().contains("token-1"))
    }

    private suspend fun expectApiError(block: suspend () -> Unit): BillingError.Api {
        try {
            block()
        } catch (e: BillingError.Api) {
            return e
        }
        fail("Expected BillingError.Api")
        error("unreachable")
    }
}
