package health.pulse.strength.widgets.extras

import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.lock.LockText
import health.pulse.strength.widgets.lock.PulseFormat

/** One dot per set of the shown exercise. */
internal enum class DotState { DONE, CURRENT, PENDING }

/**
 * The label between a stepper's two buttons ("82.5 kg"; [shortLabel] is the bare "82.5" for a stepper too narrow for the unit), and what
 * a screen reader says for each button.
 */
internal data class StepperView(
    val label: String,
    val shortLabel: String,
    val lessDescription: String,
    val moreDescription: String,
)

/** What the log-a-set widget (WI-02) shows: one state per situation of the running workout, so the layout only draws what makes sense. */
internal sealed interface LogSetView {
    /** No workout runs: offer to start the next template. */
    data class Idle(val title: String, val detail: String, val canStart: Boolean) : LogSetView

    /**
     * A set waits to be logged; [weight] is null for bodyweight and timed exercises. [progress] words how far the workout is, from the
     * most to the least ("6 of 20 sets logged", "6 of 20 sets"), for the widget to pick the longest that fits.
     */
    data class Logging(
        val exercise: String,
        val setLabel: String,
        val weight: StepperView?,
        val reps: StepperView,
        val dots: List<DotState>,
        val progress: List<String>,
    ) : LogSetView

    /** The rest timer has [remainingMillis] left; the widget counts it down by itself. [nextSet] is the set that follows. */
    data class Resting(val exercise: String, val remainingMillis: Long, val nextSet: String) : LogSetView

    data class RestOver(val exercise: String, val nextSet: String) : LogSetView

    data class Paused(val workout: String, val detail: String) : LogSetView

    data class Complete(val workout: String, val summary: String) : LogSetView
}

internal object LogSetModel {
    private const val MAX_DOTS = 10
    private const val MIN_DOT = 8f
    private const val MAX_DOT = 22f

    /** The gap in dp after each set dot. */
    const val DOT_GAP_DP = 4f

    /** The state of the widget at [nowMillis] (epoch milliseconds): which controls make sense for the running workout. */
    fun of(snapshot: WidgetSnapshot, nowMillis: Long): LogSetView {
        val active = snapshot.active
        if (active == null) {
            val next = snapshot.nextUp
            return if (next != null) {
                LogSetView.Idle(next.name, LockText.templateDetail(next), canStart = true)
            } else {
                LogSetView.Idle("No workout yet", "Create a template in Pulse Strength.", canStart = false)
            }
        }
        val progress = "${active.loggedSets} of ${active.totalSets} sets logged"
        if (active.isPaused) {
            val frozen = active.restFrozenRemaining
            return LogSetView.Paused(active.workoutName, if (frozen != null) "Rest paused at ${PulseFormat.clock(frozen)}" else progress)
        }
        return when (active.phase) {
            SnapshotPhase.COMPLETE -> LogSetView.Complete(active.workoutName, progress)
            SnapshotPhase.REST_OVER -> LogSetView.RestOver(active.exerciseName, active.nextSetText)
            SnapshotPhase.RESTING -> {
                // A snapshot that outlived its rest (the end passed since it was made) reads as over, not as a negative countdown.
                val remaining = (active.restEndsAt?.toEpochMilli() ?: 0L) - nowMillis
                if (remaining > 0) {
                    LogSetView.Resting(active.exerciseName, remaining, active.nextSetText)
                } else {
                    LogSetView.RestOver(active.exerciseName, active.nextSetText)
                }
            }
            SnapshotPhase.LOGGING -> LogSetView.Logging(
                exercise = active.exerciseName,
                setLabel = active.setLabel,
                weight = if (active.showsWeight) {
                    StepperView("${active.weightText} kg", active.weightText, "Decrease weight", "Increase weight")
                } else {
                    null
                },
                reps = if (active.tracking == TrackingKind.DURATION) {
                    StepperView("${active.repsText} ${active.repsUnit}", active.repsText, "Less time", "More time")
                } else {
                    StepperView("${active.repsText} ${active.repsUnit}", active.repsText, "Fewer reps", "More reps")
                },
                dots = dots(active.exerciseDoneSets, active.exerciseSetCount),
                progress = listOf(progress, "${active.loggedSets} of ${active.totalSets} sets"),
            )
        }
    }

    /** The width in dp of one set dot when [count] of them share [availableDp] with a gap after each: between 8 and 22 dp. */
    fun dotWidth(count: Int, availableDp: Float): Float =
        if (count <= 0) MAX_DOT else (availableDp / count - DOT_GAP_DP).coerceIn(MIN_DOT, MAX_DOT)

    /** Logged sets, the one to log now, and those still to come; at most [MAX_DOTS] so a long exercise does not overflow the row. */
    fun dots(done: Int?, count: Int?): List<DotState> {
        val total = (count ?: 0).coerceIn(0, MAX_DOTS)
        val finished = (done ?: 0).coerceAtLeast(0)
        return List(total) { index ->
            when {
                index < finished -> DotState.DONE
                index == finished -> DotState.CURRENT
                else -> DotState.PENDING
            }
        }
    }
}
