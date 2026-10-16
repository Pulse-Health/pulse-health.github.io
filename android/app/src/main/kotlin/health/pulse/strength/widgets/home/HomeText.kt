package health.pulse.strength.widgets.home

import health.pulse.strength.core.widgets.WidgetSnapshot
import java.time.DateTimeException
import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.TextStyle
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.abs
import kotlin.math.floor

/**
 * The English text the Home Screen widgets are made of. Everything is hand formatted and locale independent, like the iOS `WidgetText`
 * and PulseStrengthCore's `NumberText`, so the same snapshot reads the same on both platforms.
 */
internal object HomeText {
    /** Kilograms with at most two decimals and no trailing zeros: 82.5 gives "82.5", 80 gives "80", a non-finite value gives "0". */
    fun kg(value: Double): String {
        if (!value.isFinite()) return "0"
        val scaled = (value * 100).coerceIn(-9.0e15, 9.0e15)
        val hundredths = if (scaled < 0) -floor(-scaled + 0.5).toLong() else floor(scaled + 0.5).toLong()
        if (hundredths == 0L) return "0"
        val magnitude = abs(hundredths)
        val whole = magnitude / 100
        val fraction = (magnitude % 100).toInt()
        val text = StringBuilder()
        if (hundredths < 0) text.append('-')
        text.append(whole)
        when {
            fraction == 0 -> Unit
            fraction % 10 == 0 -> text.append('.').append(fraction / 10)
            fraction < 10 -> text.append(".0").append(fraction)
            else -> text.append('.').append(fraction)
        }
        return text.toString()
    }

    /** "85 × 5". */
    fun weightReps(kg: Double, reps: Int): String = kg(kg) + " × " + reps

    /** "+2.5" / "−3" with a real minus sign, "0" for zero. */
    fun signed(value: Double): String {
        if (abs(value) < 0.005) return "0"
        return (if (value > 0) "+" else "−") + kg(abs(value))
    }

    /** "Never", "Today", "Yesterday", "5 days ago". */
    fun daysAgo(days: Int?): String = when {
        days == null -> "Never"
        days <= 0 -> "Today"
        days == 1 -> "Yesterday"
        else -> "$days days ago"
    }

    /** "5d" ("–" for none). */
    fun daysShort(days: Int?): String = if (days == null) "–" else "${maxOf(0, days)}d"

    /** "~55 min". */
    fun minutes(minutes: Int): String = "~$minutes min"

    /** "6 exercises" / "1 exercise". */
    fun exercises(count: Int): String = if (count == 1) "1 exercise" else "$count exercises"

    /** "7 sessions" / "1 session". */
    fun sessions(count: Int): String = if (count == 1) "1 session" else "$count sessions"

    /** "9 sets" / "1 set". */
    fun sets(count: Int): String = if (count == 1) "1 set" else "$count sets"

    /** A session's tonnage: "8.4 t" from one tonne on, else "850 kg". */
    fun volume(kg: Double): String =
        if (kg >= 1000) kg(floor(kg / 100 + 0.5) / 10) + " t" else kg(kg) + " kg"

    /** "a", "a and b", "a, b and c". */
    fun list(items: List<String>): String = when (items.size) {
        0 -> ""
        1 -> items[0]
        else -> items.dropLast(1).joinToString(", ") + " and " + items.last()
    }

    /** The non-blank parts joined with a middle dot: "6 exercises · ~55 min". */
    fun dotted(vararg parts: String?): String = parts.filter { !it.isNullOrBlank() }.joinToString(" · ")

    /** Small upper-case labels above a value ("NEXT UP"). */
    fun eyebrow(text: String): String = text.uppercase(Locale.ROOT)

    /** Full English weekday for a Monday-first index 0...6. */
    fun weekdayName(mondayFirstIndex: Int): String =
        DayOfWeek.of(mondayFirstIndex.coerceIn(0, 6) + 1).getDisplayName(TextStyle.FULL, Locale.ENGLISH)
}

/** Calendar maths in the snapshot's time zone (widgets/SPEC.md section 2: "calendar days between" counts local midnights). */
internal object HomeDates {
    fun zoneOf(snapshot: WidgetSnapshot): ZoneId =
        try {
            ZoneId.of(snapshot.timeZoneID)
        } catch (_: DateTimeException) {
            ZoneOffset.UTC
        }

    /** Local midnights crossed between [from] and [to]; a [from] after [to] counts as 0. */
    fun daysBetween(from: Instant, to: Instant, zone: ZoneId): Int =
        ChronoUnit.DAYS.between(from.atZone(zone).toLocalDate(), to.atZone(zone).toLocalDate()).toInt().coerceAtLeast(0)

    /** "Today", "Yesterday", a short weekday within the last week ("Fri"), else the date ("Oct 3"). */
    fun dayLabel(then: Instant, now: Instant, zone: ZoneId): String {
        val date = then.atZone(zone)
        return when (daysBetween(then, now, zone)) {
            0 -> "Today"
            1 -> "Yesterday"
            in 2..6 -> date.dayOfWeek.getDisplayName(TextStyle.SHORT, Locale.ENGLISH)
            else -> date.month.getDisplayName(TextStyle.SHORT, Locale.ENGLISH) + " " + date.dayOfMonth
        }
    }

    /** "today", "yesterday", "3 days ago" in running text. */
    fun daysAgoLower(days: Int): String = when {
        days <= 0 -> "today"
        days == 1 -> "yesterday"
        else -> "$days days ago"
    }

    /** "today", "yesterday", "3d ago" where space is short. */
    fun shortAgo(days: Int): String = when {
        days <= 0 -> "today"
        days == 1 -> "yesterday"
        else -> "${days}d ago"
    }
}
