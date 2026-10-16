package health.pulse.strength.core.widgets

import health.pulse.strength.core.CompletedWorkout
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Day, week and month arithmetic in the snapshot's time zone (widgets/SPEC.md section 2, "Calendar").
 *
 * An instant is reduced to a day number: the days since 1970-01-01 of its local date. Everything that counts days, weeks or months
 * works on those numbers, so the buckets stay exact across a daylight saving change (a day may have 23 or 25 hours) and are the same
 * as the Swift implementation's. Only turning a day number back into the start of that day needs the zone.
 */
internal class WidgetCalendar(private val zone: ZoneId) {
    /** The day number of the local date of [instant]. An instant too far from the epoch counts as 1970-01-01. */
    fun day(instant: Instant): Long {
        val local = localSeconds(instant.epochSecond) ?: return 0
        return Math.floorDiv(local, secondsPerDay)
    }

    /** The first moment of local day [day] (an hour later than midnight where daylight saving skips midnight). */
    fun startOfDay(day: Long): Instant = LocalDate.ofEpochDay(day).atStartOfDay(zone).toInstant()

    /** Minutes after local midnight of the moment [epochSecond] seconds after the epoch (0...1439). */
    fun minuteOfDay(epochSecond: Long): Int {
        val local = localSeconds(epochSecond) ?: return 0
        return min(1_439L, Math.floorMod(local, secondsPerDay) / 60).toInt()
    }

    /** Minutes after local midnight of [instant] (0...1439). */
    fun minuteOfDay(instant: Instant): Int = minuteOfDay(instant.epochSecond)

    /**
     * The calendar days from [earlier] to [later]: the local midnights crossed (23:50 yesterday is 1 day ago). A [later] that is not
     * after [earlier] counts as 0.
     */
    fun daysBetween(earlier: Instant, later: Instant): Int =
        max(0L, day(later) - day(earlier)).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()

    /** Seconds since the epoch of the local date and time of the moment [epochSecond]; null for a moment too far from the epoch. */
    private fun localSeconds(epochSecond: Long): Long? {
        if (abs(epochSecond) >= farSeconds) return null
        return epochSecond + zone.rules.getOffset(Instant.ofEpochSecond(epochSecond)).totalSeconds
    }

    companion object {
        private const val secondsPerDay = 86_400L

        /** Instants farther than this many seconds from the epoch (about 31 million years) are treated as the epoch itself. */
        private const val farSeconds = 1_000_000_000_000_000L

        /** 0 for Monday ... 6 for Sunday. Day 0, 1970-01-01, was a Thursday. */
        fun weekdayIndex(day: Long): Int = Math.floorMod(day + 3, 7L).toInt()

        /** The Monday on or before [day]: the first day of its week. */
        fun mondayOnOrBefore(day: Long): Long = day - weekdayIndex(day)

        /** The civil date of day number [day]. */
        fun civil(day: Long): LocalDate = LocalDate.ofEpochDay(day)

        /** The day number of a civil date. */
        fun dayNumber(year: Int, month: Int, day: Int): Long = LocalDate.of(year, month, day).toEpochDay()

        /** 28...31. */
        fun daysInMonth(year: Int, month: Int): Int = YearMonth.of(year, month).lengthOfMonth()

        /** 1...366. */
        fun dayOfYear(day: Long): Int = LocalDate.ofEpochDay(day).dayOfYear

        /** One letter per weekday, Monday first. */
        val weekdayLetters: List<String> = listOf("M", "T", "W", "T", "F", "S", "S")

        /** Weekday names, Monday first. */
        val weekdayNames: List<String> = listOf("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")

        /** Month names, January first. */
        val monthNames: List<String> = listOf(
            "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December",
        )
    }
}

/** The finished workouts of a snapshot with the local day each one belongs to (the day of its `finishedAt`), computed once. */
internal class WidgetHistory(workouts: List<CompletedWorkout>, val calendar: WidgetCalendar, val now: Instant) {
    class Entry(val workout: CompletedWorkout, val day: Long)

    /** The day number of [now]. */
    val today: Long = calendar.day(now)

    /** The Monday of the current week (day number). */
    val weekStart: Long = WidgetCalendar.mondayOnOrBefore(today)

    /** The workouts in the order of `StrengthData.history` (newest first). */
    val entries: List<Entry> = workouts.map { Entry(it, calendar.day(it.finishedAt)) }

    /** The workouts of the current week, Monday to Sunday. */
    val thisWeek: List<Entry> = inDays(weekStart until weekStart + 7)

    /** The workout with the greatest `finishedAt` (the first one on a tie). */
    val latest: Entry? = entries.maxWithOrNull(compareBy { it.workout.finishedAt })

    /** The workouts whose day lies in [days]. */
    fun inDays(days: LongRange): List<Entry> = entries.filter { it.day in days }

    /** Calendar days from [instant] to now (0 for an instant in the future). */
    fun daysAgo(instant: Instant): Int = calendar.daysBetween(instant, now)
}
