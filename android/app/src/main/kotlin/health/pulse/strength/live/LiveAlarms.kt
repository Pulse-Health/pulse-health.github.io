package health.pulse.strength.live

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * The alarms of this package. Each slot has one pending intent, so scheduling a slot again moves its alarm instead of adding another.
 *
 * All of them are delivered in Doze. A [punctual] slot (a planned session) is exact wherever the system lets the app set an exact alarm
 * without a permission it has to ask for: on Android 11 and older, and on Android 12 and newer when the user has allowed "Alarms &
 * reminders" for the app (the app itself declares no `SCHEDULE_EXACT_ALARM`, see `android/RELEASING.md`). Everywhere else it falls back to
 * `setAndAllowWhileIdle`, which can come a few minutes late. The other slots (the PR flash) are inexact: a few seconds do no harm. The
 * rest alarm that has to be punctual belongs to `RestAlerts`, which brings its own in-process exact alarm.
 */
internal enum class AlarmSlot(
    val requestCode: Int,
    val action: String,
    val receiver: Class<out BroadcastReceiver>,
    val punctual: Boolean = false,
) {
    /** The PR flash is over (LA-01): the notification is drawn again without it. */
    MOMENT_END(7101, LiveAlarmReceiver.ACTION_MOMENT_END, LiveAlarmReceiver::class.java),

    /** 30 minutes before a planned session: show its countdown (LA-06). */
    PLANNED_COUNTDOWN(7102, PlannedSessionReceiver.ACTION_COUNTDOWN, PlannedSessionReceiver::class.java, punctual = true),

    /** A planned session starts now: "Time to train" (LA-06). */
    PLANNED_DUE(7103, PlannedSessionReceiver.ACTION_DUE, PlannedSessionReceiver::class.java, punctual = true),
}

internal object LiveAlarms {
    fun schedule(context: Context, slot: AlarmSlot, atMillis: Long) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = pendingIntent(context, slot, create = true) ?: return
        if (slot.punctual && canScheduleExact(manager)) {
            try {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending)
                return
            } catch (_: SecurityException) {
                // The user took the permission away between the check and the call: the inexact alarm below is the fallback.
            }
        }
        manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending)
    }

    /** Android 11 and older need no permission for an exact alarm; from Android 12 the user has to have allowed it for the app. */
    private fun canScheduleExact(manager: AlarmManager): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || runCatching { manager.canScheduleExactAlarms() }.getOrDefault(false)

    fun cancel(context: Context, slot: AlarmSlot) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = pendingIntent(context, slot, create = false) ?: return
        manager.cancel(pending)
        pending.cancel()
    }

    private fun pendingIntent(context: Context, slot: AlarmSlot, create: Boolean): PendingIntent? {
        val intent = Intent(context, slot.receiver).setAction(slot.action)
        val flags = PendingIntent.FLAG_IMMUTABLE or if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE
        return PendingIntent.getBroadcast(context, slot.requestCode, intent, flags)
    }
}
