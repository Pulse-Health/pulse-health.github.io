package health.pulse.strength.ui.hub

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.setValue
import java.util.UUID

// Navigation targets of the hub (HubRoute and HubEditorTarget of StrengthHubView.swift). The hub keeps its own small back stack
// instead of a navigation library: every route has a stable text form, so the stack survives rotation and process death.

internal sealed interface HubRoute {
    data object Library : HubRoute
    data object Templates : HubRoute
    data class Template(val id: UUID) : HubRoute
    data object History : HubRoute
    data class Workout(val id: UUID) : HubRoute
    data object Recovery : HubRoute

    /** The exercise detail screen of an exercise id (a library, template or workout row). */
    data class Exercise(val exerciseID: String) : HubRoute

    /** Settings and About, owned by the app shell. */
    data object Settings : HubRoute

    fun encode(): String = when (this) {
        Library -> "library"
        Templates -> "templates"
        is Template -> "template:$id"
        History -> "history"
        is Workout -> "workout:$id"
        Recovery -> "recovery"
        is Exercise -> "exercise:$exerciseID"
        Settings -> "settings"
    }

    companion object {
        fun decode(text: String): HubRoute? {
            val name = text.substringBefore(':')
            val argument = text.substringAfter(':', "")
            return when (name) {
                "library" -> Library
                "templates" -> Templates
                "template" -> uuid(argument)?.let(::Template)
                "history" -> History
                "workout" -> uuid(argument)?.let(::Workout)
                "recovery" -> Recovery
                "exercise" -> if (argument.isEmpty()) null else Exercise(argument)
                "settings" -> Settings
                else -> null
            }
        }

        private fun uuid(text: String): UUID? = runCatching { UUID.fromString(text) }.getOrNull()
    }
}

/** One screen of the stack. [id] is unique for the life of the stack, so a screen opened twice never inherits the other's scroll position. */
internal data class HubEntry(val id: Int, val route: HubRoute) {
    fun encode(): String = "$id|${route.encode()}"

    companion object {
        fun decode(text: String): HubEntry? {
            val id = text.substringBefore('|').toIntOrNull() ?: return null
            val route = HubRoute.decode(text.substringAfter('|', "")) ?: return null
            return HubEntry(id, route)
        }
    }
}

/** What the template editor sheet edits: a new template, or the template with this id. */
internal sealed interface HubEditorTarget {
    data object New : HubEditorTarget
    data class Existing(val templateID: UUID) : HubEditorTarget

    fun encode(): String = when (this) {
        New -> "new"
        is Existing -> "template:$templateID"
    }

    companion object {
        fun decode(text: String): HubEditorTarget? = when {
            text == "new" -> New
            text.startsWith("template:") -> runCatching { UUID.fromString(text.removePrefix("template:")) }.getOrNull()?.let(::Existing)
            else -> null
        }

        /** Saves a nullable target (rememberSaveable keeps it across rotation). */
        val NullableSaver: Saver<HubEditorTarget?, String> = Saver(
            save = { it?.encode() ?: "" },
            restore = { decode(it) },
        )
    }
}

/** The back stack above the hub's home screen: empty = the home screen is showing. */
@Stable
internal class HubNavigator(initial: List<HubEntry> = emptyList()) {
    var entries: List<HubEntry> by mutableStateOf(initial)
        private set

    private var nextID: Int = (initial.maxOfOrNull { it.id } ?: 0) + 1

    val isAtRoot: Boolean get() = entries.isEmpty()

    /** Opens [route] on top; a second tap on the same row while it opens is ignored. */
    fun push(route: HubRoute) {
        if (entries.lastOrNull()?.route == route) return
        entries = entries + HubEntry(nextID++, route)
    }

    /** Goes one screen back; false at the home screen. */
    fun pop(): Boolean {
        if (entries.isEmpty()) return false
        entries = entries.dropLast(1)
        return true
    }

    fun popToRoot() {
        entries = emptyList()
    }

    companion object {
        val Saver: Saver<HubNavigator, Any> = listSaver<HubNavigator, String>(
            save = { navigator -> navigator.entries.map { it.encode() } },
            restore = { saved -> HubNavigator(saved.mapNotNull(HubEntry::decode)) },
        )
    }
}
