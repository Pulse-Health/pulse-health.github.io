package health.pulse.strength.core

/**
 * Platform services (ongoing notification, rest alert, Health Connect, haptics) plug into the engine through this
 * interface, so the engine itself stays platform neutral. All callbacks run on the thread that drives the engine (the main
 * thread in the app).
 */
interface WorkoutSideEffect {
    /** A workout was started or restored from disk. */
    fun workoutStarted(state: WorkoutState) {}

    /** The state changed because of [action]. */
    fun workoutChanged(old: WorkoutState, new: WorkoutState, action: WorkoutAction, origin: ActionOrigin) {}

    /** The workout was finished ([completed] != null) or discarded ([completed] == null). */
    fun workoutEnded(state: WorkoutState, completed: CompletedWorkout?) {}
}
