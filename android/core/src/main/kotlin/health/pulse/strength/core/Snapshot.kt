@file:UseSerializers(UuidSerializer::class, InstantSerializer::class)

package health.pulse.strength.core

import health.pulse.strength.core.widgets.CoachTipBrief
import health.pulse.strength.core.widgets.FinishBrief
import health.pulse.strength.core.widgets.PRMoment
import health.pulse.strength.core.widgets.PlateBrief
import health.pulse.strength.core.widgets.SupersetBrief
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

@Serializable
enum class SnapshotPhase {
    /** A set is waiting to be logged. */
    @SerialName("logging") LOGGING,

    /** Rest countdown is running. */
    @SerialName("resting") RESTING,

    /** Rest countdown reached zero and has not been dismissed. */
    @SerialName("restOver") REST_OVER,

    /** Every set of every exercise is logged. */
    @SerialName("complete") COMPLETE,
}

/**
 * A small, flat summary of the workout for surfaces that cannot render the full state: the ongoing notification
 * (the Android counterpart of the Live Activity). Built by `SnapshotBuilder.make(state, now)`.
 */
@Serializable
data class WorkoutSnapshot(
    val workoutID: UUID,
    val revision: Int,
    val workoutName: String,

    /** `startedAt + pausedTotal`: elapsed active time is `now - activeStart` while running. */
    val activeStart: Instant,
    val isPaused: Boolean,
    /** Elapsed seconds, valid while paused (frozen). */
    val elapsedWhenPaused: Int,

    val phase: SnapshotPhase,
    val exerciseName: String,
    /** 0-based position of the current exercise. */
    val exerciseIndex: Int,
    val exerciseCount: Int,

    /** The set a "Log set" button logs (the next pending set); null when `phase == COMPLETE`. */
    val targetExerciseID: UUID? = null,
    val targetSetID: UUID? = null,
    /** "Set 4 of 5" or "Warm-up 1 of 2" style label for the target set. */
    val setLabel: String,
    val tracking: TrackingKind,
    val weightText: String,
    val repsText: String,
    /** "reps" or "sec". */
    val repsUnit: String,
    /** True when the target exercise logs a weight (weightReps). */
    val showsWeight: Boolean,

    /** Rest countdown: `restStartedAt ... restEndsAt`. */
    val restStartedAt: Instant? = null,
    val restEndsAt: Instant? = null,
    val restTotalSeconds: Int,
    /** Seconds left while the workout is paused (frozen rest). */
    val restFrozenRemaining: Int? = null,

    val heartRate: Int? = null,
    val volumeText: String,
    val loggedSets: Int,
    val totalSets: Int,
    /** "Set 4 · 82.5 kg × 6" */
    val nextSetText: String,
    val nextExerciseName: String? = null,

    /** Sets of the shown exercise that are logged / in total (the "set dots"). */
    val exerciseDoneSets: Int? = null,
    val exerciseSetCount: Int? = null,
    /** A personal record that was just logged; cleared by an update at its `expiresAt`. */
    val moment: PRMoment? = null,
    /** The running superset; null when the shown exercise is not in one. */
    val superset: SupersetBrief? = null,
    /** Plates for the target set; null unless the target is a barbell weight exercise. */
    val plates: PlateBrief? = null,
    /** A one-tap suggestion shown while resting. */
    val coachTip: CoachTipBrief? = null,
    /** Set on the final content of a finished workout. */
    val finish: FinishBrief? = null,
)
