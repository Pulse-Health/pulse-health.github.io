package health.pulse.strength.core.widgets

import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.HeartRateSample
import health.pulse.strength.core.PersonalRecord
import health.pulse.strength.core.roundedAwayFromZero
import health.pulse.strength.core.timeIntervalSince
import java.time.Instant
import kotlin.math.abs

/** The most recent session and the newest personal record (widgets/SPEC.md section 2: lastSession, latestPR). */
internal object WidgetSessions {
    /** Fewest heart-rate samples that make a curve. */
    const val minimumHeartRateSamples = 4

    /** Most bars of the heart-rate curve. */
    const val maximumHeartRateBars = 16

    /** The longest time a set counts as lifting; the rest of the gap before it is rest. */
    const val liftingSeconds = 45L

    /** A rest longer than this many seconds is a long rest. */
    const val longRestSeconds = 180L

    // region Last session

    /** The workout with the greatest `finishedAt` (the first one on a tie) as a session summary; null without history. */
    fun lastSession(history: WidgetHistory): SessionSummary? {
        val workout = history.latest?.workout ?: return null
        val curve = heartRateCurve(workout.heartRateSeries ?: emptyList())
        val stretches = timeline(workout)
        return SessionSummary(
            workoutID = workout.id.toString(),
            name = workout.name,
            finishedAt = workout.finishedAt,
            durationMinutes = roundedMinutes(workout.durationSeconds),
            loggedSets = workout.loggedSets,
            volumeKg = workout.volumeKg,
            averageHeartRate = workout.averageHeartRate,
            peakHeartRate = curve.peak,
            personalRecordCount = workout.personalRecords.size,
            timeline = stretches.segments,
            underTensionPercent = stretches.underTensionPercent,
            longBreakCount = stretches.longBreakCount,
            heartRateBars = curve.bars,
        )
    }

    /** Whole minutes of [seconds], a half rounding up (negative time counts as none). */
    fun roundedMinutes(seconds: Int): Int {
        val time = maxOf(0, seconds)
        return time / 60 + if (time % 60 >= 30) 1 else 0
    }

    // endregion

    // region Heart rate

    class Curve(val peak: Int?, val bars: List<HeartRateBar>)

    /**
     * The peak and the bars of a heart-rate series. With fewer than [minimumHeartRateSamples] samples there is neither.
     *
     * The samples (in the order recorded) are cut into `min(16, count)` contiguous buckets of near-equal size, the earlier buckets
     * taking the remainder; a bar is the rounded mean of its bucket and is an effort when it is above the rounded mean of all
     * samples. The peak is the highest sample.
     */
    fun heartRateCurve(samples: List<HeartRateSample>): Curve {
        if (samples.size < minimumHeartRateSamples) return Curve(null, emptyList())
        val overall = roundedMean(samples.map { it.bpm })
        val buckets = minOf(maximumHeartRateBars, samples.size)
        val size = samples.size / buckets
        val remainder = samples.size % buckets
        val bars = ArrayList<HeartRateBar>(buckets)
        var start = 0
        for (bucket in 0 until buckets) {
            val end = start + size + if (bucket < remainder) 1 else 0
            val mean = roundedMean(samples.subList(start, end).map { it.bpm })
            bars.add(HeartRateBar(bpm = mean, isEffort = mean > overall))
            start = end
        }
        return Curve(samples.maxOf { it.bpm }, bars)
    }

    /** The mean of [values] rounded half up, in integers. A value is taken as 0...1,000 so a damaged sample cannot overflow the sum. */
    private fun roundedMean(values: List<Int>): Int {
        val count = values.size
        if (count == 0) return 0
        val sum = values.sumOf { it.coerceIn(0, 1_000) }
        return (2 * sum + count) / (2 * count)
    }

    // endregion

    // region Timeline

    class Timeline(val segments: List<TimelineSegment>, val underTensionPercent: Int?, val longBreakCount: Int)

