package health.pulse.strength.wear.model

import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.core.widgets.HeartRateBar
import health.pulse.strength.core.widgets.LiftTrend
import health.pulse.strength.core.widgets.PRSummary
import health.pulse.strength.wear.data.WearView
import java.time.Duration
import java.time.Instant
import kotlin.math.ceil
import kotlin.math.max

/*
 * What each tile shows, derived from the snapshot as plain data. The tile services only turn these models into layouts, so the
 * decisions (which state, which words, which numbers) are testable without the tile renderer.
 */

/** WA-03: the next workout and its Start button. */
internal sealed interface NextUpTileModel {
    /** Only the preview exists: the phone has not synced yet. */
    data object Waiting : NextUpTileModel

    /** The user has no templates yet. */
    data object NoWorkout : NextUpTileModel

    data class Ready(
        /** "Push day" */
        val split: String,
        /** "Upper A · Push" */
        val name: String,
        /** "6 exercises · ~55 min" */
        val detail: String,
    ) : NextUpTileModel

    /** A workout is already running: the tile offers to open it instead of starting another. */
    data class Running(val name: String, val detail: String) : NextUpTileModel

    companion object {
        fun of(view: WearView): NextUpTileModel {
            val snapshot = view.snapshot
            val active = snapshot.active
            val nextUp = snapshot.nextUp
            return when {
                view.isPlaceholder -> Waiting
                active != null -> Running(active.workoutName, progress(active))
                nextUp == null -> NoWorkout
                else -> Ready(
                    split = nextUp.splitLabel,
                    name = nextUp.name,
                    detail = WearText.planSummary(nextUp.exerciseCount, nextUp.estimatedMinutes),
                )
            }
        }

        private fun progress(active: WorkoutSnapshot): String =
            if (active.phase == SnapshotPhase.COMPLETE) "All sets logged" else "${active.loggedSets} of ${active.totalSets} sets"
    }
}

/** WA-04 and WA-05: the one tile that follows the running workout. */
internal sealed interface WorkoutTileModel {
    data object Waiting : WorkoutTileModel

    /** No workout is running: the next one can be started from here. */
    data class Idle(val next: NextUpTileModel) : WorkoutTileModel

    /** A set waits to be logged (or the rest is over and the next set is due). */
    data class Logging(
        val exercise: String,
        /** "Set 3 of 4" */
        val setLabel: String,
        /** "80 kg × 6" */
        val work: String,
        val restOver: Boolean,
    ) : WorkoutTileModel {
        val description: String get() = "Log set. $exercise, $setLabel, $work"
    }

    /** A rest countdown runs until [endsAt]; [afterRest] is what the tile shows from then on. */
    data class Resting(
        val startedAt: Instant,
        val endsAt: Instant,
        val totalSeconds: Int,
        /** Whole seconds left when the model was made, the fallback for renderers without live countdowns. */
        val remainingSeconds: Int,
        /** "Next · 80 kg × 6" */
        val next: String,
        val afterRest: Logging,
    ) : WorkoutTileModel {
        /** Share of the rest that is over, 0...1 (also the static fallback of the progress bar). */
        val elapsedFraction: Float
            get() = if (totalSeconds <= 0) 1f else (1f - remainingSeconds.toFloat() / totalSeconds).coerceIn(0f, 1f)
    }

    data class Paused(val workoutName: String, val elapsedSeconds: Int) : WorkoutTileModel

    /** Every set is logged; finishing happens in the app. */
    data class Complete(val workoutName: String, val sets: String) : WorkoutTileModel

    companion object {
        fun of(view: WearView, now: Instant): WorkoutTileModel {
            val snapshot = view.snapshot
            val active = snapshot.active
            return when {
                view.isPlaceholder -> Waiting
                active == null -> Idle(NextUpTileModel.of(view))
                active.phase == SnapshotPhase.COMPLETE -> Complete(active.workoutName, "${active.loggedSets} sets logged")
                active.isPaused -> Paused(active.workoutName, active.elapsedWhenPaused)
                else -> {
                    val endsAt = active.restEndsAt
                    when {
                        active.phase == SnapshotPhase.RESTING && endsAt != null && endsAt.isAfter(now) -> resting(active, endsAt, now)
                        else -> logging(active, restOver = active.phase != SnapshotPhase.LOGGING)
                    }
                }
            }
        }

        private fun logging(active: WorkoutSnapshot, restOver: Boolean) = Logging(
            exercise = active.exerciseName,
            setLabel = active.setLabel,
            work = WearText.work(active),
            restOver = restOver,
        )

        private fun resting(active: WorkoutSnapshot, endsAt: Instant, now: Instant): Resting {
            val remaining = ceil(Duration.between(now, endsAt).toMillis() / 1000.0).toInt()
            val total = max(active.restTotalSeconds, remaining)
            return Resting(
                startedAt = endsAt.minusSeconds(total.toLong()),
                endsAt = endsAt,
                totalSeconds = total,
                remainingSeconds = remaining,
                next = WearText.nextSet(active),
                afterRest = logging(active, restOver = true),
            )
        }
    }
}

/** WA-06: the newest personal record. */
internal sealed interface RecordTileModel {
    data object Waiting : RecordTileModel

    data object NoRecords : RecordTileModel

