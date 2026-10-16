package health.pulse.strength.core

import java.time.Instant

/**
 * How recovered each muscle group is (percent, 0...100), worked out from the user's own finished workouts. The iOS demo build uses fixed
 * numbers ([DemoRecovery]); a real install needs numbers that follow the training.
 *
 * It is a simple, transparent rule of thumb, not medical advice:
 *
 * * A muscle group recovers in [baseHours] (48 h) after a workout that trained it with up to [easySets] (6) working sets, plus
 *   [extraHoursPerSet] (4 h) for every set beyond that, at most [maxHours] (72 h). Only the most recent workout that trained the
 *   muscle counts; warm-up sets do not.
 * * Recovery grows in a straight line from 0 % right after that workout to 100 % when the time is up.
 * * A muscle that was never trained is 100 % recovered.
 */
class RecoveryModel(
    private val history: () -> List<CompletedWorkout>,
    private val clock: () -> Instant = { Instant.now() },
) {
    private var cachedHistory: List<CompletedWorkout>? = null
    private var cachedMinute: Long = Long.MIN_VALUE
    private var cached: Map<MuscleGroup, Int> = emptyMap()

    /** Percent recovered of [muscle] now. */
    fun percent(muscle: MuscleGroup): Int {
        val workouts = history()
        val now = clock()
        val minute = now.epochSecond / 60
        if (cachedHistory !== workouts || cachedMinute != minute) {
            cached = MuscleGroup.entries.associateWith { compute(workouts, it, now) }
            cachedHistory = workouts
            cachedMinute = minute
        }
        return cached[muscle] ?: 100
    }

    /** This model as the provider the presenter and the hub use. */
    val provider: RecoveryProvider = { muscle -> percent(muscle) }

    companion object {
        const val baseHours = 48.0
        const val easySets = 6
        const val extraHoursPerSet = 4.0
        const val maxHours = 72.0

        /** The hours [muscle] needs to recover after a workout with [sets] working sets of it. */
        fun recoveryHours(sets: Int): Double = minOf(maxHours, baseHours + extraHoursPerSet * maxOf(0, sets - easySets))

        /** Percent recovered of [muscle] at [now] given the finished [workouts] (in any order). */
        fun compute(workouts: List<CompletedWorkout>, muscle: MuscleGroup, now: Instant): Int {
            var latest: CompletedWorkout? = null
            var latestSets = 0
            for (workout in workouts) {
                val sets = workout.muscleSets.firstOrNull { it.muscle == muscle }?.sets ?: 0
                if (sets <= 0) continue
                if (latest == null || workout.finishedAt.isAfter(latest.finishedAt)) {
                    latest = workout
                    latestSets = sets
                }
            }
            if (latest == null) return 100
            val hours = maxOf(0.0, now.timeIntervalSince(latest.finishedAt)) / 3600.0
            val fraction = hours / recoveryHours(latestSets)
            return (fraction * 100).roundedAwayFromZero().toInt().coerceIn(0, 100)
        }
    }
}