    /**
     * The stretches of a session: lifting, rest and long rest, from the times its sets were logged.
     *
     * Needs `CompletedSet.loggedAt` on at least two sets; sets without a time are ignored, and without enough of them the timeline is
     * empty. The logged sets are put in time order (the workout's own order on a tie) and times are taken in whole seconds. The gap
     * before a set (to the previous set, to the start of the workout for the first) is lifting for up to 45 seconds and rest for
     * the remainder: a long rest above 180 seconds. Per set the rest comes first, then the lifting; a stretch of no time is skipped and
     * neighbours of the same kind are merged.
     */
    fun timeline(workout: CompletedWorkout): Timeline {
        val logged = workout.exercises.flatMap { it.sets }.mapNotNull { it.loggedAt }.map(::wholeSeconds).sorted()
        if (logged.size < 2) return Timeline(emptyList(), null, 0)

        val kinds = ArrayList<TimelineKind>()
        val lengths = ArrayList<Long>()
        fun add(kind: TimelineKind, seconds: Long) {
            if (seconds <= 0) return
            if (kinds.isNotEmpty() && kinds.last() == kind) {
                lengths[lengths.size - 1] = lengths.last() + seconds
            } else {
                kinds.add(kind)
                lengths.add(seconds)
            }
        }
        var previous = wholeSeconds(workout.startedAt)
        for (time in logged) {
            val gap = maxOf(0L, time - previous)
            val lifting = minOf(gap, liftingSeconds)
            val rest = gap - lifting
            add(if (rest > longRestSeconds) TimelineKind.LONG_REST else TimelineKind.REST, rest)
            add(TimelineKind.LIFTING, lifting)
            previous = time
        }

        val total = lengths.sum()
        val lifting = kinds.indices.filter { kinds[it] == TimelineKind.LIFTING }.sumOf { lengths[it] }
        return Timeline(
            segments = kinds.indices.map { TimelineSegment(kinds[it], lengths[it].coerceAtMost(Int.MAX_VALUE.toLong()).toInt()) },
            underTensionPercent = if (total > 0) ((200 * lifting + total) / (2 * total)).toInt() else null,
            longBreakCount = kinds.count { it == TimelineKind.LONG_REST },
        )
    }

    /** [instant] in whole seconds since the epoch, a half rounding away from zero; 0 for an instant too far from it. */
    private fun wholeSeconds(instant: Instant): Long {
        val seconds = instant.timeIntervalSince(Instant.EPOCH)
        if (!seconds.isFinite() || abs(seconds) >= 1e15) return 0
        return seconds.roundedAwayFromZero().toLong()
    }

    // endregion

    // region Latest record

    /**
     * The newest personal record: the workout with the greatest `finishedAt` among those that set records (the first on a tie), and
     * in it the record with the highest estimated 1RM (the first on a tie). `deltaKg` is the estimate minus the previous best (0 when
     * there was none); the record is fresh when it is at most 24 hours old.
     */
    fun latestPR(history: WidgetHistory): PRSummary? {
        val workout = history.entries
            .map { it.workout }
            .filter { it.personalRecords.isNotEmpty() }
            .maxWithOrNull(compareBy { it.finishedAt }) ?: return null
        val record: PersonalRecord = workout.personalRecords.maxWithOrNull(compareBy { it.estimated1RM }) ?: return null
        val age = history.now.timeIntervalSince(workout.finishedAt)
        return PRSummary(
            exerciseID = record.exerciseID,
            exerciseName = record.exerciseName,
            weightKg = record.weightKg,
            reps = record.reps,
            estimated1RM = record.estimated1RM,
            deltaKg = if (record.previousBest == 0.0) 0.0 else record.estimated1RM - record.previousBest,
            achievedAt = workout.finishedAt,
            isFresh = age >= 0 && age <= 24 * 3_600,
        )
    }

    // endregion
}
