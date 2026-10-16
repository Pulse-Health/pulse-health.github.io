package health.pulse.strength.live

import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import health.pulse.strength.PulseStrengthApplication
import health.pulse.strength.core.SnapshotBuilder
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.core.widgets.FinishBrief
import health.pulse.strength.runtime.StrengthRuntime
import health.pulse.strength.services.WorkoutNotifications
import java.time.Instant

/**
 * LA-01 ... LA-10, the states of the Android "Live Activity" beyond what `WorkoutNotifications` draws. The ongoing workout
 * notification is that class's (one notification, one id, the buttons, the rest countdown); this object decorates it:
 *
 * * [decorate] is called by `WorkoutNotifications.ongoing` as its last step and adds, from the snapshot, the PR moment, the
 *   superset's members and "Log A2", the plate line, the coach tip's answers, the status-bar chip text, the segmented progress bar of
 *   Android 16, the entry to bench mode, and the finish summary ([LiveDecorations] decides, this applies);
 * * [showFinish] posts the summary card once the workout is over and its notification is gone;
 * * [refresh] (from `Surfaces.refreshAll`) ends a planned session as soon as a workout runs.
 */
object LiveUpdates {
    /**
     * Decorates [builder], which `WorkoutNotifications.ongoing` has filled for [snapshot] at [now]. A snapshot without live moments
     * changes nothing but the status-bar chip text and, on Android 16, the progress bar.
     */
    fun decorate(context: Context, builder: NotificationCompat.Builder, snapshot: WorkoutSnapshot, now: Instant) {
        val app = context.applicationContext
        val decoration = LiveDecorations.of(snapshot, now, LiveState.of(app).dismissedCoachTip)
        apply(app, builder, decoration, now)
        // A workout is running: a planned session is over. A PR flash needs an alarm to end it.
        PlannedSessions.cancel(app)
        val flashEnd = LiveDecorations.flashEnd(snapshot, now)
        if (flashEnd != null) LiveAlarms.schedule(app, AlarmSlot.MOMENT_END, flashEnd.toEpochMilli()) else LiveAlarms.cancel(app, AlarmSlot.MOMENT_END)
    }

    /** Called after every new snapshot: a running workout ends a planned session, whether or not the notification can be posted. */
    suspend fun refresh(context: Context) {
        if (StrengthRuntime.snapshots.current().active != null) PlannedSessions.cancel(context.applicationContext)
    }

    /**
     * LA-05: the app calls this when a workout was finished and saved, with `SnapshotBuilder.finishBrief(...)`. Posts the summary
     * card, which leaves after two hours. (While the workout still runs, `WorkoutNotifications.ongoing` turns into the same
     * summary when the snapshot carries `finish`.)
     */
    fun showFinish(context: Context, brief: FinishBrief) {
        LiveCards.post(context.applicationContext, LiveCards.finish(brief))
    }

    /**
     * Draws the ongoing notification again from the running workout: after the PR flash ran out, or after the coach tip was answered
     * with "Keep". It is the notification of `WorkoutNotificationEffect`, replaced in place, never a second one.
     */
    internal fun repost(context: Context) {
        val app = context.applicationContext
        val state = (app as? PulseStrengthApplication)?.environment?.controller?.state?.value ?: return
        if (!WorkoutNotifications.canNotify(app)) return
        val now = Instant.now()
        @Suppress("MissingPermission") // canNotify() checked the runtime permission
        NotificationManagerCompat.from(app).notify(WorkoutNotifications.ONGOING_ID, WorkoutNotifications.ongoing(app, SnapshotBuilder.make(state, now), now))
    }

    private fun apply(context: Context, builder: NotificationCompat.Builder, decoration: LiveDecoration, now: Instant) {
        decoration.finish?.let { summary ->
            LiveCards.apply(context, builder, summary, now)
            builder.setProgress(0, 0, false)
            return
        }
        decoration.title?.let { builder.setContentTitle(it) }
        decoration.text?.let { builder.setContentText(it) }
        decoration.accent?.let { builder.setColor(LiveCards.accentColor(context, it)) }
        decoration.actions?.let { actions ->
            builder.clearActions()
            actions.forEach { builder.addAction(0, it.title, LiveIntents.pendingIntent(context, it)) }
        }
        if (decoration.opensBenchMode) builder.setContentIntent(LiveIntents.bench(context))

        val bigText = decoration.bigText
        val progress = decoration.progress
        if (bigText != null) {
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(bigText))
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
            decoration.chipText?.let { builder.setShortCriticalText(it) }
            if (progress != null) {
                val color = LiveCards.accentColor(context, decoration.accent ?: LiveAccent.GREEN)
                // The progress style draws its own bar: the plain one that the base notification set would sit next to it.
                builder.setProgress(0, 0, false)
                builder.setStyle(
                    NotificationCompat.ProgressStyle()
                        .setProgressSegments(progress.segments.map { NotificationCompat.ProgressStyle.Segment(it).setColor(color) })
                        .setProgress(progress.value),
                )
            }
        }
    }
}
