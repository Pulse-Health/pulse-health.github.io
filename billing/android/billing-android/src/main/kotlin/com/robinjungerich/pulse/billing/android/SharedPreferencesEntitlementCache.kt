// SharedPreferencesEntitlementCache.kt
// The EntitlementCache on the device: one JSON value per user in a private SharedPreferences file.

package com.robinjungerich.pulse.billing.android

import android.content.Context
import android.content.SharedPreferences
import com.robinjungerich.pulse.billing.CachedEntitlement
import com.robinjungerich.pulse.billing.Entitlement
import com.robinjungerich.pulse.billing.EntitlementCache
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import java.io.IOException
import java.time.Instant

class SharedPreferencesEntitlementCache(
    private val preferences: SharedPreferences,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) : EntitlementCache {

    constructor(context: Context) : this(context.applicationContext.getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE))

    @Serializable
    private class Stored(val entitlement: Entitlement, val confirmedAtEpochMillis: Long)

    override suspend fun load(userId: String): CachedEntitlement? = withContext(io) {
        val raw = preferences.getString(key(userId), null) ?: return@withContext null
        try {
            val stored = json.decodeFromString(Stored.serializer(), raw)
            CachedEntitlement(stored.entitlement, Instant.ofEpochMilli(stored.confirmedAtEpochMillis))
        } catch (_: SerializationException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    override suspend fun save(userId: String, cached: CachedEntitlement) {
        val raw = json.encodeToString(Stored.serializer(), Stored(cached.entitlement, cached.confirmedAt.toEpochMilli()))
        withContext(io) {
            if (!preferences.edit().putString(key(userId), raw).commit()) throw IOException("The entitlement could not be saved.")
        }
    }

    override suspend fun clear(userId: String) {
        withContext(io) {
            if (!preferences.edit().remove(key(userId)).commit()) throw IOException("The entitlement could not be removed.")
        }
    }

    private fun key(userId: String) = "entitlement.$userId"

    private companion object {
        const val FILE_NAME = "pulse_billing_entitlements"
        val json = Json { ignoreUnknownKeys = true }
    }
}
