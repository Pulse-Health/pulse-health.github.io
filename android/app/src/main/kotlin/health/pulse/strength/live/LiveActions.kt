package health.pulse.strength.live

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.widgets.common.PulseActions

/**
 * The buttons that this package adds to a notification. Each owns a request code: buttons whose pending intents differ only in their
 * extras would collapse into one. (The codes are far from those of `WorkoutNotifications`, whose receiver is another component anyway.)
 */
internal enum class LiveActionId(val requestCode: Int) {
    LOG_SET(101),
    NUDGE_DOWN(102),
    NUDGE_UP(103),
    SKIP_REST(104),
    APPLY_TIP(105),
    KEEP_TIP(106),
    SHARE(107),
    START_PLANNED(108),
    SNOOZE_PLANNED(109),
}

/** What a button does. */
internal sealed interface LiveTarget {
    /** Runs a command through `StrengthRuntime.commands` in the app process, without opening the app. */
    data class Command(val command: WidgetCommand) : LiveTarget

    /** Opens the app on a `pulse-strength://` link. */
    data class Link(val url: String) : LiveTarget

    /** Answers "Keep 80": only the tip for [setId] disappears, nothing is sent to the engine. */
    data class KeepCoachTip(val setId: String) : LiveTarget

    /** Opens the share sheet with [text]. */
    data class Share(val text: String) : LiveTarget

    /** Moves the planned session by [minutes]. */
    data class Snooze(val minutes: Int) : LiveTarget
}

internal data class LiveAction(val id: LiveActionId, val title: String, val target: LiveTarget)

/** The pending intents behind the buttons and the tap targets of the notifications of this package. */
internal object LiveIntents {
    private const val FLAGS = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT

    fun pendingIntent(context: Context, action: LiveAction): PendingIntent = when (val target = action.target) {
        is LiveTarget.Command -> broadcast(
            context,
            action.id,
            Intent(context, WorkoutActionReceiver::class.java)
                .setAction(WorkoutActionReceiver.ACTION_COMMAND)
                .putExtra(WorkoutActionReceiver.EXTRA_COMMAND, WorkoutActionReceiver.encode(target.command)),
        )
        is LiveTarget.KeepCoachTip -> broadcast(
            context,
            action.id,
            Intent(context, WorkoutActionReceiver::class.java)
                .setAction(WorkoutActionReceiver.ACTION_KEEP_TIP)
                .putExtra(WorkoutActionReceiver.EXTRA_SET_ID, target.setId),
        )
        is LiveTarget.Snooze -> broadcast(
            context,
            action.id,
            Intent(context, PlannedSessionReceiver::class.java)
                .setAction(PlannedSessionReceiver.ACTION_SNOOZE)
                .putExtra(PlannedSessionReceiver.EXTRA_MINUTES, target.minutes),
        )
        is LiveTarget.Link -> link(context, target.url)
        is LiveTarget.Share -> PendingIntent.getActivity(
            context,
            action.id.requestCode,
            Intent.createChooser(
                Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, target.text),
                null,
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            FLAGS,
        )
    }

    /**
     * Opens the app on a `pulse-strength://` link. The pending intents of different links differ by their data, so one request code is
     * enough. They start the activity directly: Android 12 and later block an activity that a receiver starts for a notification button.
     */
    fun link(context: Context, url: String): PendingIntent =
        PendingIntent.getActivity(context, 0, PulseActions.linkIntent(url), FLAGS)

    /** Opens bench mode (the big rest timer; shown over the lock screen). */
    fun bench(context: Context): PendingIntent =
        PendingIntent.getActivity(context, 0, BenchMode.intent(context), FLAGS)

    private fun broadcast(context: Context, id: LiveActionId, intent: Intent): PendingIntent =
        PendingIntent.getBroadcast(context, id.requestCode, intent, FLAGS)
}
