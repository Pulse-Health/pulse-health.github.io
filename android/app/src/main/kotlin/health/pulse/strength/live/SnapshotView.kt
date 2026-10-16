package health.pulse.strength.live

import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.WorkoutSnapshot
import java.time.Duration
import java.time.Instant

/**
 * The phase to show at [now]. The engine only publishes a snapshot when something changes, so a rest whose countdown has run out is
 * still `resting` in the latest one; here it is already over. A paused workout never has a running rest.
 */
internal fun WorkoutSnapshot.displayPhase(now: Instant): SnapshotPhase {
    val end = restEndsAt
    return if (phase == SnapshotPhase.RESTING && !isPaused && end != null && !end.isAfter(now)) SnapshotPhase.REST_OVER else phase
}

/** Whole seconds left on the rest at [now], rounded up so the clock shows 0:01 until the rest is over; the frozen value while paused. */
internal fun WorkoutSnapshot.restRemainingSeconds(now: Instant): Int {
    if (isPaused) return (restFrozenRemaining ?: 0).coerceAtLeast(0)
    val end = restEndsAt ?: return 0
    val millis = Duration.between(now, end).toMillis()
    return if (millis <= 0) 0 else ((millis + 999) / 1000).toInt()
}
