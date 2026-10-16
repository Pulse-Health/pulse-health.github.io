package health.pulse.strength.services

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The few device-level preferences of the app (not part of the workout data, and not backed up: see `res/xml/backup_rules.xml`).
 */
class PulseSettings(context: Context) {
    private val prefs: SharedPreferences = context.applicationContext.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    private val mutableHealthConnectEnabled = MutableStateFlow(prefs.getBoolean(KEY_HEALTH_CONNECT, false))

    /** Whether finished workouts are saved to Health Connect (off until the user turns it on and grants the permission). */
    val healthConnectEnabled: StateFlow<Boolean> = mutableHealthConnectEnabled.asStateFlow()

    fun setHealthConnectEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_HEALTH_CONNECT, enabled).apply()
        mutableHealthConnectEnabled.value = enabled
    }

    /** True once the notification permission prompt was shown, so it is not repeated at every workout. */
    var notificationPermissionAsked: Boolean
        get() = prefs.getBoolean(KEY_NOTIFICATION_ASKED, false)
        set(value) = prefs.edit().putBoolean(KEY_NOTIFICATION_ASKED, value).apply()

    /** The end time (epoch millis) of the last rest that was alerted, so the two alarm paths never alert twice. */
    var lastRestAlertEndsAt: Long
        get() = prefs.getLong(KEY_LAST_REST_ALERT, 0L)
        set(value) = prefs.edit().putLong(KEY_LAST_REST_ALERT, value).apply()

    companion object {
        const val NAME = "pulse_settings"
        private const val KEY_HEALTH_CONNECT = "health_connect_enabled"
        private const val KEY_NOTIFICATION_ASKED = "notification_permission_asked"
        private const val KEY_LAST_REST_ALERT = "last_rest_alert_ends_at"
    }
}
