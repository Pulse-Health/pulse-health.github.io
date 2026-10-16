package health.pulse.strength.services

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import health.pulse.strength.MainActivity
import health.pulse.strength.R
import health.pulse.strength.core.NumberText
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.core.WorkoutSnapshot
import java.time.Instant
import java.util.UUID

/**
 * Builds the notifications of a workout: the ongoing "workout in progress" notification (the Android counterpart of the iOS Live
 * Activity: phase, next set, native chronometer / rest countdown and action buttons that work from the lock screen) and the
 * "rest over" alert.
 *
 * The notification only shows the app's own workout data, which is on the device anyway; nothing here touches the network.
 */
object WorkoutNotifications {
    const val ONGOING_ID = 1001
    const val REST_ALERT_ID = 1002

    // Intent actions handled by NotificationActionReceiver.
    const val ACTION_LOG_SET = "health.pulse.strength.action.LOG_SET"
    const val ACTION_NUDGE = "health.pulse.strength.action.NUDGE"
    const val ACTION_ADJUST_REST = "health.pulse.strength.action.ADJUST_REST"
    const val ACTION_SKIP_REST = "health.pulse.strength.action.SKIP_REST"

    const val EXTRA_EXERCISE_ID = "exercise_id"
    const val EXTRA_SET_ID = "set_id"
    const val EXTRA_WEIGHT_STEPS = "weight_steps"
    const val EXTRA_REPS_STEPS = "reps_steps"
    const val EXTRA_SECONDS = "seconds"

    private const val ACCENT = 0xFF1B8448.toInt()

    /** The text of what a set asks for: "82.5 kg × 6", "8 reps" or "45 sec". */
    fun workText(snapshot: WorkoutSnapshot): String =
        if (snapshot.showsWeight) "${snapshot.weightText} kg × ${snapshot.repsText}" else "${snapshot.repsText} ${snapshot.repsUnit}"

