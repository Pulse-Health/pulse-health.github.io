package health.pulse.strength.live

import android.content.Context
import android.content.SharedPreferences

/**
 * What the workout notification has to remember across a restart of the process: the coach tip that the person answered with "Keep".
 * The tip belongs to one set, so the entry never has to be cleaned up: the next tip is for another set.
 */
internal class LiveState private constructor(private val prefs: SharedPreferences) {
    /** The set of the coach tip that "Keep 80" dismissed. */
    val dismissedCoachTip: String? get() = prefs.getString(KEY_DISMISSED_TIP, null)

    fun dismissCoachTip(setId: String) {
        prefs.edit().putString(KEY_DISMISSED_TIP, setId).apply()
    }

    companion object {
        private const val FILE = "pulse_live_state"
        private const val KEY_DISMISSED_TIP = "dismissed_coach_tip"

        fun of(context: Context): LiveState =
            LiveState(context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE))
    }
}
