package health.pulse.strength.live

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/** How an alarm is set. */
internal enum class AlarmMode { EXACT, INEXACT }

/** The one rule that chooses between the two alarm APIs (unit-tested). */
internal object AlarmPolicy {
    /**
     * Before Android 12 every app may set exact alarms; from then on only with the user's "Alarms & reminders" grant
     * ([canScheduleExact]). [wantsExact] false asks for the cheaper inexact alarm where a few minutes do not matter.
     */
    fun mode(sdkInt: Int, canScheduleExact: Boolean, wantsExact: Boolean = true): AlarmMode =
        if (wantsExact && (sdkInt < Build.VERSION_CODES.S || canScheduleExact)) AlarmMode.EXACT else AlarmMode.INEXACT
}

/** The alarms of the app. Each slot has one pending intent, so scheduling a slot again moves its alarm instead of adding another. */
internal enum class AlarmSlot(
    val requestCode: Int,
    val action: String,
    val receiver: Class<out BroadcastReceiver>,
    val wantsExact: Boolean,
) {
    /** The rest countdown reached zero: show "Go" and buzz once. */
    REST_END(7101, LiveAlarmReceiver.ACTION_REST_END, LiveAlarmReceiver::class.java, true),

    /** The PR flash is over (LA-01). */
    MOMENT_END(7102, LiveAlarmReceiver.ACTION_MOMENT_END, LiveAlarmReceiver::class.java, true),

    /** 30 minutes before a planned session: show its countdown (LA-06). Being a little late costs nothing, so no exact alarm. */
    PLANNED_COUNTDOWN(7103, PlannedSessionReceiver.ACTION_COUNTDOWN, PlannedSessionReceiver::class.java, false),

    /** A planned session starts now: "Time to train" (LA-06). */
    PLANNED_DUE(7104, PlannedSessionReceiver.ACTION_DUE, PlannedSessionReceiver::class.java, true),
}

/** Schedules and cancels the alarms of [AlarmSlot]. */
internal object LiveAlarms {
    /** The time the alarm was set for; receivers compare it with the current snapshot to ignore an alarm of a state that is gone. */
    const val EXTRA_AT_MILLIS = "health.pulse.strength.live.extra.AT_MILLIS"

    fun schedule(context: Context, slot: AlarmSlot, atMillis: Long) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = pendingIntent(context, slot, atMillis, create = true) ?: return
        val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()
        when (AlarmPolicy.mode(Build.VERSION.SDK_INT, canExact, slot.wantsExact)) {
            AlarmMode.EXACT -> try {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending)
            } catch (_: SecurityException) {
                // The grant was withdrawn between the check and the call.
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending)
            }
            AlarmMode.INEXACT -> manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending)
        }
    }

    fun cancel(context: Context, slot: AlarmSlot) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = pendingIntent(context, slot, 0L, create = false) ?: return
        manager.cancel(pending)
        pending.cancel()
    }

    private fun pendingIntent(context: Context, slot: AlarmSlot, atMillis: Long, create: Boolean): PendingIntent? {
        val intent = Intent(context, slot.receiver).setAction(slot.action).putExtra(EXTRA_AT_MILLIS, atMillis)
        val flags = PendingIntent.FLAG_IMMUTABLE or if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE
        return PendingIntent.getBroadcast(context, slot.requestCode, intent, flags)
    }
}

/**
 * The alarm that ends a rest: the notification turns into "Go" and the phone buzzes once, even with the screen off. Exact when the user
 * granted "Alarms & reminders" (`SCHEDULE_EXACT_ALARM`), inexact but still allowed in Doze otherwise. `LiveUpdates.refresh` calls these
 * from the snapshot itself, so no other component has to.
 */
object RestAlarms {
    fun scheduleRestEnd(context: Context, endsAtMillis: Long) {
        LiveAlarms.schedule(context, AlarmSlot.REST_END, endsAtMillis)
    }

    fun cancel(context: Context) {
        LiveAlarms.cancel(context, AlarmSlot.REST_END)
    }
}
