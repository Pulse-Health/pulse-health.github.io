package health.pulse.strength.ui.detail

import health.pulse.strength.core.CompletedSet
import health.pulse.strength.core.NumberText
import health.pulse.strength.core.SetType
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.roundedAwayFromZero
import java.time.Instant
import java.time.ZoneId

/**
 * Hand-made date and set text, shared by the exercise detail and the workout summary (port of `StrengthResultText`). No
 * `DateFormat`, so the text is the same in every locale ("Oct 3", "Fri, Oct 13", "80×6").
 *
 * Dates are shown in [zone] (the device's time zone unless a test passes one), because "which day was this workout" is a local
 * calendar question; the month and weekday names below assume the Gregorian calendar.
 */
object StrengthResultText {
    val monthNames: List<String> = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
    val weekdayNames: List<String> = listOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")

    /** "Oct 3"; "Oct 3, 2025" when the year differs from the year of [now]. */
    fun monthDay(date: Instant, now: Instant, zone: ZoneId = ZoneId.systemDefault()): String {
        val local = date.atZone(zone)
        val text = monthNames[local.monthValue - 1] + " " + local.dayOfMonth
        val year = local.year
        return if (year != now.atZone(zone).year) "$text, $year" else text
    }

    /** "Fri, Oct 13" */
    fun weekdayMonthDay(date: Instant, now: Instant, zone: ZoneId = ZoneId.systemDefault()): String {
        // java.time counts Monday = 1 ... Sunday = 7; the names start with Sunday.
        val weekday = date.atZone(zone).dayOfWeek.value % 7
        return weekdayNames[weekday] + ", " + monthDay(date, now, zone)
    }

    /** "52m", "1h 5m" or "45s". */
    fun durationTile(seconds: Int): String {
        val total = maxOf(0, seconds)
        if (total < 60) return "${total}s"
        val minutes = total / 60
        if (minutes < 60) return "${minutes}m"
        val hours = minutes / 60
        val rest = minutes % 60
        if (rest == 0) return "${hours}h"
        return "${hours}h ${rest}m"
    }

    /** "52 min", "65 min" or "< 1 min". */
    fun durationSubtitle(seconds: Int): String {
        val minutes = maxOf(0, seconds) / 60
        if (minutes < 1) return "< 1 min"
        return "$minutes min"
    }

    /** "52 minutes", "1 hour 5 minutes" or "45 seconds" for TalkBack. */
    fun durationSpoken(seconds: Int): String {
        val total = maxOf(0, seconds)
        if (total < 60) return "$total" + if (total == 1) " second" else " seconds"
        val minutes = total / 60
        val hours = minutes / 60
        val rest = minutes % 60
        val parts = mutableListOf<String>()
        if (hours > 0) parts.add("$hours" + if (hours == 1) " hour" else " hours")
        if (rest > 0 || hours == 0) parts.add("$rest" + if (rest == 1) " minute" else " minutes")
        return parts.joinToString(" ")
    }

    /** One decimal with a "." separator: 2.14 gives "2.1", 2 gives "2.0". */
    fun oneDecimal(value: Double): String {
        if (!value.isFinite()) return "0.0"
        val clamped = maxOf(0.0, minOf(value, 1_000_000.0))
        val tenths = (clamped * 10).roundedAwayFromZero().toInt()
        return "${tenths / 10}.${tenths % 10}"
    }

    // region Sets

    /** "W 50×8", "80×6", "8 reps" or "45 s": one set on the one-line summaries. */
    fun compactText(set: CompletedSet, tracking: TrackingKind): String {
        var text = when (tracking) {
            TrackingKind.WEIGHT_REPS -> NumberText.kg(set.weightKg) + "×" + set.reps
            TrackingKind.REPS_ONLY ->
                if (set.weightKg > 0) "+" + NumberText.kg(set.weightKg) + "×" + set.reps else "${set.reps} reps"
            TrackingKind.DURATION -> "${set.reps} s"
        }
        if (set.type != SetType.NORMAL) text = set.type.badge + " " + text
        return text
    }

    /** "W 50×8 · W 70×5 · 80×6 · 80×6 · 80×5" */
    fun setsLine(sets: List<CompletedSet>, tracking: TrackingKind): String =
        sets.joinToString(" · ") { compactText(it, tracking) }

    /** "RIR 2", "RIR 4+" or null. */
    fun rirText(rir: Int?): String? {
        if (rir == null) return null
        if (rir >= 4) return "RIR 4+"
        return "RIR " + maxOf(0, rir)
    }

    /** "80 kg × 6", "8 reps", "+10 kg × 8" or "45 s". */
    fun detailText(set: CompletedSet, tracking: TrackingKind): String = when (tracking) {
        TrackingKind.WEIGHT_REPS -> NumberText.kg(set.weightKg) + " kg × " + set.reps
        TrackingKind.REPS_ONLY ->
            if (set.weightKg > 0) {
                "+" + NumberText.kg(set.weightKg) + " kg × " + set.reps
            } else {
                "${set.reps}" + if (set.reps == 1) " rep" else " reps"
            }
        TrackingKind.DURATION -> "${set.reps} s"
    }

    /** One line per set with the badge ("W", "D", "F" or the running number of the normal sets). */
    fun setLines(sets: List<CompletedSet>, tracking: TrackingKind): List<StrengthSetLine> {
        var normalCount = 0
        return sets.mapIndexed { index, set ->
            var badge = set.type.badge
            if (set.type == SetType.NORMAL) {
                normalCount += 1
                badge = normalCount.toString()
            }
            StrengthSetLine(
                id = index,
                type = set.type,
                badge = badge,
                detailText = detailText(set, tracking),
                rirText = rirText(set.rir),
            )
        }
    }

    // endregion
}

/** One expanded set of a session. */
data class StrengthSetLine(
    val id: Int,
    val type: SetType,
    val badge: String,
    val detailText: String,
    val rirText: String?,
) {
    /** What TalkBack reads for the line: "Set 2, 80 kg × 6, RIR 2" / "Warm-up set, 50 kg × 8". */
    val spokenText: String
        get() {
            val name = when (type) {
                SetType.NORMAL -> "Set $badge"
                SetType.WARMUP -> "Warm-up set"
                SetType.DROP -> "Drop set"
                SetType.FAILURE -> "Set to failure"
            }
            return listOfNotNull(name, detailText, rirText).joinToString(", ")
        }
}
