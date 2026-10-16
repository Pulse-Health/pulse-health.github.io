package health.pulse.strength.ui.detail

import health.pulse.strength.core.E1RMPoint
import health.pulse.strength.core.NumberText
import health.pulse.strength.core.addingTimeInterval
import health.pulse.strength.core.roundedAwayFromZero
import health.pulse.strength.core.timeIntervalSince
import java.time.Instant
import java.time.ZoneId
import kotlin.math.ceil
import kotlin.math.floor

// The numbers and texts behind the exercise detail screen: pure Kotlin, so they can be tested without a UI.

// region Text formats

internal object ExerciseDetailFormat {
    /** "99 kg", or an en dash without a value. */
    fun e1RM(value: Double): String {
        if (!value.isFinite() || value <= 0) return "–"
        return NumberText.kg(value.roundedAwayFromZero()) + " kg"
    }

    /** The store's "85 kg × 5" shows as "85 × 5" in the tile; "12 reps" and "45 s" stay as they are. */
    fun bestSet(text: String?): String {
        if (text.isNullOrEmpty()) return "–"
        return text.replace(" kg", "")
    }

    /** "12.5 t" from one tonne on, "840 kg" below. */
    fun volume(kg: Double): String {
        if (!kg.isFinite() || kg <= 0) return "0 kg"
        if (kg < 1000) return NumberText.thousands(kg) + " kg"
        val tonnes = (kg / 100).roundedAwayFromZero() / 10
        return NumberText.kg(tonnes) + " t"
    }

    fun sessionCount(count: Int): String = if (count == 1) "1 session" else "$count sessions"
}

// endregion

// region Range

/** The time windows of the estimated-1RM chart (the "12w" menu of the design). */
internal enum class ExerciseDetailRange(val chipTitle: String, val menuTitle: String, val days: Int?) {
    FOUR_WEEKS("4w", "4 weeks", 28),
    TWELVE_WEEKS("12w", "12 weeks", 84),
    SIX_MONTHS("6m", "6 months", 182),
    ONE_YEAR("1y", "1 year", 365),
    ALL("All", "All time", null),
}

// endregion

// region Chart data

internal data class ExerciseDetailChartPoint(
    val id: Int,
    val date: Instant,
    val value: Double,
    val isLast: Boolean,
)

/** The vertical scale: rounded bounds with two grid intervals at most (93...99 kg gives 90, 95, 100). */
internal class ExerciseDetailAxis(val lower: Double, val upper: Double, val ticks: List<Double>) {
    companion object {
        private val steps = listOf(1.0, 2.0, 2.5, 5.0, 10.0, 20.0, 25.0, 50.0, 100.0, 200.0, 250.0, 500.0, 1000.0)

        fun make(values: List<Double>): ExerciseDetailAxis {
            val minimum = values.minOrNull()
            val maximum = values.maxOrNull()
            if (minimum == null || maximum == null) return ExerciseDetailAxis(0.0, 100.0, listOf(0.0, 50.0, 100.0))
            var low = minimum
            var high = maximum
            if (high - low < 1) {
                low -= 2.5
                high += 2.5
            }
            var chosen = steps.last()
            for (step in steps) {
                val lowerTick = floor(low / step) * step
                val upperTick = ceil(high / step) * step
                if ((upperTick - lowerTick) / step <= 2.0001) {
                    chosen = step
                    break
                }
            }
            val lower = floor(low / chosen) * chosen
            var upper = ceil(high / chosen) * chosen
            if (upper - lower < chosen) upper = lower + chosen
            val ticks = mutableListOf(lower)
            if ((upper - lower) / chosen > 1.5) ticks.add((lower + upper) / 2)
            ticks.add(upper)
            return ExerciseDetailAxis(lower, upper, ticks)
        }
    }
}

/**
 * The time between two sessions: "5 d" / "3 wk" for the trend text, "5 days" / "3 weeks" for TalkBack. Whole days below a week,
 * rounded weeks from then on, never less than one.
 */
internal class ExerciseDetailSpan(from: Instant, to: Instant) {
    val short: String
    val spoken: String

    init {
        val days = maxOf(1, (to.timeIntervalSince(from) / 86_400).roundedAwayFromZero().toInt())
        if (days < 7) {
            short = "$days d"
            spoken = if (days == 1) "1 day" else "$days days"
        } else {
            val weeks = maxOf(1, (days.toDouble() / 7).roundedAwayFromZero().toInt())
            short = "$weeks wk"
            spoken = if (weeks == 1) "1 week" else "$weeks weeks"
        }
    }
}

// endregion

/**
 * Everything the chart card shows for one window: the points, the dates, the scale, the best value and the trend.
 *
 * One figure runs through the tile, the chart heading and the TalkBack text: [best], the highest estimate of the sessions in the
 * window, and its gain over the first session in whole kilograms (the design: "99 kg", "6 kg · 12 wk", "rising from 93 to 99
 * kilograms"). The span named in the texts is the time between the two sessions compared, not the length of the selected window.
 */
