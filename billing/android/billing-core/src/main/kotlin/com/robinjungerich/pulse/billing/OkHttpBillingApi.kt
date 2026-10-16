// OkHttpBillingApi.kt
// BillingApi over OkHttp. A 401 is retried once with a fresh token, then surfaces as ErrorCode.UNAUTHORIZED; any
// other non-2xx answer becomes BillingError.Api. Nothing is logged: tokens, client secrets and ephemeral keys pass
// through here.

package com.robinjungerich.pulse.billing

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.SerializationException
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.util.Locale
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class OkHttpBillingApi(
    baseUrl: String,
    private val sessionTokens: SessionTokenProvider,
    private val client: OkHttpClient = OkHttpClient(),
    private val platform: Platform = Platform.ANDROID,
) : BillingApi {

    private val base: HttpUrl = baseUrl.toHttpUrl()

    override suspend fun offers(country: String?): Offers =
        send(
            method = "GET",
            path = "offers",
            query = mapOf("platform" to platform.wire, "country" to normalizedCountry(country)),
            strategy = Offers.serializer(),
        )

    override suspend fun entitlement(): EntitlementResponse =
        send("GET", "entitlement", strategy = EntitlementResponse.serializer())

    override suspend fun startSubscription(
        planId: String,
        country: String?,
        billingCountry: String?,
        consent: WithdrawalConsent?,
        idempotencyKey: String,
    ): CreateSubscriptionResponse {
        val request = CreateSubscriptionRequest(
            planId = planId,
            platform = platform,
            country = normalizedCountry(country),
            billingCountry = normalizedCountry(billingCountry),
            consent = consent,
        )
        return send(
            method = "POST",
            path = "subscriptions",
            headers = mapOf("Idempotency-Key" to idempotencyKey),
            body = BillingJson.encodeToString(CreateSubscriptionRequest.serializer(), request),
            strategy = CreateSubscriptionResponse.serializer(),
        )
    }

    override suspend fun sync(): EntitlementResponse =
        send("POST", "sync", body = "", strategy = EntitlementResponse.serializer())

    override suspend fun cancel(): EntitlementResponse =
        send("POST", "subscription/cancel", body = "", strategy = EntitlementResponse.serializer())

    override suspend fun resume(): EntitlementResponse =
        send("POST", "subscription/resume", body = "", strategy = EntitlementResponse.serializer())

    override suspend fun portalUrl(returnUrl: String): String =
        send(
            method = "POST",
            path = "portal",
            body = BillingJson.encodeToString(PortalRequest.serializer(), PortalRequest(returnUrl)),
            strategy = PortalResponse.serializer(),
        ).url

    override suspend fun deleteAccount() {
        val response = send("DELETE", "account", strategy = AccountDeletedResponse.serializer())
        if (!response.deleted) throw BillingError.Decoding(IllegalStateException("The account was not reported as deleted"))
    }

    // MARK: - Transport

    private suspend fun <T> send(
        method: String,
        path: String,
        query: Map<String, String?> = emptyMap(),
        headers: Map<String, String> = emptyMap(),
        body: String? = null,
        strategy: DeserializationStrategy<T>,
    ): T {
        val url = base.newBuilder()
            .addPathSegments("v1/billing/$path")
            .apply { query.forEach { (name, value) -> if (value != null) addQueryParameter(name, value) } }
            .build()

        var raw = execute(method, url, headers, body, token())
        if (raw.status == 401) raw = execute(method, url, headers, body, token())

        if (raw.status !in 200..299) throw apiError(raw)
        return try {
            BillingJson.decodeFromString(strategy, raw.body)
        } catch (e: SerializationException) {
            throw BillingError.Decoding(e)
        } catch (e: IllegalArgumentException) {
            throw BillingError.Decoding(e)
        }
    }

    private suspend fun token(): String {
        val token = try {
            sessionTokens.sessionToken()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            throw BillingError.Api(ErrorCode.UNAUTHORIZED, 401, "No session token is available.", e)
        }
        if (token.isBlank()) throw BillingError.Api(ErrorCode.UNAUTHORIZED, 401, "The session token is empty.")
        return token
    }

    private suspend fun execute(
        method: String,
        url: HttpUrl,
        headers: Map<String, String>,
        body: String?,
        token: String,
    ): RawResponse {
        val request = Request.Builder()
            .url(url)
            .method(method, body?.toRequestBody(JSON))
            .header("Authorization", "Bearer $token")
            .header("Accept", "application/json")
            .apply { headers.forEach { (name, value) -> header(name, value) } }
            .build()
        return try {
            client.newCall(request).await()
        } catch (e: IOException) {
            throw BillingError.Network(e)
        }
    }

    private fun apiError(raw: RawResponse): BillingError.Api {
        val envelope = try {
            BillingJson.decodeFromString(ErrorResponse.serializer(), raw.body).error
        } catch (_: SerializationException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }
        val code = envelope?.code ?: if (raw.status == 401) ErrorCode.UNAUTHORIZED else ErrorCode.UNKNOWN
        return BillingError.Api(code, raw.status, envelope?.message?.ifEmpty { null } ?: "HTTP ${raw.status}")
    }

    private fun normalizedCountry(country: String?): String? =
        country?.trim()?.takeIf { it.length == 2 && it.all(Char::isLetter) }?.uppercase(Locale.ROOT)

    private companion object {
        val JSON = "application/json; charset=utf-8".toMediaType()
    }
}

/** Status and body, read on OkHttp's thread so a caller on the main dispatcher never touches the socket. */
private class RawResponse(val status: Int, val body: String)

private suspend fun Call.await(): RawResponse = suspendCancellableCoroutine { continuation ->
    continuation.invokeOnCancellation { cancel() }
    enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) {
            if (continuation.isActive) continuation.resumeWithException(e)
        }

        override fun onResponse(call: Call, response: Response) {
            val raw = try {
                response.use { RawResponse(it.code, it.body?.string().orEmpty()) }
            } catch (e: IOException) {
                if (continuation.isActive) continuation.resumeWithException(e)
                return
            }
            continuation.resume(raw)
        }
    })
}
