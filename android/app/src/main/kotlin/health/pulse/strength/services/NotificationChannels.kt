package health.pulse.strength.services

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import health.pulse.strength.R

object NotificationChannels {
    /** The ongoing "workout in progress" notification: silent, shown on the lock screen. */
    const val WORKOUT = "workout"

    /** The "rest over" alert: sound and vibration (the user can change both in the system settings). */
    const val REST_ALERT = "rest_alert"

    /** Creates the channels (idempotent; the system keeps the user's changes to an existing channel). */
    fun ensureCreated(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val workout = NotificationChannel(
            WORKOUT,
            context.getString(R.string.channel_workout_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = context.getString(R.string.channel_workout_description)
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        val rest = NotificationChannel(
            REST_ALERT,
            context.getString(R.string.channel_rest_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = context.getString(R.string.channel_rest_description)
            setShowBadge(false)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 250, 120, 250)
        }
        manager.createNotificationChannels(listOf(workout, rest))
    }
}
