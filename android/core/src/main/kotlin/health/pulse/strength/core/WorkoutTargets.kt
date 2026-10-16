package health.pulse.strength.core

/** Address of one set inside a workout: the exercise position and the set position. */
data class SetTarget(
    /** Index into `WorkoutState.exercises`. */
    val exerciseIndex: Int,
    /** Index into that exercise's `sets`. */
    val setIndex: Int,
)

/** Finds the set that "log next set" (notification actions, nudges) acts on. */
object WorkoutTargets {
    /** First pending set of the current exercise; else of the following exercises, then of the earlier ones; null when all are logged. */
    fun nextPending(state: WorkoutState): SetTarget? {
        val count = state.exercises.size
        if (count <= 0) return null
        val start = state.clampedIndex
        for (offset in 0 until count) {
            val exerciseIndex = (start + offset) % count
            val setIndex = state.exercises[exerciseIndex].sets.indexOfFirst { !it.isDone }
            if (setIndex >= 0) return SetTarget(exerciseIndex = exerciseIndex, setIndex = setIndex)
        }
        return null
    }
}
