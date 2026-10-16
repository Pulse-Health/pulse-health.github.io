package health.pulse.strength.widgets.common

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.glance.GlanceId
import androidx.glance.action.Action
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.GlanceModifier
import health.pulse.strength.MainActivity
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetCommands
import health.pulse.strength.runtime.StrengthRuntime
import health.pulse.strength.surfaces.Surfaces

/**
 * Click actions of the widgets (widgets/SPEC.md sections 4 and 5).
 *
 * * [command] runs a [WidgetCommand] through `StrengthRuntime.commands` in the app process without opening the app, then refreshes every surface.
 * * [link] opens the app on a `pulse-strength://` deep link ([health.pulse.strength.core.widgets.DeepLinks]).
 */
object PulseActions {
    private val NameKey = ActionParameters.Key<String>("pulse.command.name")
    private val ArgsKey = ActionParameters.Key<String>("pulse.command.args")

    /** A click action that runs the command. Arguments are carried as `key=value` pairs joined by `&`, percent-encoded. */
    fun command(name: String, vararg args: Pair<String, String>): Action =
        actionRunCallback<CommandCallback>(
            actionParametersOf(NameKey to name, ArgsKey to encodeArgs(args.toMap())),
        )

    /** A click action that opens the app on [url] (for example `DeepLinks.startNext`). */
    fun link(url: String): Action = actionStartActivity(linkIntent(url))

    fun linkIntent(url: String): Intent =
        Intent(Intent.ACTION_VIEW, Uri.parse(url))
            .setClassName("health.pulse.strength", MainActivity::class.java.name)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)

    internal fun encodeArgs(args: Map<String, String>): String =
        args.entries.joinToString("&") { Uri.encode(it.key) + "=" + Uri.encode(it.value) }

    internal fun decodeArgs(text: String?): Map<String, String> {
        if (text.isNullOrEmpty()) return emptyMap()
        return text.split("&").mapNotNull { pair ->
            val index = pair.indexOf('=')
            if (index <= 0) null else Uri.decode(pair.substring(0, index)) to Uri.decode(pair.substring(index + 1))
        }.toMap()
    }

    internal fun commandOf(parameters: ActionParameters): WidgetCommand? {
        val name = parameters[NameKey] ?: return null
        return WidgetCommand(name, decodeArgs(parameters[ArgsKey]))
    }

    class CommandCallback : ActionCallback {
        override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
            val command = commandOf(parameters) ?: return
            StrengthRuntime.commands.execute(command)
            Surfaces.refreshAll(context)
        }
    }
}

/** `GlanceModifier.clickable(PulseActions.command(...))` as one call. */
fun GlanceModifier.onCommand(name: String, vararg args: Pair<String, String>): GlanceModifier =
    clickable(PulseActions.command(name, *args))

/** `GlanceModifier.clickable(PulseActions.link(url))` as one call. */
fun GlanceModifier.onLink(url: String): GlanceModifier = clickable(PulseActions.link(url))

/** Shorthand for the most used commands. */
object Commands {
    fun startNext() = PulseActions.command(WidgetCommands.START_NEXT)
    fun logNextSet() = PulseActions.command(WidgetCommands.LOG_NEXT_SET)
    fun skipRest() = PulseActions.command(WidgetCommands.SKIP_REST)
    fun adjustRest(seconds: Int) = PulseActions.command(WidgetCommands.ADJUST_REST, WidgetCommands.ARG_SECONDS to seconds.toString())
    fun nudge(weightSteps: Int, repsSteps: Int) = PulseActions.command(
        WidgetCommands.NUDGE,
        WidgetCommands.ARG_WEIGHT_STEPS to weightSteps.toString(),
        WidgetCommands.ARG_REPS_STEPS to repsSteps.toString(),
    )
}
