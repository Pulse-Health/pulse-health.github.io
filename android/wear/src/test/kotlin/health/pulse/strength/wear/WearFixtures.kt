package health.pulse.strength.wear

import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.core.widgets.preview
import health.pulse.strength.wear.data.WearView
import java.time.Instant
import java.util.UUID

/** Snapshots for the tests: the preview (3 of 4 workouts, a fresh record, no running workout) and running workouts in every state. */
internal object WearFixtures {
    /** The moment the tests look at the watch: twenty minutes after the preview snapshot was made. */
    val now: Instant = Instant.parse("2026-10-17T10:01:00Z")

    /** The preview as real data. */
    val preview: WidgetSnapshot get() = WidgetSnapshot.preview

    fun view(snapshot: WidgetSnapshot = preview, isPlaceholder: Boolean = false) = WearView(snapshot, isPlaceholder)

    /** The preview with [active] as its running workout. */
    fun withWorkout(active: WorkoutSnapshot?): WidgetSnapshot = preview.copy(active = active)

    /** Set 3 of 4 of the bench press, waiting to be logged, 80 kg x 6, 25 minutes into the workout. */
    fun workout(
        phase: SnapshotPhase = SnapshotPhase.LOGGING,
        isPaused: Boolean = false,
        elapsedWhenPaused: Int = 1500,
        restEndsAt: Instant? = null,
        restTotalSeconds: Int = 120,
        restFrozenRemaining: Int? = null,
        tracking: TrackingKind = TrackingKind.WEIGHT_REPS,
        showsWeight: Boolean = true,
        loggedSets: Int = 7,
        totalSets: Int = 20,
        exerciseName: String = "Bench Press",
        workoutName: String = "Upper A · Push",
    ) = WorkoutSnapshot(
        workoutID = UUID.fromString("00000000-0000-4000-8000-0000000000c1"),
        revision = 12,
        workoutName = workoutName,
        activeStart = now.minusSeconds(1500),
        isPaused = isPaused,
        elapsedWhenPaused = elapsedWhenPaused,
        phase = phase,
        exerciseName = exerciseName,
        exerciseIndex = 0,
        exerciseCount = 6,
        targetExerciseID = UUID.fromString("00000000-0000-4000-8000-0000000000d1"),
        targetSetID = UUID.fromString("00000000-0000-4000-8000-0000000000e1"),
        setLabel = "Set 3 of 4",
        tracking = tracking,
        weightText = "80",
        repsText = "6",
        repsUnit = if (tracking == TrackingKind.DURATION) "sec" else "reps",
        showsWeight = showsWeight,
        restStartedAt = restEndsAt?.minusSeconds(restTotalSeconds.toLong()),
        restEndsAt = restEndsAt,
        restTotalSeconds = restTotalSeconds,
        restFrozenRemaining = restFrozenRemaining,
        volumeText = "4,800",
        loggedSets = loggedSets,
        totalSets = totalSets,
        nextSetText = "Set 3 · 80 kg × 6",
        nextExerciseName = "Incline Dumbbell Press",
    )

    /** A rest that ends [seconds] after [now]. */
    fun resting(seconds: Long = 84, total: Int = 120) =
        workout(phase = SnapshotPhase.RESTING, restEndsAt = now.plusSeconds(seconds), restTotalSeconds = total)
}
