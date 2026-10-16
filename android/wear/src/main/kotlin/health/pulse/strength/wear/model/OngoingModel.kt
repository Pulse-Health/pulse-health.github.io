package health.pulse.strength.wear.model

import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.WorkoutSnapshot
import java.time.Instant

/** What the Ongoing Activity chip on the watch face says: the clock of the workout, the rest countdown, or a short state. */
internal sealed interface OngoingStatus {
    /** The workout clock counting up from [startMillis]. */
    data class Elapsed(val startMillis: Long) : OngoingStatus

    /** The workout is paused: the clock stands still at [pausedAtMillis]. */
    data class ElapsedPaused(val startMillis: Long, val pausedAtMillis: Long) : OngoingStatus

    /** The rest countdown runs out at [endsAtMillis]. */
    data class Rest(val endsAtMillis: Long) : OngoingStatus

    /** The workout is paused during a rest with [remainingSeconds] left. */
    data class RestPaused(val remainingSeconds: Int) : OngoingStatus

    data object RestOver : OngoingStatus

    data object Complete : OngoingStatus
}

/** WA-02: the content of the Ongoing Activity and of the notification behind it, derived from the running workout. */
internal data class OngoingModel(
    /** The workout name. */
    val title: String,
    /** "Bench Press · Set 3 of 4" */
    val text: String,
    val status: OngoingStatus,
    /** What a screen reader says for the chip. */
    val description: String,
) {
    companion object {
        fun of(active: WorkoutSnapshot, now: Instant): OngoingModel {
            val status = status(active, now)
            val text = if (status == OngoingStatus.Complete) "${active.loggedSets} sets logged" else "${active.exerciseName} · ${active.setLabel}"
            return OngoingModel(active.workoutName, text, status, "${active.workoutName}. ${describe(status)}")
        }

        private fun status(active: WorkoutSnapshot, now: Instant): OngoingStatus {
            val startMillis = active.activeStart.toEpochMilli()
            val endsAt = active.restEndsAt
            val frozen = active.restFrozenRemaining
            return when {
                active.phase == SnapshotPhase.COMPLETE -> OngoingStatus.Complete
                active.isPaused && frozen != null -> OngoingStatus.RestPaused(frozen.coerceAtLeast(0))
                active.isPaused -> OngoingStatus.ElapsedPaused(startMillis, startMillis + active.elapsedWhenPaused * MILLIS_PER_SECOND)
                active.phase == SnapshotPhase.RESTING && endsAt != null && endsAt.isAfter(now) -> OngoingStatus.Rest(endsAt.toEpochMilli())
                active.phase == SnapshotPhase.LOGGING -> OngoingStatus.Elapsed(startMillis)
                else -> OngoingStatus.RestOver
            }
        }

        private fun describe(status: OngoingStatus): String = when (status) {
            is OngoingStatus.Elapsed -> "Workout running"
            is OngoingStatus.ElapsedPaused -> "Workout paused"
            is OngoingStatus.Rest -> "Resting"
            is OngoingStatus.RestPaused -> "Workout paused during a rest, ${WearText.spoken(status.remainingSeconds)} left"
            OngoingStatus.RestOver -> "Rest is over"
            OngoingStatus.Complete -> "All sets logged"
        }

        private const val MILLIS_PER_SECOND = 1000L
    }
}
