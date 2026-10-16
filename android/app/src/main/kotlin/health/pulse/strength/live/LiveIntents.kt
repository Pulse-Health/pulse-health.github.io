package health.pulse.strength.live

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import health.pulse.strength.widgets.common.PulseActions

/** The pending intents behind the buttons and the tap target of the cards. */
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
     * enough. It starts the activity directly: Android 12 and later block activities started from a receiver that a button triggered.
     */
    fun link(context: Context, url: String): PendingIntent =
        PendingIntent.getActivity(context, 0, PulseActions.linkIntent(url), FLAGS)

    /** Buttons that differ only in their extras need their own request code, or they would collapse into one pending intent. */
    private fun broadcast(context: Context, id: LiveActionId, intent: Intent): PendingIntent =
        PendingIntent.getBroadcast(context, id.requestCode, intent, FLAGS)
}
