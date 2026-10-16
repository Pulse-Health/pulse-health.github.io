package health.pulse.strength.wear

import android.content.Context
import android.util.Log
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import health.pulse.strength.core.widgets.WearProtocol
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetJson
import health.pulse.strength.runtime.StrengthRuntime
import health.pulse.strength.surfaces.Surfaces
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Receives the commands of the watch app (`WearProtocol.COMMAND_PATH`, registered in the manifest) and runs them like any other surface
 * does: through `StrengthRuntime.commands`, then a refresh of every surface, which also sends the new state back to the watch.
 *
 * Play services calls [onMessageReceived] on a background thread of this service and lets the process go once it returns, so the
 * command runs to completion inside the call (bounded by [COMMAND_TIMEOUT_MILLIS]) instead of on a scope that could be cancelled.
 */
class PhoneWearListenerService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != WearProtocol.COMMAND_PATH) return
        runBlocking(Dispatchers.Default) {
            val done = withTimeoutOrNull(COMMAND_TIMEOUT_MILLIS) { WearCommandHandler.handle(applicationContext, event.data) }
            if (done == null) Log.w(TAG, "A command from the watch took longer than $COMMAND_TIMEOUT_MILLIS ms")
        }
    }

    private companion object {
        const val TAG = "PhoneWearListener"
        const val COMMAND_TIMEOUT_MILLIS = 10_000L
    }
}

/** Decodes and runs one watch command. */
internal object WearCommandHandler {
    /** The command inside a message of the watch: [WidgetCommand] as UTF-8 JSON (`WearProtocol.COMMAND_PATH`). Null when it is not one. */
    fun decode(payload: ByteArray): WidgetCommand? = try {
        WidgetJson.json.decodeFromString(WidgetCommand.serializer(), String(payload, Charsets.UTF_8))
    } catch (_: IllegalArgumentException) {
        // kotlinx.serialization's SerializationException is an IllegalArgumentException: garbled JSON and wrong shapes land here.
        null
    }

    /**
     * Runs the command in [payload], then calls [refresh] so every surface (and the watch) shows the result. A message that is not a
     * command is ignored. Returns whether a command ran.
     */
    suspend fun handle(
        context: Context,
        payload: ByteArray,
        refresh: suspend (Context) -> Unit = Surfaces::refreshAll,
    ): Boolean {
        val command = decode(payload) ?: return false
        StrengthRuntime.commands.execute(command)
        refresh(context)
        return true
    }
}
