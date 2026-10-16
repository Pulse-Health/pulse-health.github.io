package health.pulse.strength.core.widgets

import health.pulse.strength.core.StrengthConfig
import java.net.URI
import java.net.URISyntaxException
import java.net.URLDecoder
import java.net.URLEncoder
import java.util.UUID

/**
 * A parsed `pulse-strength://` link (widgets/SPEC.md section 4): what the app does when a widget, tile, notification or the launcher
 * opens it. Surfaces build the strings with [DeepLinks]; the main activity reads them with [parse]. Same rules as the Swift `StrengthDeepLink`.
 */
sealed interface StrengthDeepLink {
    /** Open the running workout. */
    data object Workout : StrengthDeepLink

    /** Start the suggested next template. */
    data object StartNext : StrengthDeepLink

    /** Start one template. */
    data class Start(val templateId: UUID) : StrengthDeepLink

    /** Start an empty workout with a name. */
    data class StartEmpty(val name: String) : StrengthDeepLink

    /** Open the detail of an exercise. */
    data class Exercise(val id: String) : StrengthDeepLink

    /** Open the Strength hub. */
    data object Hub : StrengthDeepLink

    /** Open the running workout on the plate calculator. */
    data object Plates : StrengthDeepLink

    /** Open the body weight entry. */
    data object Weight : StrengthDeepLink

    /** The link as the text a surface puts into an intent. */
    val url: String
        get() = when (this) {
            Workout -> DeepLinks.workout
            StartNext -> DeepLinks.startNext
            is Start -> DeepLinks.start(templateId.toString().lowercase())
            is StartEmpty -> DeepLinks.startEmpty(name)
            is Exercise -> DeepLinks.exercise(id)
            Hub -> DeepLinks.hub
            Plates -> DeepLinks.plates
            Weight -> DeepLinks.weight
        }

    companion object {
        /** The link behind [text]; null for another scheme, an unknown host or a malformed argument. */
        fun parse(text: String?): StrengthDeepLink? {
            if (text.isNullOrBlank()) return null
            val uri = try {
                URI(text)
            } catch (_: URISyntaxException) {
                return null
            }
            if (!StrengthConfig.urlScheme.equals(uri.scheme, ignoreCase = true)) return null
            val query = queryItems(uri.rawQuery)
            return when (uri.host?.lowercase()) {
                "workout" -> Workout
                "start-next" -> StartNext
                "hub" -> Hub
                "plates" -> Plates
                "weight" -> Weight
                "start" -> query["template"]?.let { parseUuid(it) }?.let { Start(it) }
                "start-empty" -> StartEmpty(query["name"]?.trim().orEmpty().ifEmpty { StrengthConfig.defaultWorkoutName })
                "exercise" -> decode(uri.rawPath.orEmpty().trimStart('/').substringBefore('/')).takeIf { it.isNotEmpty() }?.let { Exercise(it) }
                else -> null
            }
        }

        private fun queryItems(rawQuery: String?): Map<String, String> {
            if (rawQuery.isNullOrEmpty()) return emptyMap()
            val items = LinkedHashMap<String, String>()
            for (pair in rawQuery.split('&')) {
                val index = pair.indexOf('=')
                val name = decode(if (index < 0) pair else pair.substring(0, index))
                if (name.isEmpty() || name in items) continue
                items[name] = if (index < 0) "" else decode(pair.substring(index + 1))
            }
            return items
        }

        private fun parseUuid(text: String): UUID? = try {
            UUID.fromString(text)
        } catch (_: IllegalArgumentException) {
            null
        }

        private fun decode(text: String): String = try {
            URLDecoder.decode(text, Charsets.UTF_8)
        } catch (_: IllegalArgumentException) {
            text
        }

        internal fun encode(text: String): String = URLEncoder.encode(text, Charsets.UTF_8).replace("+", "%20")
    }
}
