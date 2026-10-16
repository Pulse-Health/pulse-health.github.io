package health.pulse.strength.services

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.core.app.NotificationManagerCompat
import health.pulse.strength.PulseStrengthApplication
import health.pulse.strength.core.SnapshotBuilder
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.core.WorkoutState
import java.time.Instant

/**
 * Makes sure something happens when a rest timer reaches zero while the app is not on screen: the ongoing notification flips to
 * "Go" and, when the workout's "alert when rest ends" setting is on, a "rest over" notification sounds.
 *
 * Reliability without special permissions or a foreground service:
 * 1. An exact alarm whose callback runs in the app process (`AlarmManager.OnAlarmListener`; this variant needs no exact-alarm
 *    permission). It fires on time while the process lives, which it normally does during a workout.
 * 2. A backup `PendingIntent` alarm (`setAndAllowWhileIdle`, inexact) that wakes the app even when the system ended the process; it
 *    may be late but it never needs a permission.
 * Both lead to [onRestEnded]; the end time of the last alerted rest is remembered, so the alert never happens twice.
 */
class RestAlerts(
    private val context: Context,
    private val controller: WorkoutController,
    private val tracker: AppForegroundTracker,
    private val settings: PulseSettings,
    private val clock: () -> Instant = { Instant.now() },
) {
    private val alarmManager: AlarmManager? = context.getSystemService(AlarmManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private val listener = AlarmManager.OnAlarmListener { onRestEnded(scheduledEndsAt) }

    @Volatile
    private var scheduledEndsAt: Long = 0L

    /** Schedules (or cancels) the alarms to match [state]: a running, unpaused rest gets one; everything else none. */
    fun sync(state: WorkoutState?) {
        val rest = state?.rest
        if (rest == null || state.isPaused || rest.frozenRemaining != null) {
            cancel()
            return
        }
        schedule(rest.endsAt.toEpochMilli())
    }

    fun cancel() {
        scheduledEndsAt = 0L
        val manager = alarmManager ?: return
        manager.cancel(listener)
        manager.cancel(backupIntent(0L))
    }

    private fun schedule(endsAtMillis: Long) {
        val manager = alarmManager ?: return
        cancel()
        scheduledEndsAt = endsAtMillis
        val delay = maxOf(0L, endsAtMillis - clock().toEpochMilli())
        val elapsedTrigger = SystemClock.elapsedRealtime() + delay
        runCatching {
            if (Build.VERSION.SDK_INT >= 34) {
                manager.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, elapsedTrigger, TAG, { it.run() }, listener)
            } else {
                manager.setExact(AlarmManager.ELAPSED_REALTIME_WAKEUP, elapsedTrigger, TAG, listener, handler)
            }
        }
        // Backup that also works after the process was ended: inexact, a second after the end so the exact one wins normally.
        runCatching { manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endsAtMillis + 1_000L, backupIntent(endsAtMillis)) }
    }

    private fun backupIntent(endsAtMillis: Long): PendingIntent {
        val intent = Intent(context, RestAlarmReceiver::class.java).setAction(RestAlarmReceiver.ACTION_REST_END)
            .putExtra(RestAlarmReceiver.EXTRA_ENDS_AT, endsAtMillis)
        return PendingIntent.getBroadcast(context, 77, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /**
     * A rest that was due at [endsAtMillis] is over. Ignores a stale alarm (the rest was changed, skipped, paused or finished since),
     * refreshes the ongoing notification and sounds the alert when the app is in the background and the workout wants it.
     */
    fun onRestEnded(endsAtMillis: Long) {
        val state = controller.state.value ?: return
        val rest = state.rest ?: return
        if (state.isPaused || rest.frozenRemaining != null) return
        val endsAt = rest.endsAt.toEpochMilli()
        if (endsAtMillis != 0L && kotlin.math.abs(endsAt - endsAtMillis) > STALE_TOLERANCE_MILLIS) return
        if (clock().toEpochMilli() < endsAt - STALE_TOLERANCE_MILLIS) return
        if (settings.lastRestAlertEndsAt == endsAt) return
        settings.lastRestAlertEndsAt = endsAt

        val now = clock()
        val snapshot = SnapshotBuilder.make(state, now)
        if (!WorkoutNotifications.canNotify(context)) return
        val manager = NotificationManagerCompat.from(context)
        @Suppress("MissingPermission") // canNotify() checked the runtime permission
        manager.notify(WorkoutNotifications.ONGOING_ID, WorkoutNotifications.ongoing(context, snapshot, now))
        if (state.settings.alertWhenRestEnds && !tracker.isForeground && snapshot.phase == SnapshotPhase.REST_OVER) {
            @Suppress("MissingPermission")
            manager.notify(WorkoutNotifications.REST_ALERT_ID, WorkoutNotifications.restOver(context, snapshot))
        }
    }

    companion object {
        private const val TAG = "pulse-rest"
        private const val STALE_TOLERANCE_MILLIS = 2_000L
    }
}

/** Receives the backup rest alarm, possibly in a process that was started just for it. */
class RestAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_REST_END) return
        val environment = (context.applicationContext as PulseStrengthApplication).environment
        environment.services?.restAlerts?.onRestEnded(intent.getLongExtra(EXTRA_ENDS_AT, 0L))
    }

    companion object {
        const val ACTION_REST_END = "health.pulse.strength.action.REST_END"
        const val EXTRA_ENDS_AT = "ends_at"
    }
}
