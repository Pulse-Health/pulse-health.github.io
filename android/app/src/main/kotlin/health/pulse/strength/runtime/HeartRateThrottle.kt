package health.pulse.strength.runtime

import health.pulse.strength.core.WorkoutState
import health.pulse.strength.core.timeIntervalSince
import java.time.Instant
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * The states of a workout without the changes that only bring a new heart rate and follow another such change within [interval]
 * seconds. A watch reports a reading every second or two, and a snapshot rebuilt and every surface redrawn for each of them would be
 * wasted work; every other change passes at once and carries the latest reading with it.
 */
internal fun Flow<WorkoutState?>.heartRateThrottled(interval: Double, clock: () -> Instant): Flow<WorkoutState?> = flow {
    var previous: WorkoutState? = null
    var lastReading: Instant? = null
    collect { state ->
        val before = previous
        previous = state
        if (before != null && state != null && state.onlyHeartRateDiffers(before)) {
            val now = clock()
            val last = lastReading
            if (last != null && !now.isBefore(last) && now.timeIntervalSince(last) < interval) return@collect
            lastReading = now
        }
        emit(state)
    }
}

/** True when this state differs from [other] in nothing but the heart-rate readings. */
private fun WorkoutState.onlyHeartRateDiffers(other: WorkoutState): Boolean =
    this != other &&
        copy(
            heartRate = other.heartRate,
            heartRateSum = other.heartRateSum,
            heartRateCount = other.heartRateCount,
            heartRateSeries = other.heartRateSeries,
        ) == other
