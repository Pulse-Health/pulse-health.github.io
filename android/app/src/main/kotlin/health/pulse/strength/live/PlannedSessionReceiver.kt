package health.pulse.strength.live

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * LA-06: the planned session's alarms (the countdown 30 minutes before, "Time to train" at the start), the "Snooze 10 min" button, and
 * arming the plan again after a reboot or an update of the app. All of it is quick, so no `goAsync()`.
 */
class PlannedSessionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_COUNTDOWN -> PlannedSessions.showCountdown(context)
            ACTION_DUE -> PlannedSessions.showDue(context)
            ACTION_SNOOZE -> PlannedSessions.snooze(context, intent.getIntExtra(EXTRA_MINUTES, PlannedSessionModels.SNOOZE_MINUTES))
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> PlannedSessions.restore(context)
        }
    }

    companion object {
        const val ACTION_COUNTDOWN = "health.pulse.strength.live.action.PLANNED_COUNTDOWN"
        const val ACTION_DUE = "health.pulse.strength.live.action.PLANNED_DUE"
        const val ACTION_SNOOZE = "health.pulse.strength.live.action.PLANNED_SNOOZE"
        const val EXTRA_MINUTES = "health.pulse.strength.live.extra.MINUTES"
    }
}