    data class Record(
        /** "NEW RECORD" within 24 hours of the lift, "LATEST RECORD" afterwards. */
        val badge: String,
        val isFresh: Boolean,
        val exercise: String,
        /** "85 × 5" */
        val lift: String,
        /** "e1RM 99 kg" */
        val estimate: String,
        /** "+4 kg" when the record beat an earlier best. */
        val improvement: String?,
    ) : RecordTileModel {
        val description: String
            get() = "$badge. $exercise, $lift, $estimate" + (improvement?.let { ", $it" } ?: "")
    }

    companion object {
        fun of(view: WearView): RecordTileModel {
            val record = view.snapshot.latestPR
            return when {
                view.isPlaceholder -> Waiting
                record == null -> NoRecords
                else -> Record(
                    badge = if (record.isFresh) "NEW RECORD" else "LATEST RECORD",
                    isFresh = record.isFresh,
                    exercise = record.exerciseName,
                    lift = lift(record),
                    estimate = "e1RM ${WearText.kg(record.estimated1RM)} kg",
                    improvement = record.deltaKg.takeIf { it > 0 }?.let { "+${WearText.kg(it)} kg" },
                )
            }
        }

        private fun lift(record: PRSummary): String =
            if (record.weightKg > 0) "${WearText.kg(record.weightKg)} × ${record.reps}" else "${record.reps} reps"
    }
}

/** WA-08: the estimated 1RM of one lift over its last sessions. */
internal sealed interface LiftTrendTileModel {
    data object Waiting : LiftTrendTileModel

    data object NoLifts : LiftTrendTileModel

    data class Lift(
        /** Position of this lift in the snapshot's list, for the tap that moves to the next one. */
        val index: Int,
        val count: Int,
        val name: String,
        /** "99" */
        val current: String,
        /** "3 sessions · −3 kg" */
        val summary: String,
        /** The estimated 1RM of each session, oldest first. */
        val values: List<Double>,
        /** Index in [values] of the personal record, drawn in gold. */
        val recordIndex: Int?,
    ) : LiftTrendTileModel {
        val description: String
            get() = "$name estimated one rep max ${current} kilograms, $summary" +
                (recordIndex?.let { ", record in session ${it + 1} of ${values.size}" } ?: "")
    }

    companion object {
        /** [requestedIndex] wraps around, so a stored position stays valid when the list of lifts shrinks. */
        fun of(view: WearView, requestedIndex: Int): LiftTrendTileModel {
            val lifts = view.snapshot.lifts
            return when {
                view.isPlaceholder -> Waiting
                lifts.isEmpty() -> NoLifts
                else -> lift(lifts, Math.floorMod(requestedIndex, lifts.size))
            }
        }

        private fun lift(lifts: List<LiftTrend>, index: Int): Lift {
            val trend = lifts[index]
            val sessions = WearText.plural(trend.sessionCount.takeIf { it > 0 } ?: trend.points.size, "session")
            return Lift(
                index = index,
                count = lifts.size,
                name = trend.name,
                current = WearText.kg(trend.currentE1RM),
                summary = if (trend.points.size > 1) "$sessions · ${WearText.deltaKg(trend.deltaKg)}" else sessions,
                values = trend.points.map { it.value },
                recordIndex = trend.prIndex?.takeIf { it in trend.points.indices },
            )
        }
    }
}

/** WA-09: the heart rate of the last session as bars. */
internal sealed interface HeartRateTileModel {
    data object Waiting : HeartRateTileModel

    /** The last session has no heart-rate curve (none recorded, or no session yet). */
    data class NoData(val workout: String?) : HeartRateTileModel

    data class Bars(
        val workout: String,
        val bars: List<Bar>,
        /** "avg 118 · peak 151" */
        val summary: String,
    ) : HeartRateTileModel {
        val description: String
            get() = "Heart rate across $workout, $summary. " +
                bars.joinToString(", ") { "${it.bpm} beats per minute, ${if (it.isEffort) "effort" else "rest"}" }
    }

    /** One bucket of the session; [height] is its share of the tallest bar, 0.2...1. */
    data class Bar(val bpm: Int, val isEffort: Boolean, val height: Float)

    companion object {
        /** The shortest bar, so a rest bucket stays visible next to the peak. */
        private const val FLOOR = 0.2f

        fun of(view: WearView): HeartRateTileModel {
            val session = view.snapshot.lastSession
            return when {
                view.isPlaceholder -> Waiting
                session == null || session.heartRateBars.isEmpty() -> NoData(session?.name)
                else -> Bars(
                    workout = session.name,
                    bars = bars(session.heartRateBars),
                    summary = listOfNotNull(
                        session.averageHeartRate?.let { "avg $it" },
                        session.peakHeartRate?.let { "peak $it" },
                    ).joinToString(" · "),
                )
            }
        }

        /** Heights run from [FLOOR] at 80 % of the lowest bucket to 1 at the highest, so rests and efforts differ visibly. */
        fun bars(buckets: List<HeartRateBar>): List<Bar> {
            val highest = buckets.maxOf { it.bpm }
            val lowest = buckets.minOf { it.bpm }
            val base = lowest * 0.8
            val span = max(highest - base, 1.0)
            return buckets.map { bucket ->
                val share = ((bucket.bpm - base) / span).toFloat()
                Bar(bucket.bpm, bucket.isEffort, FLOOR + (1f - FLOOR) * share.coerceIn(0f, 1f))
            }
        }
    }
}
