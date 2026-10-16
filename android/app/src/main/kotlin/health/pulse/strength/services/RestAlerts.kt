package health.pulse.strength.services

import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
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
 * The app declares no exact-alarm permission (no `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`: Google Play restricts them to alarm,
 * timer and calendar apps) and runs no foreground service, so what is possible depends on the Android version:
 *
 * | Android | Alarm used | Timing |
 * | --- | --- | --- |
 * | 8-11 (API 26-30) | exact `PendingIntent` alarm (no permission needed before API 31) | on time, also in Doze |
 * | 12-13 (API 31-33) | the approaching alarm below | on time or a few seconds late |
 * | 14+ (API 34+) | exact in-process listener alarm, plus the approaching alarm | on time while the app is not "cached" |
 *
 * The in-process listener alarm (`setExact(..., OnAlarmListener, Handler)`) needs no permission from Android 14 on, but the system
 * deletes it about ten seconds after the app becomes cached (the user went to other apps). On Android 12-13 it throws a
 * `SecurityException`, so it is not used there.
 *
 * **The approaching alarm** is an inexact `setAndAllowWhileIdle` alarm. The system may deliver an inexact alarm up to 0.75 times
 * its distance (futurity) late, and on a sleeping phone it delivers it at the end of that window, which would make a 90 s rest
 * about a minute late. So the alarm is not set for the end of the rest but for the moment from which the window ends exactly at
 * the end of the rest (`now + rest / 1.75`). When it fires early (the phone was awake anyway), it is set again for what is left,
 * and alarms closer than ten seconds are not fuzzed at all. This relies on that platform behaviour; on a device that behaves
 * differently the alert is late, never missing. It also works after the system ended the process.
 *
 * Every path leads to [onRestEnded]; the end time of the last alerted rest is remembered, so the alert never happens twice.
 */
class RestAlerts(
    private val context: Context,
    private val controller: WorkoutController,
    private val tracker: AppForegroundTracker,
    private val settings: PulseSettings,
    private val elapsedRealtime: () -> Long = { SystemClock.elapsedRealtime() },
    private val clock: () -> Instant = { Instant.now() },
) {
    private val alarmManager: AlarmManager? = context.getSystemService(AlarmManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private val listener = AlarmManager.OnAlarmListener { onRestEnded(scheduledEndsAt) }

    @Volatile
    private var scheduledEndsAt: Long = 0L

    /** Schedules (or cancels) the alarms to match [state]: a running, unpaused rest gets them; everything else none. */
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
        manager.cancel(alarmIntent(0L))
    }

    private fun schedule(endsAtMillis: Long) {
        val manager = alarmManager ?: return
        cancel()
        scheduledEndsAt = endsAtMillis
        val remaining = maxOf(0L, endsAtMillis - clock().toEpochMilli())

        if (Build.VERSION.SDK_INT >= 34) scheduleListener(manager, remaining)
        if (canScheduleExactPendingIntent(manager)) {
            val trigger = elapsedRealtime() + remaining
            attempt("exact alarm") { setExactAlarm(manager, trigger, endsAtMillis) }
        } else {
            scheduleApproaching(manager, endsAtMillis, remaining)
        }
    }

    /** Only called before Android 12, or when `canScheduleExactAlarms()` says that the app may set an exact alarm. */
    @SuppressLint("MissingPermission")
    private fun setExactAlarm(manager: AlarmManager, trigger: Long, endsAtMillis: Long) {
        manager.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, trigger, alarmIntent(endsAtMillis))
    }

    /** The exact in-process listener alarm (Android 14+; no permission). */
    private fun scheduleListener(manager: AlarmManager, remaining: Long) {
        val trigger = elapsedRealtime() + remaining
        attempt("listener alarm") {
            if (Build.VERSION.SDK_INT >= 37) {
                // The listener variant that also fires in Doze (API 37).
                manager.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, trigger, TAG, { it.run() }, listener)
            } else {
                manager.setExact(AlarmManager.ELAPSED_REALTIME_WAKEUP, trigger, TAG, listener, handler)
            }
        }
    }

    /**
     * True when a `PendingIntent` alarm can be exact: before Android 12 always, afterwards only when the app holds an exact-alarm
     * permission (it does not unless the manifest declares one; see RELEASING.md).
     */
    private fun canScheduleExactPendingIntent(manager: AlarmManager): Boolean =
        Build.VERSION.SDK_INT < 31 || runCatching { manager.canScheduleExactAlarms() }.getOrDefault(false)

    /** The inexact alarm timed so that the system's delay window ends at the end of the rest (see the class comment). */
    private fun scheduleApproaching(manager: AlarmManager, endsAtMillis: Long, remaining: Long) {
        val lead = if (remaining < FUZZ_FREE_MILLIS) remaining else (remaining / WINDOW_FACTOR).toLong()
        val trigger = elapsedRealtime() + lead
        attempt("approaching alarm") {
            manager.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, trigger, alarmIntent(endsAtMillis))
        }
    }

    private inline fun attempt(what: String, block: () -> Unit) {
        try {
            block()
        } catch (e: SecurityException) {
            Log.w(TAG, "The $what was refused by the system: ${e.message}")
        } catch (e: RuntimeException) {
            Log.w(TAG, "The $what could not be set: ${e.message}")
        }
    }

    private fun alarmIntent(endsAtMillis: Long): PendingIntent {
        val intent = Intent(context, RestAlarmReceiver::class.java).setAction(RestAlarmReceiver.ACTION_REST_END)
            .putExtra(RestAlarmReceiver.EXTRA_ENDS_AT, endsAtMillis)
        return PendingIntent.getBroadcast(context, REQUEST_CODE, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /**
     * The `PendingIntent` alarm fired. When it is early (an inexact alarm may fire as soon as its trigger time), it is set again for
     * what is left of the same rest; otherwise the rest is over.
     */
    fun onAlarm(endsAtMillis: Long) {
        val state = controller.state.value ?: return
        val rest = state.rest ?: return
        if (state.isPaused || rest.frozenRemaining != null) return
        val endsAt = rest.endsAt.toEpochMilli()
        if (endsAtMillis != 0L && kotlin.math.abs(endsAt - endsAtMillis) > STALE_TOLERANCE_MILLIS) return
        val remaining = endsAt - clock().toEpochMilli()
        if (remaining > STALE_TOLERANCE_MILLIS) {
            val manager = alarmManager ?: return
            if (!canScheduleExactPendingIntent(manager)) scheduleApproaching(manager, endsAt, remaining)
            return
        }
        onRestEnded(endsAtMillis)
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
        private const val REQUEST_CODE = 77
        private const val STALE_TOLERANCE_MILLIS = 2_000L

        /** Android does not fuzz an inexact alarm that is less than ten seconds away. */
        internal const val FUZZ_FREE_MILLIS = 10_000L

        /** An inexact alarm may be delivered up to 0.75 times its distance late: it ends at `distance * 1.75`. */
        internal const val WINDOW_FACTOR = 1.75
    }
}

/** Receives the `PendingIntent` rest alarm, possibly in a process that was started just for it. */
class RestAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_REST_END) return
        val environment = (context.applicationContext as PulseStrengthApplication).environment
        environment.services?.restAlerts?.onAlarm(intent.getLongExtra(EXTRA_ENDS_AT, 0L))
    }

    companion object {
        const val ACTION_REST_END = "health.pulse.strength.action.REST_END"
        const val EXTRA_ENDS_AT = "ends_at"
    }
}
