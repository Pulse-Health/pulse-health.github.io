// EntitlementCache.kt
// The last server answer per user, for the billing screens and for offline display. Gating in the host app keeps using
// its existing Premium source (user_premium_access, which the billing server fills for Stripe subscribers).

package com.robinjungerich.pulse.billing

import kotlinx.coroutines.CancellationException
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap

/** How long a cached answer stays usable without the server vouching for it again (same as the Pulse app's PremiumAccessCache). */
val OFFLINE_TRUST_WINDOW: Duration = Duration.ofDays(7)

/** An [entitlement] together with [confirmedAt], the instant the server last vouched for it. */
data class CachedEntitlement(
    val entitlement: Entitlement,
    val confirmedAt: Instant,
) {
    /**
     * Premium, not past `premiumUntil`, and confirmed by the server within [OFFLINE_TRUST_WINDOW]. A premium answer
     * without a `premiumUntil` is not trusted offline.
     */
    fun isPremium(now: Instant): Boolean {
        val until = entitlement.premiumUntil ?: return false
        return entitlement.premium && now.isBefore(until) && Duration.between(confirmedAt, now) <= OFFLINE_TRUST_WINDOW
    }
}

interface EntitlementCache {
    suspend fun load(userId: String): CachedEntitlement?
    suspend fun save(userId: String, cached: CachedEntitlement)
    suspend fun clear(userId: String)
}

class InMemoryEntitlementCache : EntitlementCache {
    private val entries = ConcurrentHashMap<String, CachedEntitlement>()

    override suspend fun load(userId: String): CachedEntitlement? = entries[userId]

    override suspend fun save(userId: String, cached: CachedEntitlement) {
        entries[userId] = cached
    }

    override suspend fun clear(userId: String) {
        entries.remove(userId)
    }
}

/**
 * Wraps a [BillingApi] and records every entitlement the server returns, stamped with the device clock (the trust
 * window is then measured by one clock). The cache is written only after the server answered: a failed request
 * leaves it alone, a successful "not premium" overwrites it.
 */
class CachingBillingApi(
    private val delegate: BillingApi,
    private val cache: EntitlementCache,
    private val userId: String,
    private val clock: Clock = Clock.systemUTC(),
) : BillingApi by delegate {

    override suspend fun entitlement(): EntitlementResponse = delegate.entitlement().also { remember(it) }

    override suspend fun sync(): EntitlementResponse = delegate.sync().also { remember(it) }

    override suspend fun cancel(): EntitlementResponse = delegate.cancel().also { remember(it) }

    override suspend fun resume(): EntitlementResponse = delegate.resume().also { remember(it) }

    override suspend fun deleteAccount() {
        delegate.deleteAccount()
        attempt { cache.clear(userId) }
    }

    private suspend fun remember(response: EntitlementResponse) =
        attempt { cache.save(userId, CachedEntitlement(response.entitlement, clock.instant())) }

    // The server's answer is good even when the device cannot store it, so a storage failure must not fail the call.
    private suspend fun attempt(block: suspend () -> Unit) {
        try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
        }
    }
}
