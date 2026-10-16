package health.pulse.strength.wear.model

import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutSnapshot
import kotlin.math.abs
import kotlin.math.max

/**
 * The words and numbers the tiles, complications and the app share. Everything is a pure function of snapshot data, so the same
 * figure reads the same on every surface (and on the phone: [kg] and [clock] follow `NumberText` of the iOS core).
 */
internal object WearText {
    /** The longest text a SHORT_TEXT complication is meant to carry. */
    const val SHORT_LIMIT = 7

    /** "82.5", "85", "80.25": at most two decimals, no trailing zeros. */
    fun kg(value: Double): String {
        val hundredths = Math.round(value * 100)
        if (hundredths == 0L) return "0"
        val magnitude = abs(hundredths)
        val whole = magnitude / 100
        val fraction = (magnitude % 100).toInt()
        val sign = if (hundredths < 0) "-" else ""
        return when {
            fraction == 0 -> "$sign$whole"
            fraction % 10 == 0 -> "$sign$whole.${fraction / 10}"
            fraction < 10 -> "$sign$whole.0$fraction"
            else -> "$sign$whole.$fraction"
        }
    }

    /** A signed change: "+4 kg", "−3 kg" (true minus sign), "no change" for zero. */
    fun deltaKg(value: Double): String {
        val text = kg(abs(value))
        return when {
            text == "0" -> "no change"
            value > 0 -> "+$text kg"
            else -> "−$text kg"
        }
    }

    /** "1:24", or "1:02:03" from an hour on. */
    fun clock(seconds: Int): String {
        val total = max(0, seconds)
        val hours = total / 3600
        val minutes = total % 3600 / 60
        val secs = total % 60
        val tail = secs.toString().padStart(2, '0')
        return if (hours > 0) "$hours:${minutes.toString().padStart(2, '0')}:$tail" else "$minutes:$tail"
    }

    /** "1 minute 24 seconds": the clock for a screen reader. */
    fun spoken(seconds: Int): String {
        val total = max(0, seconds)
        val hours = total / 3600
        val minutes = total % 3600 / 60
        val secs = total % 60
        val parts = buildList {
            if (hours > 0) add(plural(hours, "hour"))
            if (minutes > 0) add(plural(minutes, "minute"))
            if (secs > 0 || isEmpty()) add(plural(secs, "second"))
        }
        return parts.joinToString(" ")
    }

    fun plural(count: Int, noun: String): String = if (count == 1) "1 $noun" else "$count ${noun}s"

    /** "6 exercises", "1 exercise". */
    fun exercises(count: Int): String = plural(count, "exercise")

    /** "3d" for the complications; "--" without any history. */
    fun daysShort(days: Int?): String = days?.let { "${max(0, it)}d" } ?: "--"

    /** "Last workout 3 days ago" for a screen reader. */
    fun daysSpoken(days: Int?): String = when {
        days == null -> "No workouts yet"
        days <= 0 -> "Last workout today"
        days == 1 -> "Last workout yesterday"
        else -> "Last workout $days days ago"
    }

    /** "5 days ago", "Yesterday", "Today": how long a record or a workout lies back. */
    fun daysAgo(days: Int?): String = when {
        days == null -> ""
        days <= 0 -> "Today"
        days == 1 -> "Yesterday"
        else -> "$days days ago"
    }

    /** "~55 min", or null when the estimate is unknown. */
    fun approxMinutes(minutes: Int): String? = if (minutes > 0) "~$minutes min" else null

    /** "6 exercises · ~55 min". */
    fun planSummary(exerciseCount: Int, minutes: Int): String =
        listOfNotNull(exercises(exerciseCount), approxMinutes(minutes)).joinToString(" · ")

    /** "Push day" -> "PUSH", "Upper A" -> "UPPER": the first word in capitals, cut to what a small complication holds. */
    fun splitWord(label: String): String {
        val word = label.trim().substringBefore(' ').uppercase()
        return word.take(SHORT_LIMIT)
    }

    /** Cuts [text] to the length of a SHORT_TEXT complication. */
    fun short(text: String): String = text.take(SHORT_LIMIT)

    /** What the running set asks for, as the phone writes it: "82.5 kg × 6", "8 reps" or "45 s". */
    fun work(active: WorkoutSnapshot): String = when (active.tracking) {
        TrackingKind.WEIGHT_REPS -> "${active.weightText} kg × ${active.repsText}"
        TrackingKind.REPS_ONLY -> "${active.repsText} reps"
        TrackingKind.DURATION -> "${active.repsText} s"
    }

    /** The set that follows a rest, for the line under the countdown: "Next · 80 kg × 6". */
    fun nextSet(active: WorkoutSnapshot): String =
        if (active.phase == SnapshotPhase.COMPLETE) "All sets logged" else "Next · ${work(active)}"
}
