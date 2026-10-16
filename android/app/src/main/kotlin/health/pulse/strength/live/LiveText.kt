package health.pulse.strength.live

import health.pulse.strength.core.WorkoutSnapshot

/**
 * The few text rules of this package that neither `NumberText` nor `WorkoutNotifications` has. English only (widgets/SPEC.md).
 */
internal object LiveText {
    /** "12 of 20 sets · 4,980 kg" */
    fun progress(snapshot: WorkoutSnapshot): String =
        "${snapshot.loggedSets} of ${snapshot.totalSets} sets · ${snapshot.volumeText} kg"

    /** "7:00" (24-hour style) or "7:00 AM" for [minuteOfDay] minutes after midnight. */
    fun timeOfDay(minuteOfDay: Int, is24Hour: Boolean): String {
        val (time, suffix) = timeParts(minuteOfDay, is24Hour)
        return if (suffix == null) time else "$time $suffix"
    }

    /** The same time in two parts, the digits and "AM" or "PM" (null in the 24-hour style), so a clock can set the suffix small. */
    fun timeParts(minuteOfDay: Int, is24Hour: Boolean): Pair<String, String?> {
        val total = (minuteOfDay % MINUTES_PER_DAY + MINUTES_PER_DAY) % MINUTES_PER_DAY
        val hour = total / 60
        val minute = if (total % 60 < 10) "0${total % 60}" else (total % 60).toString()
        if (is24Hour) return "$hour:$minute" to null
        return "${if (hour % 12 == 0) 12 else hour % 12}:$minute" to if (hour < 12) "AM" else "PM"
    }

    /** "1 PR" or "3 PRs". */
    fun records(count: Int): String = if (count == 1) "1 PR" else "$count PRs"

    private const val MINUTES_PER_DAY = 24 * 60
}
