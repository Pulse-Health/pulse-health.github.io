package com.robinjungerich.pulse.billing

import com.robinjungerich.pulse.billing.testing.FakeBillingApi
import com.robinjungerich.pulse.billing.testing.MutableClock
import com.robinjungerich.pulse.billing.testing.NOW
import com.robinjungerich.pulse.billing.testing.apiError
import com.robinjungerich.pulse.billing.testing.premiumEntitlement
import com.robinjungerich.pulse.billing.testing.response
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.IOException
import java.time.Duration

class EntitlementCacheTest {

    private val clock = MutableClock()
    private val cache = InMemoryEntitlementCache()
    private val api = FakeBillingApi()
    private val caching = CachingBillingApi(api, cache, userId = "user_1", clock = clock)

    // MARK: - The offline rule

    @Test
    fun premiumWithinTheTrustWindowAndBeforePremiumUntilIsPremium() {
        val cached = CachedEntitlement(premiumEntitlement(until = NOW.plus(Duration.ofDays(30))), confirmedAt = NOW)

        assertTrue(cached.isPremium(NOW))
        assertTrue(cached.isPremium(NOW.plus(Duration.ofDays(6))))
    }

    @Test
    fun theTrustWindowIsSevenDaysInclusive() {
        val cached = CachedEntitlement(premiumEntitlement(until = NOW.plus(Duration.ofDays(60))), confirmedAt = NOW)

        assertTrue(cached.isPremium(NOW.plus(Duration.ofDays(7))))
        assertFalse(cached.isPremium(NOW.plus(Duration.ofDays(7)).plusMillis(1)))
    }

    @Test
    fun premiumUntilIsExclusive() {
        val until = NOW.plus(Duration.ofDays(3))
        val cached = CachedEntitlement(premiumEntitlement(until = until), confirmedAt = NOW)

        assertTrue(cached.isPremium(until.minusMillis(1)))
        assertFalse(cached.isPremium(until))
        assertFalse(cached.isPremium(until.plusSeconds(1)))
    }

    @Test
    fun aCachedAnswerThatIsNotPremiumIsNeverPremium() {
        val cached = CachedEntitlement(Entitlement.NONE, confirmedAt = NOW)

        assertFalse(cached.isPremium(NOW))
    }

    @Test
    fun premiumWithoutPremiumUntilIsNotTrustedOffline() {
        val cached = CachedEntitlement(premiumEntitlement().copy(premiumUntil = null), confirmedAt = NOW)

        assertFalse(cached.isPremium(NOW))
    }

    @Test
    fun aPremiumFlagFalseWithAFutureUntilIsNotPremium() {
        val cached = CachedEntitlement(premiumEntitlement().copy(premium = false), confirmedAt = NOW)

        assertFalse(cached.isPremium(NOW))
    }

    @Test
    fun theCacheKeepsUsersApart() = runTest {
        cache.save("user_1", CachedEntitlement(premiumEntitlement(), NOW))

        assertNull(cache.load("user_2"))
        assertTrue(cache.load("user_1")!!.entitlement.premium)

        cache.clear("user_1")
        assertNull(cache.load("user_1"))
    }

    // MARK: - What gets written

    @Test
    fun aSuccessfulFetchIsStoredWithTheDeviceClock() = runTest {
        api.entitlementResults += Result.success(response(premiumEntitlement()))

        caching.entitlement()

        val cached = cache.load("user_1")!!
        assertEquals(premiumEntitlement(), cached.entitlement)
        assertEquals(NOW, cached.confirmedAt)
    }

    @Test
    fun aFailedFetchNeverOverwritesTheCache() = runTest {
        api.entitlementResults += Result.success(response(premiumEntitlement()))
        caching.entitlement()
        val before = cache.load("user_1")
        clock.advance(Duration.ofDays(1))
        api.entitlementResults += Result.failure(BillingError.Network(IOException("offline")))
        api.entitlementResults += Result.failure(apiError(ErrorCode.INTERNAL, 500))
        api.entitlementResults += Result.failure(BillingError.Decoding(IllegalStateException("garbled")))
        api.entitlementResults += Result.failure(apiError(ErrorCode.UNAUTHORIZED, 401))

        repeat(4) {
            try {
                caching.entitlement()
                fail("Expected an error")
            } catch (_: BillingError) {
            }
        }

        assertEquals(before, cache.load("user_1"))
        assertTrue(cache.load("user_1")!!.isPremium(clock.instant()))
    }

    @Test
    fun aSuccessfulNotPremiumAnswerOverwritesTheCache() = runTest {
        api.entitlementResults += Result.success(response(premiumEntitlement()))
        caching.entitlement()
        clock.advance(Duration.ofDays(2))
        api.entitlementResults += Result.success(response(Entitlement.NONE))

        caching.entitlement()

        val cached = cache.load("user_1")!!
        assertEquals(Entitlement.NONE, cached.entitlement)
        assertEquals(clock.instant(), cached.confirmedAt)
        assertFalse(cached.isPremium(clock.instant()))
    }

    @Test
    fun syncCancelAndResumeAreStoredToo() = runTest {
        api.syncResults += Result.success(response(premiumEntitlement()))
        caching.sync()
        assertFalse(cache.load("user_1")!!.entitlement.cancelAtPeriodEnd)

        api.cancelResults += Result.success(response(premiumEntitlement().copy(cancelAtPeriodEnd = true)))
        caching.cancel()
        assertTrue(cache.load("user_1")!!.entitlement.cancelAtPeriodEnd)

        api.resumeResults += Result.success(response(premiumEntitlement()))
        caching.resume()
        assertFalse(cache.load("user_1")!!.entitlement.cancelAtPeriodEnd)
    }

    @Test
    fun aFailedCancelLeavesTheCacheAlone() = runTest {
        api.entitlementResults += Result.success(response(premiumEntitlement()))
        caching.entitlement()
        val before = cache.load("user_1")
        api.cancelResults += Result.failure(apiError(ErrorCode.NO_SUBSCRIPTION, 404))

        try {
            caching.cancel()
            fail("Expected an error")
        } catch (_: BillingError.Api) {
        }

        assertEquals(before, cache.load("user_1"))
    }

    @Test
    fun deletingTheAccountClearsTheCache() = runTest {
        api.entitlementResults += Result.success(response(premiumEntitlement()))
        caching.entitlement()

        caching.deleteAccount()

        assertEquals(1, api.deleteCalls)
        assertNull(cache.load("user_1"))
    }

    @Test
    fun otherOperationsPassThrough() = runTest {
        api.offersResults += Result.success(com.robinjungerich.pulse.billing.testing.offers())
        api.portalResults += Result.success("https://billing.stripe.com/p/session/x")

        assertEquals(2, caching.offers("DE").plans.size)
        assertEquals("https://billing.stripe.com/p/session/x", caching.portalUrl("pulse://return"))
        assertNull(cache.load("user_1"))
    }

    @Test
    fun aCacheThatCannotBeWrittenDoesNotFailTheCall() = runTest {
        val broken = object : EntitlementCache {
            override suspend fun load(userId: String): CachedEntitlement? = null
            override suspend fun save(userId: String, cached: CachedEntitlement) = throw IOException("disk full")
            override suspend fun clear(userId: String) = throw IOException("disk full")
        }
        val tolerant = CachingBillingApi(api, broken, "user_1", clock)
        api.entitlementResults += Result.success(response(premiumEntitlement()))

        assertTrue(tolerant.entitlement().entitlement.premium)
    }
}
