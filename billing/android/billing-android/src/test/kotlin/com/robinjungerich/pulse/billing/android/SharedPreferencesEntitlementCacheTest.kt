package com.robinjungerich.pulse.billing.android

import android.content.SharedPreferences
import com.robinjungerich.pulse.billing.CachedEntitlement
import com.robinjungerich.pulse.billing.Entitlement
import com.robinjungerich.pulse.billing.EntitlementSource
import com.robinjungerich.pulse.billing.EntitlementStatus
import com.robinjungerich.pulse.billing.testing.NOW
import com.robinjungerich.pulse.billing.testing.premiumEntitlement
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test
import java.io.IOException
import java.time.Instant

class SharedPreferencesEntitlementCacheTest {

    private val preferences = FakeSharedPreferences()
    private val cache = SharedPreferencesEntitlementCache(preferences, Dispatchers.Unconfined)

    @Test
    fun anEntitlementSurvivesARoundTrip() = runTest {
        val cached = CachedEntitlement(premiumEntitlement(), NOW)

        cache.save("user_1", cached)

        assertEquals(cached, cache.load("user_1"))
    }

    @Test
    fun everyFieldOfAnEntitlementIsKept() = runTest {
        val entitlement = Entitlement(
            premium = true,
            status = EntitlementStatus.TRIALING,
            planId = "premium_yearly",
            source = EntitlementSource.STRIPE,
            currentPeriodEnd = Instant.parse("2026-11-16T10:00:00Z"),
            cancelAtPeriodEnd = true,
            trialEnd = Instant.parse("2026-10-23T10:00:00Z"),
            premiumUntil = Instant.parse("2026-11-16T10:00:00.5Z"),
        )

        cache.save("user_1", CachedEntitlement(entitlement, Instant.parse("2026-10-16T10:00:00.123Z")))

        assertEquals(entitlement, cache.load("user_1")!!.entitlement)
        assertEquals(Instant.parse("2026-10-16T10:00:00.123Z"), cache.load("user_1")!!.confirmedAt)
    }

    @Test
    fun valuesOfFutureServerVersionsSurviveTheCache() = runTest {
        val entitlement = premiumEntitlement().copy(status = EntitlementStatus.UNKNOWN, source = EntitlementSource.UNKNOWN)

        cache.save("user_1", CachedEntitlement(entitlement, NOW))

        assertEquals(entitlement, cache.load("user_1")!!.entitlement)
    }

    @Test
    fun usersAreKeptApart() = runTest {
        cache.save("user_1", CachedEntitlement(premiumEntitlement(), NOW))

        assertNull(cache.load("user_2"))
    }

    @Test
    fun clearRemovesOnlyThatUser() = runTest {
        cache.save("user_1", CachedEntitlement(premiumEntitlement(), NOW))
        cache.save("user_2", CachedEntitlement(Entitlement.NONE, NOW))

        cache.clear("user_1")

        assertNull(cache.load("user_1"))
        assertEquals(Entitlement.NONE, cache.load("user_2")!!.entitlement)
    }

    @Test
    fun nothingStoredMeansNull() = runTest {
        assertNull(cache.load("user_1"))
    }

    @Test
    fun unreadableContentIsTreatedAsNothingStored() = runTest {
        for (garbage in listOf("", "not json", "{}", """{"entitlement": {"premium": "yes"}, "confirmedAtEpochMillis": 1}""")) {
            preferences.values["entitlement.user_1"] = garbage
            assertNull(garbage, cache.load("user_1"))
        }
    }

    @Test
    fun aWriteThatFailsIsReported() = runTest {
        preferences.commitSucceeds = false

        try {
            cache.save("user_1", CachedEntitlement(premiumEntitlement(), NOW))
            fail("Expected an IOException")
        } catch (_: IOException) {
            // expected
        }
    }
}

/** An in-memory SharedPreferences; only what the cache uses is implemented. */
internal class FakeSharedPreferences : SharedPreferences {
    val values = mutableMapOf<String, Any?>()
    var commitSucceeds = true

    override fun getString(key: String, defValue: String?): String? = values[key] as String? ?: defValue
    override fun getAll(): MutableMap<String, *> = values
    override fun getStringSet(key: String, defValues: MutableSet<String>?): MutableSet<String>? = defValues
    override fun getInt(key: String, defValue: Int) = defValue
    override fun getLong(key: String, defValue: Long) = defValue
    override fun getFloat(key: String, defValue: Float) = defValue
    override fun getBoolean(key: String, defValue: Boolean) = defValue
    override fun contains(key: String) = values.containsKey(key)
    override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener) = Unit
    override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener) = Unit

    override fun edit(): SharedPreferences.Editor = object : SharedPreferences.Editor {
        private val pending = mutableMapOf<String, Any?>()
        private val removed = mutableSetOf<String>()

        override fun putString(key: String, value: String?): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun remove(key: String): SharedPreferences.Editor {
            removed += key
            return this
        }

        override fun commit(): Boolean {
            if (!commitSucceeds) return false
            removed.forEach { values.remove(it) }
            values.putAll(pending)
            return true
        }

        override fun apply() {
            commit()
        }

        override fun putStringSet(key: String, values: MutableSet<String>?): SharedPreferences.Editor = this
        override fun putInt(key: String, value: Int): SharedPreferences.Editor = this
        override fun putLong(key: String, value: Long): SharedPreferences.Editor = this
        override fun putFloat(key: String, value: Float): SharedPreferences.Editor = this
        override fun putBoolean(key: String, value: Boolean): SharedPreferences.Editor = this
        override fun clear(): SharedPreferences.Editor = this
    }
}
