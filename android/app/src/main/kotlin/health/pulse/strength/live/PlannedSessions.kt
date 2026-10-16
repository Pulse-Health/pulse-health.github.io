package health.pulse.strength.live

import android.content.Context

/**
 * LA-06 Pre-workout countdown. Owner: system. A planned session shows a notification with a countdown to its start and the actions
 * "Start now" and "Snooze"; the host UI (owner: host) calls [schedule] from the "Plan a session" dialog of the hub.
 */
object PlannedSessions {
    /** Plans [templateId] to start at [startsAtEpochMillis]; replaces an earlier plan. Shows the countdown from 30 minutes before. */
    fun schedule(context: Context, templateId: String, startsAtEpochMillis: Long) {
        // Replaced by the owner.
    }

    /** Moves the planned start by [minutes]. */
    fun snooze(context: Context, minutes: Int = 10) {
        // Replaced by the owner.
    }

    fun cancel(context: Context) {
        // Replaced by the owner.
    }
}
