package health.pulse.strength.live

import android.content.Context
import android.content.SharedPreferences
import health.pulse.strength.core.widgets.FinishBrief
import health.pulse.strength.core.widgets.WidgetJson
import kotlinx.serialization.SerializationException

/**
 * What the workout notification has to remember between two refreshes, and across a restart of the process: the coach tip the user
 * answered with "Keep", the finish brief the app handed in, and which finished workout already has its card.
 */
internal class LiveState private constructor(private val prefs: SharedPreferences) {
    /** The set of the coach tip that "Keep 80" dismissed; a tip for another set shows again. */
    val dismissedCoachTip: String? get() = prefs.getString(KEY_DISMISSED_TIP, null)

    fun dismissCoachTip(setId: String) {
        prefs.edit().putString(KEY_DISMISSED_TIP, setId).apply()
    }

    fun forgetCoachTip() {
        if (prefs.contains(KEY_DISMISSED_TIP)) prefs.edit().remove(KEY_DISMISSED_TIP).apply()
    }

    /** `LiveUpdates.showFinish`: keeps the brief until the notification sees that the workout is gone. */
    fun handInFinish(brief: FinishBrief, nowMillis: Long) {
        prefs.edit()
            .putString(KEY_PENDING_FINISH, WidgetJson.json.encodeToString(FinishBrief.serializer(), brief))
            .putLong(KEY_PENDING_FINISH_AT, nowMillis)
            .apply()
    }

    /** The handed-in brief, once. A brief that nobody asked for within [PENDING_FINISH_TTL_MILLIS] is dropped: it belongs to a workout that is long over. */
    fun takePendingFinish(nowMillis: Long): FinishBrief? {
        val json = prefs.getString(KEY_PENDING_FINISH, null) ?: return null
        val handedAt = prefs.getLong(KEY_PENDING_FINISH_AT, 0L)
        prefs.edit().remove(KEY_PENDING_FINISH).remove(KEY_PENDING_FINISH_AT).apply()
        if (nowMillis - handedAt > PENDING_FINISH_TTL_MILLIS) return null
        return try {
            WidgetJson.json.decodeFromString(FinishBrief.serializer(), json)
        } catch (_: SerializationException) {
            null
        }
    }

    /** The finished workout (by id) whose card was posted from the snapshot's own `finish`; a dismissed card must not come back with the next refresh. */
    var finishPostedFor: String?
        get() = prefs.getString(KEY_FINISH_POSTED_FOR, null)
        set(value) {
            prefs.edit().apply { if (value == null) remove(KEY_FINISH_POSTED_FOR) else putString(KEY_FINISH_POSTED_FOR, value) }.apply()
        }

    companion object {
        /** The app hands the brief in a moment before or after the snapshot drops the workout. */
        const val PENDING_FINISH_TTL_MILLIS = 60_000L

        private const val FILE = "pulse_live_state"
        private const val KEY_DISMISSED_TIP = "dismissed_coach_tip"
        private const val KEY_PENDING_FINISH = "pending_finish"
        private const val KEY_PENDING_FINISH_AT = "pending_finish_at"
        private const val KEY_FINISH_POSTED_FOR = "finish_posted_for"

        fun of(context: Context): LiveState =
            LiveState(context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE))
    }
}
