package health.pulse.strength.services

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import health.pulse.strength.PulseStrengthApplication
import health.pulse.strength.core.ActionOrigin

/**
 * Runs a notification button (Log set, -/+, rest -15 s / +15 s / Skip) in the app's process. The process may have been started just
 * for this broadcast: [PulseStrengthApplication] restores the running workout from disk before any receiver runs, and the controller
 * then applies the action, saves the workout and refreshes the notification (through the registered side effects).
 *
 * Not exported: only our own notifications can fire it.
 */
class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = WorkoutNotifications.workoutAction(intent) ?: return
        val environment = (context.applicationContext as PulseStrengthApplication).environment
        environment.controller.send(action, ActionOrigin.LIVE_ACTIVITY)
    }
}
