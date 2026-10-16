package health.pulse.strength.core

import java.time.Instant

/** Builds the small [WorkoutSnapshot] shown by the ongoing notification. */
object SnapshotBuilder {
    /** The snapshot of [state] at [now]; its target is the next pending set (`WorkoutTargets.nextPending`). */
    fun make(state: WorkoutState, now: Instant): WorkoutSnapshot {
        val target = WorkoutTargets.nextPending(state)
        val totals = PresenterSupport.totals(state)

        // The exercise shown is the one that owns the target set (the current one while it still has pending sets).
        val shownIndex = target?.exerciseIndex ?: state.clampedIndex
        val shown: WorkoutExercise? = if (state.exercises.isEmpty()) null else state.exercises[shownIndex]
        val targetSet: LoggedSet? = target?.let { state.exercises[it.exerciseIndex].sets[it.setIndex] }

        val remaining = PresenterSupport.restRemainingSeconds(state, now)
        val phase = if (target == null) {
            SnapshotPhase.COMPLETE
        } else if (remaining != null) {
            if (remaining > 0) SnapshotPhase.RESTING else SnapshotPhase.REST_OVER
        } else {
            SnapshotPhase.LOGGING
        }

        val tracking = shown?.exercise?.tracking ?: TrackingKind.WEIGHT_REPS
        val setLabel: String
        val nextSetText: String
        val weightText: String
        val repsText: String
        if (shown != null && target != null && targetSet != null) {
            val position = "Set ${target.setIndex + 1} of ${shown.sets.size}"
            setLabel = if (targetSet.type == SetType.WARMUP) "Warm-up · $position" else position
            nextSetText = nextText(targetSet, target.setIndex + 1, shown.exercise)
            weightText = PresenterSupport.weightText(targetSet, shown.exercise)
            repsText = targetSet.reps.toString()
        } else {
            setLabel = "All sets logged"
            nextSetText = "All sets logged"
            weightText = "–"
            repsText = "–"
        }

        val rest = state.rest
        return WorkoutSnapshot(
            workoutID = state.id,
            revision = state.revision,
            workoutName = state.name,
            activeStart = state.startedAt.addingTimeInterval(state.pausedTotal),
            isPaused = state.isPaused,
            elapsedWhenPaused = if (state.isPaused) state.elapsedSeconds(now) else 0,
            phase = phase,
            exerciseName = shown?.exercise?.name ?: "",
            exerciseIndex = shownIndex,
            exerciseCount = state.exercises.size,
            targetExerciseID = target?.let { state.exercises[it.exerciseIndex].id },
            targetSetID = targetSet?.id,
            setLabel = setLabel,
            tracking = tracking,
            weightText = weightText,
            repsText = repsText,
            repsUnit = if (tracking == TrackingKind.DURATION) "sec" else "reps",
            showsWeight = tracking == TrackingKind.WEIGHT_REPS,
            restStartedAt = rest?.endsAt?.addingTimeInterval(-rest.totalSeconds.toDouble()),
            restEndsAt = rest?.endsAt,
            restTotalSeconds = rest?.totalSeconds ?: 0,
            restFrozenRemaining = if (state.isPaused) remaining else null,
            heartRate = state.heartRate,
            volumeText = NumberText.thousands(totals.volumeKg),
            loggedSets = totals.loggedSets,
            totalSets = totals.totalSets,
            nextSetText = nextSetText,
            nextExerciseName = nextExerciseName(state, shownIndex),
        )
    }

    /** "Set 4 · 82.5 kg × 6", "Warm-up · 50 kg × 8", "Set 1 · 12 reps" or "Set 1 · 45 s". */
    private fun nextText(set: LoggedSet, position: Int, exercise: Exercise): String {
        val label = if (set.type == SetType.WARMUP) "Warm-up" else "Set $position"
        return label + " · " + PresenterSupport.workText(set, exercise)
    }

    /** The first exercise after [index] that still has pending sets. */
    private fun nextExerciseName(state: WorkoutState, index: Int): String? {
        if (index + 1 >= state.exercises.size) return null
        return state.exercises.subList(index + 1, state.exercises.size).firstOrNull { e -> e.sets.any { !it.isDone } }?.exercise?.name
    }
}
