package health.pulse.strength.live

import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutSnapshot
import java.math.BigDecimal
import java.math.RoundingMode

/**
 * The few text rules the notification, the tiles and bench mode share. They follow `NumberText` and `WorkoutPresenter` of the iOS core, so
 * the same workout reads the same on both platforms. English only (widgets/SPEC.md).
 */
internal object LiveText {
    /** "1:12" for 72 seconds and "1:02:03" from one hour on. */
    fun clock(seconds: Int): String {
        val total = seconds.coerceAtLeast(0)
        val hours = total / 3600
        val minutes = total % 3600 / 60
        val secs = total % 60
        return if (hours > 0) "$hours:${twoDigits(minutes)}:${twoDigits(secs)}" else "$minutes:${twoDigits(secs)}"
    }

    /** What the target set asks for: "82.5 kg × 6", "12 reps" or "45 s". */
    fun work(snapshot: WorkoutSnapshot): String = when (snapshot.tracking) {
        TrackingKind.WEIGHT_REPS -> "${snapshot.weightText} kg × ${snapshot.repsText}"
        TrackingKind.REPS_ONLY -> "${snapshot.repsText} reps"
        TrackingKind.DURATION -> "${snapshot.repsText} s"
    }

    /** "12 of 20 sets · 4,980 kg" */
    fun progress(snapshot: WorkoutSnapshot): String =
        "${snapshot.loggedSets} of ${snapshot.totalSets} sets · ${snapshot.volumeText} kg"

    /** A weight with at most two decimals and no trailing zeros: 20.0 gives "20" and 2.5 gives "2.5". */
    fun kg(value: Double): String =
        BigDecimal(value).setScale(2, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()

    /** "7:00" (24-hour style) or "7:00 AM" for [minuteOfDay] minutes after midnight. */
    fun timeOfDay(minuteOfDay: Int, is24Hour: Boolean): String {
        val total = (minuteOfDay % MINUTES_PER_DAY + MINUTES_PER_DAY) % MINUTES_PER_DAY
        val hour = total / 60
        val minute = twoDigits(total % 60)
        if (is24Hour) return "$hour:$minute"
        return "${if (hour % 12 == 0) 12 else hour % 12}:$minute ${if (hour < 12) "AM" else "PM"}"
    }

    /** "1 PR" or "3 PRs". */
    fun records(count: Int): String = if (count == 1) "1 PR" else "$count PRs"

    private const val MINUTES_PER_DAY = 24 * 60

    private fun twoDigits(value: Int): String = if (value < 10) "0$value" else value.toString()
}