    /** The ongoing notification for [snapshot]; [now] only decides whether a running rest has already ended. */
    @SuppressLint("InlinedApi") // EXTRA_REQUEST_PROMOTED_ONGOING is a plain string constant; it is only read on Android 16+
    fun ongoing(context: Context, snapshot: WorkoutSnapshot, now: Instant): Notification {
        val phase = effectivePhase(snapshot, now)
        val builder = NotificationCompat.Builder(context, NotificationChannels.WORKOUT)
            .setSmallIcon(R.drawable.ic_stat_workout)
            .setColor(ACCENT)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setAutoCancel(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(if (Build.VERSION.SDK_INT >= 36) "workout" else NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(openWorkoutIntent(context))
            .setSubText(snapshot.workoutName)
            .setProgress(maxOf(1, snapshot.totalSets), snapshot.loggedSets.coerceIn(0, maxOf(1, snapshot.totalSets)), false)

        when {
            snapshot.isPaused -> {
                builder.setContentTitle(context.getString(R.string.notification_paused_title))
                    .setContentText("${snapshot.exerciseName.ifEmpty { snapshot.workoutName }} · ${NumberText.clock(snapshot.elapsedWhenPaused)}")
                    .setShowWhen(false)
            }
            phase == SnapshotPhase.RESTING -> {
                val endsAt = snapshot.restEndsAt
                builder.setContentTitle(context.getString(R.string.notification_rest_title))
                    .setContentText(context.getString(R.string.notification_next, snapshot.nextSetText))
                if (endsAt != null) {
                    builder.setWhen(endsAt.toEpochMilli()).setShowWhen(true).setUsesChronometer(true).setChronometerCountDown(true)
                }
                builder.addAction(adjustRestAction(context, -15)).addAction(adjustRestAction(context, 15)).addAction(skipRestAction(context))
            }
            phase == SnapshotPhase.REST_OVER -> {
                builder.setContentTitle(context.getString(R.string.notification_rest_over_title))
                    .setContentText(context.getString(R.string.notification_next, snapshot.nextSetText))
                    .setWhen(snapshot.activeStart.toEpochMilli()).setShowWhen(true).setUsesChronometer(true)
                logSetAction(context, snapshot)?.let { builder.addAction(it) }
            }
            phase == SnapshotPhase.COMPLETE && snapshot.totalSets == 0 -> {
                // A workout without exercises is "complete" for the builder; say what is actually going on.
                builder.setContentTitle(snapshot.workoutName)
                    .setContentText(context.getString(R.string.notification_empty_text))
                    .setWhen(snapshot.activeStart.toEpochMilli()).setShowWhen(true).setUsesChronometer(true)
            }
            phase == SnapshotPhase.COMPLETE -> {
                builder.setContentTitle(context.getString(R.string.notification_complete_title))
                    .setContentText(context.getString(R.string.notification_complete_text, setCountText(snapshot.loggedSets), snapshot.volumeText))
                    .setWhen(snapshot.activeStart.toEpochMilli()).setShowWhen(true).setUsesChronometer(true)
            }
            else -> {
                builder.setContentTitle(snapshot.exerciseName.ifEmpty { snapshot.workoutName })
                    .setContentText("${snapshot.setLabel} · ${workText(snapshot)}")
                    .setWhen(snapshot.activeStart.toEpochMilli()).setShowWhen(true).setUsesChronometer(true)
                logSetAction(context, snapshot)?.let { builder.addAction(it) }
                builder.addAction(nudgeAction(context, snapshot, -1)).addAction(nudgeAction(context, snapshot, 1))
            }
        }

        if (Build.VERSION.SDK_INT >= 36) {
            // Android 16 "Live Updates": ask for the status-bar chip. The system decides (user setting, criteria); ignored otherwise.
            builder.addExtras(Bundle().apply { putBoolean(Notification.EXTRA_REQUEST_PROMOTED_ONGOING, true) })
        }
        return builder.build()
    }

    /** The "rest over" alert posted while the app is not on screen. */
    fun restOver(context: Context, snapshot: WorkoutSnapshot): Notification {
        val builder = NotificationCompat.Builder(context, NotificationChannels.REST_ALERT)
            .setSmallIcon(R.drawable.ic_stat_workout)
            .setColor(ACCENT)
            .setContentTitle(context.getString(R.string.notification_rest_over_title))
            .setContentText(context.getString(R.string.notification_next, snapshot.nextSetText))
            .setSubText(snapshot.workoutName)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setTimeoutAfter(120_000L)
            .setContentIntent(openWorkoutIntent(context))
        logSetAction(context, snapshot)?.let { builder.addAction(it) }
        return builder.build()
    }

    /** Whether the app may post notifications right now (Android 13+ runtime permission plus the user's system setting). */
    fun canNotify(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return androidx.core.app.NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    /** What a running rest has become at [now]: a rest whose end has passed shows as over even before the alarm refreshed it. */
    private fun effectivePhase(snapshot: WorkoutSnapshot, now: Instant): SnapshotPhase {
        if (snapshot.phase == SnapshotPhase.RESTING && !snapshot.isPaused) {
            val endsAt = snapshot.restEndsAt
            if (endsAt != null && !now.isBefore(endsAt)) return SnapshotPhase.REST_OVER
        }
        return snapshot.phase
    }

    // region Actions

    private fun openWorkoutIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(MainActivity.EXTRA_OPEN_WORKOUT, true)
        return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun receiverIntent(context: Context, action: String, requestCode: Int, configure: Intent.() -> Unit = {}): PendingIntent {
        val intent = Intent(context, NotificationActionReceiver::class.java).setAction(action).apply(configure)
        return PendingIntent.getBroadcast(context, requestCode, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun logSetAction(context: Context, snapshot: WorkoutSnapshot): NotificationCompat.Action? {
        val exerciseID = snapshot.targetExerciseID ?: return null
        val setID = snapshot.targetSetID ?: return null
        // The set is part of the intent's identity (its data): FLAG_UPDATE_CURRENT would otherwise rewrite the one shared PendingIntent
        // to the next set on every refresh, and a stale tap on the old button would log the next set as well.
        val pending = receiverIntent(context, ACTION_LOG_SET, 1) {
            data = Uri.parse("pulse-strength://log/$setID")
            putExtra(EXTRA_EXERCISE_ID, exerciseID.toString())
            putExtra(EXTRA_SET_ID, setID.toString())
        }
        return NotificationCompat.Action.Builder(0, context.getString(R.string.action_log_set), pending).build()
    }

    /** "-" / "+" of the value that matters for the target set: the weight, or the reps (seconds for a duration) without a weight. */
    private fun nudgeAction(context: Context, snapshot: WorkoutSnapshot, direction: Int): NotificationCompat.Action {
        val weight = snapshot.showsWeight
        val label = when {
            weight && direction < 0 -> context.getString(R.string.action_weight_minus)
            weight -> context.getString(R.string.action_weight_plus)
            direction < 0 -> context.getString(R.string.action_reps_minus)
            else -> context.getString(R.string.action_reps_plus)
        }
        val pending = receiverIntent(context, ACTION_NUDGE, if (direction < 0) 2 else 3) {
            putExtra(EXTRA_WEIGHT_STEPS, if (weight) direction else 0)
            putExtra(EXTRA_REPS_STEPS, if (weight) 0 else direction)
        }
        return NotificationCompat.Action.Builder(0, label, pending).build()
    }

    private fun adjustRestAction(context: Context, seconds: Int): NotificationCompat.Action {
        val label = context.getString(if (seconds < 0) R.string.action_rest_minus else R.string.action_rest_plus)
        val pending = receiverIntent(context, ACTION_ADJUST_REST, if (seconds < 0) 4 else 5) { putExtra(EXTRA_SECONDS, seconds) }
        return NotificationCompat.Action.Builder(0, label, pending).build()
    }

    private fun skipRestAction(context: Context): NotificationCompat.Action =
        NotificationCompat.Action.Builder(0, context.getString(R.string.action_skip), receiverIntent(context, ACTION_SKIP_REST, 6)).build()

    // endregion

    /** The reducer action behind a notification button's [intent], or null for one that is not ours or is malformed. */
    fun workoutAction(intent: Intent): WorkoutAction? = when (intent.action) {
        ACTION_LOG_SET -> {
            val exerciseID = intent.getStringExtra(EXTRA_EXERCISE_ID)?.let(::parseUuid)
            val setID = intent.getStringExtra(EXTRA_SET_ID)?.let(::parseUuid)
            if (exerciseID != null && setID != null) WorkoutAction.LogSet(exerciseID, setID) else null
        }
        ACTION_NUDGE -> WorkoutAction.NudgeNextSet(
            weightSteps = intent.getIntExtra(EXTRA_WEIGHT_STEPS, 0).coerceIn(-1, 1),
            repsSteps = intent.getIntExtra(EXTRA_REPS_STEPS, 0).coerceIn(-1, 1),
        )
        ACTION_ADJUST_REST -> WorkoutAction.AdjustRest(intent.getIntExtra(EXTRA_SECONDS, 0).coerceIn(-60, 60))
        ACTION_SKIP_REST -> WorkoutAction.SkipRest
        else -> null
    }

    private fun parseUuid(text: String): UUID? = runCatching { UUID.fromString(text) }.getOrNull()

    /** Kept for tests: the tracking kind decides whether the steppers move the weight or the reps. */
    internal fun nudgesWeight(tracking: TrackingKind): Boolean = tracking == TrackingKind.WEIGHT_REPS
}
