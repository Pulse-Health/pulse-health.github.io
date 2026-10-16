package health.pulse.strength.surfaces

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import health.pulse.strength.live.SystemScope
import health.pulse.strength.runtime.StrengthRuntime
import java.time.Instant
import java.time.ZoneId

/**
 * Widgets, tiles and complications draw "today", the week strip and "N days ago" from the snapshot, so a snapshot built yesterday is
 * wrong after midnight, after the clock was set and after the time zone changed. [DayChange] keeps one alarm on the next local
 * midnight; [DayChangeReceiver] answers it, and the system's clock broadcasts, by rebuilding the snapshot and refreshing every
 * surface, then arms the next midnight.
 *
 * The alarm is `setAndAllowWhileIdle`: inexact, delivered in Doze, and it needs no alarm permission (the app asks for none). A few
 * minutes late is harmless here, and if the system does not deliver a clock broadcast to the manifest receiver, the next midnight
 * alarm repairs the widgets.
 */
object DayChange {
    const val ACTION_MIDNIGHT = "health.pulse.strength.surfaces.action.MIDNIGHT"
    private const val REQUEST_CODE = 7201

    /** The alarm rings a little after midnight, so the new day has begun on every clock the snapshot builder reads. */
    private const val MARGIN_MILLIS = 30_000L

    /** The first instant of the local day after the one that holds [now] (a day can have 23 or 25 hours). */
    fun nextMidnight(now: Instant, zone: ZoneId): Instant = now.atZone(zone).toLocalDate().plusDays(1).atStartOfDay(zone).toInstant()

    /** Moves the alarm to the next midnight; calling it again only moves the same alarm. */
    fun schedule(context: Context, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val at = nextMidnight(now, zone).toEpochMilli() + MARGIN_MILLIS
        manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pendingIntent(context))
    }

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, DayChangeReceiver::class.java).setAction(ACTION_MIDNIGHT)
        return PendingIntent.getBroadcast(context, REQUEST_CODE, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }
}

/**
 * The midnight alarm, a change of the clock or of the time zone, a restart of the phone and an update of the app: the snapshot is
 * rebuilt for the new time and every surface is refreshed. Not exported; the system and the app's own alarm reach it.
 */
class DayChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        // The next midnight first: nothing below may leave the app without one.
        DayChange.schedule(app)
        SystemScope.runAsync(this) {
            StrengthRuntime.rebuild()
            Surfaces.refreshAll(app)
        }
    }
}
