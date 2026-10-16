package health.pulse.strength.live

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetJson
import health.pulse.strength.runtime.StrengthRuntime
import health.pulse.strength.surfaces.Surfaces
import kotlinx.serialization.SerializationException

/**
 * The buttons of the workout notification ("Log set", "−", "+", "−15 s", "+15 s", "Skip", the coach tip answers). The command runs in the
 * app process through `StrengthRuntime.commands`, without opening the app, and every surface is refreshed afterwards.
 */
class WorkoutActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        when (intent.action) {
            ACTION_COMMAND -> {
                val command = intent.getStringExtra(EXTRA_COMMAND)?.let(::decode) ?: return
                SystemScope.runAsync(this) {
                    StrengthRuntime.commands.execute(command)
                    Surfaces.refreshAll(app)
                }
            }
            ACTION_KEEP_TIP -> {
                val setId = intent.getStringExtra(EXTRA_SET_ID) ?: return
                SystemScope.runAsync(this) {
                    LiveState.of(app).dismissCoachTip(setId)
                    LiveUpdates.refresh(app)
                }
            }
        }
    }

    companion object {
        const val ACTION_COMMAND = "health.pulse.strength.live.action.COMMAND"
        const val ACTION_KEEP_TIP = "health.pulse.strength.live.action.KEEP_TIP"
        const val EXTRA_COMMAND = "health.pulse.strength.live.extra.COMMAND"
        const val EXTRA_SET_ID = "health.pulse.strength.live.extra.SET_ID"

        /** A command travels as its JSON, the same encoding the watch uses. */
        fun encode(command: WidgetCommand): String = WidgetJson.json.encodeToString(WidgetCommand.serializer(), command)

        /** Null for text that is not a command, so a damaged extra can never crash the receiver. */
        fun decode(text: String): WidgetCommand? =
            try {
                WidgetJson.json.decodeFromString(WidgetCommand.serializer(), text)
            } catch (_: SerializationException) {
                null
            }
    }
}
