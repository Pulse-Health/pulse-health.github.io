package health.pulse.strength.live

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Receives the alarm at the end of a PR flash (LA-01): the ongoing workout notification is drawn again, now without the flash. (The
 * rest alarm is `RestAlarmReceiver`; it refreshes the same notification.) Quick, so no `goAsync()`.
 */
class LiveAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_MOMENT_END) LiveUpdates.repost(context)
    }

    companion object {
        const val ACTION_MOMENT_END = "health.pulse.strength.live.action.MOMENT_END"
    }
}
