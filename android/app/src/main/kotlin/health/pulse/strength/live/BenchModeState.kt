package health.pulse.strength.live

import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.core.widgets.WidgetSnapshot
import java.time.Instant
import java.time.LocalTime

/** What bench mode (SB-02, SB-04) shows, as plain data. [BenchModeStates] derives it from the snapshot and the clock. */
internal sealed interface BenchState {
    /** The rest countdown: the 220 dp ring and the 64 sp clock, with the next set below. */
    data class Resting(val exercise: String, val remainingSeconds: Int, val totalSeconds: Int, val nextLine: String) : BenchState {
        /** The part of the rest that is left, 1 at the start and 0 at the end. */
        val fraction: Float get() = if (totalSeconds <= 0) 0f else (remainingSeconds.toFloat() / totalSeconds).coerceIn(0f, 1f)
    }

    /** The rest ran out: "Go". */
    data class RestOver(val exercise: String, val nextLine: String) : BenchState

    /**
     * A set waits: the weight and the reps, large. [weight] is null for exercises without a weight (reps only, duration);
     * [repsUnit] is "reps" or "s".
     */
    data class Logging(val exercise: String, val setLabel: String, val weight: String?, val reps: String, val repsUnit: String) : BenchState

    data class Paused(val exercise: String, val elapsed: String) : BenchState

    /** Every set is logged ([summary] is the totals), or the workout has no set at all ([summary] says what to do). */
    data class Complete(val title: String, val summary: String) : BenchState

    /** No workout runs: tomorrow's session beside the clock (SB-04), or the next template, or a hint. */
    data class Idle(val headline: String, val title: String?, val detail: String?) : BenchState
}

internal object BenchModeStates {
    fun of(snapshot: WidgetSnapshot, now: Instant, is24Hour: Boolean): BenchState {
        val active = snapshot.active
        if (active == null || active.finish != null) return idle(snapshot, is24Hour)
        val title = active.exerciseName.ifBlank { active.workoutName }
        if (active.isPaused) return BenchState.Paused(title, LiveText.clock(active.elapsedWhenPaused))
        return when (active.displayPhase(now)) {
            SnapshotPhase.RESTING -> BenchState.Resting(title, active.restRemainingSeconds(now), active.restTotalSeconds, "Next: ${active.nextSetText}")
            SnapshotPhase.REST_OVER -> BenchState.RestOver(title, "Next: ${active.nextSetText}")
            SnapshotPhase.COMPLETE -> complete(active)
            SnapshotPhase.LOGGING -> logging(active, title)
        }
    }

    private fun logging(active: WorkoutSnapshot, title: String): BenchState.Logging = BenchState.Logging(
        exercise = title,
        setLabel = active.setLabel,
        weight = if (active.tracking == TrackingKind.WEIGHT_REPS) active.weightText else null,
        reps = active.repsText,
        repsUnit = if (active.tracking == TrackingKind.DURATION) "s" else "reps",
    )

    private fun complete(active: WorkoutSnapshot): BenchState.Complete = when {
        active.totalSets > 0 -> BenchState.Complete("All sets logged", LiveText.progress(active))
        active.exerciseCount == 0 -> BenchState.Complete("No exercises yet", "Add exercises in Pulse Strength")
        else -> BenchState.Complete("No sets yet", "Add sets in Pulse Strength")
    }

    /** SB-04: tomorrow's session (`tomorrow`) comes first, then the next template; the headline says when, from the planned time of day. */
    private fun idle(snapshot: WidgetSnapshot, is24Hour: Boolean): BenchState.Idle {
        snapshot.tomorrow?.let { tomorrow ->
            val minute = tomorrow.plannedMinuteOfDay
            val planned = minute?.let { "Planned ${LiveText.timeOfDay(it, is24Hour)}" }
            return BenchState.Idle(
                headline = if (minute == null) "${tomorrow.weekday} session" else "${dayPart(minute)} session",
                title = tomorrow.templateName,
                detail = listOfNotNull(planned, tomorrow.note.takeIf { it.isNotBlank() }).joinToString(" · ").ifBlank { null },
            )
        }
        snapshot.nextUp?.let { nextUp ->
            val size = buildList {
                if (nextUp.exerciseCount > 0) add(if (nextUp.exerciseCount == 1) "1 exercise" else "${nextUp.exerciseCount} exercises")
                if (nextUp.estimatedMinutes > 0) add("about ${nextUp.estimatedMinutes} min")
            }
            return BenchState.Idle("Next up", nextUp.name, size.joinToString(" · ").ifBlank { null })
        }
        return BenchState.Idle("No workout planned", null, "Plan your next session in Pulse Strength")
    }

    private fun dayPart(minuteOfDay: Int): String = when {
        minuteOfDay < 12 * 60 -> "Morning"
        minuteOfDay < 17 * 60 -> "Afternoon"
        else -> "Evening"
    }

    /** SB-04: the red-on-black night look is on when the person asked for it (the `night` extra), otherwise from 22:00 until 06:00. */
    fun isNight(forced: Boolean?, localTime: LocalTime): Boolean =
        forced ?: (localTime >= NIGHT_STARTS || localTime < NIGHT_ENDS)

    private val NIGHT_STARTS: LocalTime = LocalTime.of(22, 0)
    private val NIGHT_ENDS: LocalTime = LocalTime.of(6, 0)
}