internal class ExerciseDetailProgress(
    series: List<E1RMPoint>,
    range: ExerciseDetailRange,
    now: Instant,
    zone: ZoneId = ZoneId.systemDefault(),
) {
    enum class Direction { UP, DOWN, FLAT, UNKNOWN }

    val points: List<ExerciseDetailChartPoint>

    /** Horizontal domain of the chart. */
    val start: Instant
    val end: Instant

    /** Dates printed under the chart and in the heading ("Jul 21 – Oct 13"). */
    val startLabel: String
    val middleLabel: String
    val endLabel: String
    val axis: ExerciseDetailAxis

    /** The highest estimate of the sessions in the window; null without a session. */
    val best: Double?
    val direction: Direction

    /** "6 kg · 12 wk", "No change" or an en dash. */
    val trendText: String

    /** "up 6 kilograms over 12 weeks" for TalkBack; null when [trendText] is not a gain. */
    val spokenTrend: String?

    /** TalkBack text of the chart: the figures and the dates of the first session and the best one. */
    val summary: String

    init {
        val ordered = series.filter { it.value.isFinite() }.sortedBy { it.date }

        var windowStart: Instant = ordered.firstOrNull()?.date ?: now
        val days = range.days
        if (days != null) {
            windowStart = runCatching { now.atZone(zone).minusDays(days.toLong()).toInstant() }
                .getOrElse { now.addingTimeInterval(-days.toDouble() * 86_400) }
        }
        val visible = ordered.filter { !it.date.isBefore(windowStart) }

        var displayEnd = now
        val lastDate = visible.lastOrNull()?.date
        if (lastDate != null && lastDate.isAfter(displayEnd)) displayEnd = lastDate
        var domainEnd = displayEnd
        if (domainEnd.timeIntervalSince(windowStart) < 86_400) domainEnd = windowStart.addingTimeInterval(86_400.0)
        val middle = windowStart.addingTimeInterval(displayEnd.timeIntervalSince(windowStart) / 2)

        points = visible.mapIndexed { index, point ->
            ExerciseDetailChartPoint(id = index, date = point.date, value = point.value, isLast = index == visible.size - 1)
        }

        // The best session of the window (the earliest one on a tie) against the first one.
        var bestPoint: E1RMPoint? = null
        for (point in visible) {
            val current = bestPoint
            if (current != null && point.value <= current.value) continue
            bestPoint = point
        }

        var direction = Direction.UNKNOWN
        var trendText = "–"
        var spokenTrend: String? = null
        var summary = "No estimated one-rep max in this range"
        val first = visible.firstOrNull()
        val peak = bestPoint
        if (first != null && peak != null) {
            val fromKg = first.value.roundedAwayFromZero()
            val toKg = peak.value.roundedAwayFromZero()
            val fromText = NumberText.kg(fromKg)
            val toText = NumberText.kg(toKg)
            // The line ends below the best when the latest session was weaker: TalkBack is told, the heading is not.
            var latestNote = ""
            val last = visible.last()
            if (last.value.roundedAwayFromZero() < toKg) {
                latestNote = ", latest " + NumberText.kg(last.value.roundedAwayFromZero()) + " kilograms"
            }
            val sessions = if (visible.size == 1) "1 session" else "${visible.size} sessions"
            if (visible.size < 2) {
                summary = "Estimated one-rep max $toText kilograms on ${StrengthResultText.monthDay(first.date, now, zone)}, $sessions"
            } else if (toKg > fromKg) {
                val span = ExerciseDetailSpan(first.date, peak.date)
                direction = Direction.UP
                trendText = NumberText.kg(toKg - fromKg) + " kg · " + span.short
                spokenTrend = "up " + NumberText.kg(toKg - fromKg) + " kilograms over " + span.spoken
                summary = "Estimated one-rep max rising from $fromText kilograms on ${StrengthResultText.monthDay(first.date, now, zone)} " +
                    "to $toText kilograms on ${StrengthResultText.monthDay(peak.date, now, zone)}, over ${span.spoken}$latestNote, $sessions"
            } else {
                val span = ExerciseDetailSpan(first.date, last.date)
                direction = Direction.FLAT
                trendText = "No change"
                summary = "Estimated one-rep max steady at $toText kilograms from ${StrengthResultText.monthDay(first.date, now, zone)} " +
                    "to ${StrengthResultText.monthDay(last.date, now, zone)}, over ${span.spoken}$latestNote, $sessions"
            }
        }

        this.start = windowStart
        this.end = domainEnd
        this.startLabel = StrengthResultText.monthDay(windowStart, now, zone)
        this.middleLabel = StrengthResultText.monthDay(middle, now, zone)
        this.endLabel = StrengthResultText.monthDay(displayEnd, now, zone)
        this.axis = ExerciseDetailAxis.make(visible.map { it.value })
        this.best = bestPoint?.value
        this.direction = direction
        this.trendText = trendText
        this.spokenTrend = spokenTrend
        this.summary = summary
    }

    /** "Jul 21 – Oct 13" */
    val rangeLabel: String get() = "$startLabel – $endLabel"

    /** The heading figure: "99 kg" or an en dash. */
    val bestText: String
        get() = best?.let { NumberText.kg(it.roundedAwayFromZero()) + " kg" } ?: "–"
}
