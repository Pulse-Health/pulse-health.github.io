package health.pulse.strength.live

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * The alarms of this package. Each slot has one pending intent, so scheduling a slot again moves its alarm instead of adding another.
 *
 * All of them are `setAndAllowWhileIdle`: inexact, delivered in Doze, and no `SCHEDULE_EXACT_ALARM` permission (the app asks for none).
 * The rest alarm that has to be punctual belongs to `RestAlerts`, which brings its own in-process exact alarm; what is left here can
 * be a few seconds (the PR flash) or a few minutes (a planned session) late without harm.
 */
internal enum class AlarmSlot(val requestCode: Int, val action: String, val receiver: Class<out BroadcastReceiver>) {
    /** The PR flash is over (LA-01): the notification is drawn again without it. */
    MOMENT_END(7101, LiveAlarmReceiver.ACTION_MOMENT_END, LiveAlarmReceiver::class.java),

    /** 30 minutes before a planned session: show its countdown (LA-06). */
    PLANNED_COUNTDOWN(7102, PlannedSessionReceiver.ACTION_COUNTDOWN, PlannedSessionReceiver::class.java),

    /** A planned session starts now: "Time to train" (LA-06). */
    PLANNED_DUE(7103, PlannedSessionReceiver.ACTION_DUE, PlannedSessionReceiver::class.java),
}

internal object LiveAlarms {
    fun schedule(context: Context, slot: AlarmSlot, atMillis: Long) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pendingIntent(context, slot, create = true) ?: return)
    }

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
