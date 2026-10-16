package health.pulse.strength.services

import android.content.Context
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.health.HealthConnectWorkoutWriter

/**
 * The platform services of the strength feature, registered as side effects of the workout controller (the Android counterpart of
 * the iOS `PulseServices`): the ongoing notification with its buttons, the rest alerts and the Health Connect writer.
 */
class PulseServices(context: Context, private val controller: WorkoutController) {
    val settings = PulseSettings(context)
    val foreground = AppForegroundTracker()
    val restAlerts = RestAlerts(context.applicationContext, controller, foreground, settings)
    private val notifications = WorkoutNotificationEffect(context.applicationContext, restAlerts)
    private val healthConnect = HealthConnectWorkoutWriter(context.applicationContext, settings)

    /** Called when the notification permission was just granted: shows the ongoing notification of the workout that is running. */
    fun onNotificationPermissionResult() {
        controller.state.value?.let { notifications.workoutStarted(it) }
    }

    init {
        NotificationChannels.ensureCreated(context)
        controller.addEffect(notifications)
        controller.addEffect(healthConnect)
    }
}
