package health.pulse.strength.live

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.VibrationEffect
import android.os.Vibrator
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.runtime.StrengthRuntime
import kotlin.math.abs

/**
 * Receives the rest-end and PR-flash alarms (and the news that the user granted or revoked exact alarms): refreshes the notification,
 * which turns the finished rest into "Go" and clears an expired PR flash, and buzzes once when a rest ends.
 */
class LiveAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        when (intent.action) {
            ACTION_REST_END -> {
                val firedFor = intent.getLongExtra(LiveAlarms.EXTRA_AT_MILLIS, 0L)
                SystemScope.runAsync(this) {
                    LiveUpdates.refresh(app)
                    if (RestAlert.isDue(StrengthRuntime.snapshots.current().active, firedFor, System.currentTimeMillis())) RestAlert.buzz(app)
                }
            }
            ACTION_MOMENT_END -> SystemScope.runAsync(this) { LiveUpdates.refresh(app) }
            ACTION_EXACT_ALARM_PERMISSION_CHANGED -> SystemScope.runAsync(this) {
                // The alarms set so far may be inexact (or exact although the grant is gone): set them again.
                LiveUpdates.refresh(app)
                PlannedSessions.restore(app)
            }
        }
    }

    companion object {
        const val ACTION_REST_END = "health.pulse.strength.live.action.REST_END"
        const val ACTION_MOMENT_END = "health.pulse.strength.live.action.MOMENT_END"

        /** `AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED`, which only exists from Android 12. */
        const val ACTION_EXACT_ALARM_PERMISSION_CHANGED = "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED"
    }
}

/** The buzz at the end of a rest. */
internal object RestAlert {
    private const val ONE_BUZZ_MS = 400L

    /** An alarm may fire a moment before or after the rest ends. */
    private const val TOLERANCE_MS = 1_500L

    /** An alarm that Doze held back for longer is not worth a buzz: the rest ended long ago. */
    private const val MAX_LATE_MS = 120_000L

    /**
     * Whether the phone should buzz for the alarm that fired for [alarmAtMillis]: the workout still waits for exactly that rest to end.
     * A "+15 s", a skip or a pause replaces or removes the alarm, but one that was already on its way must stay silent.
     */
    fun isDue(active: WorkoutSnapshot?, alarmAtMillis: Long, nowMillis: Long): Boolean {
        if (active == null || active.finish != null || active.isPaused) return false
        if (active.phase != SnapshotPhase.RESTING && active.phase != SnapshotPhase.REST_OVER) return false
        val end = active.restEndsAt?.toEpochMilli() ?: return false
        return abs(end - alarmAtMillis) <= TOLERANCE_MS && nowMillis >= end - TOLERANCE_MS && nowMillis - end <= MAX_LATE_MS
    }

    fun buzz(context: Context) {
        val vibrator = context.getSystemService(Vibrator::class.java) ?: return
        if (vibrator.hasVibrator()) vibrator.vibrate(VibrationEffect.createOneShot(ONE_BUZZ_MS, VibrationEffect.DEFAULT_AMPLITUDE))
    }
}
