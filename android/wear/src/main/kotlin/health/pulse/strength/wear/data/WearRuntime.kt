package health.pulse.strength.wear.data

import android.content.Context
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.core.widgets.preview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The watch's single source of truth: the last snapshot the phone pushed (the preview until one arrives) and the way to send a command
 * to the phone. Owner: wear (replaces the body with DataStore/file persistence and the Data Layer client).
 */
object WearRuntime {
    private val state = MutableStateFlow(WidgetSnapshot.preview)

    val snapshot: StateFlow<WidgetSnapshot> = state.asStateFlow()

    fun current(): WidgetSnapshot = state.value

    fun init(context: Context) {
        // Replaced by the owner.
    }

    /** Sends [command] to the phone (fire and forget). */
    suspend fun send(command: WidgetCommand) {
        // Replaced by the owner.
    }

    internal fun publish(snapshot: WidgetSnapshot) {
        state.value = snapshot
    }
}
