package health.pulse.strength.core.widgets

import kotlinx.serialization.json.Json

/** The JSON configuration every widget file and every phone to watch message uses. */
object WidgetJson {
    val json: Json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        explicitNulls = false
        isLenient = false
    }

    fun encodeSnapshot(snapshot: WidgetSnapshot): String = json.encodeToString(WidgetSnapshot.serializer(), snapshot)

    /** Decodes a snapshot; throws [kotlinx.serialization.SerializationException] on a garbled file. */
    fun decodeSnapshot(text: String): WidgetSnapshot = json.decodeFromString(WidgetSnapshot.serializer(), text)

    /** Null instead of an exception for a missing, garbled or newer-schema file. */
    fun decodeSnapshotOrNull(text: String?): WidgetSnapshot? {
        if (text.isNullOrBlank()) return null
        val decoded = try {
            decodeSnapshot(text)
        } catch (_: Exception) {
            return null
        }
        return decoded.takeIf { it.schemaVersion <= WidgetSnapshot.CURRENT_SCHEMA_VERSION }
    }
}
