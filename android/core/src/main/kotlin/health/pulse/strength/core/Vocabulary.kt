package health.pulse.strength.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Port of PulseStrengthCore `MuscleGroup`; the serial names are the Swift raw values so JSON is identical. */
@Serializable
enum class MuscleGroup(val title: String) {
    @SerialName("Chest") CHEST("Chest"),
    @SerialName("Back") BACK("Back"),
    @SerialName("Shoulders") SHOULDERS("Shoulders"),
    @SerialName("Arms") ARMS("Arms"),
    @SerialName("Legs") LEGS("Legs"),
    @SerialName("Core") CORE("Core"),
}

/** Port of `TrackingKind`. */
@Serializable
enum class TrackingKind {
    /** Weight (kg) x reps. */
    @SerialName("weightReps") WEIGHT_REPS,
    /** Reps only (bodyweight). */
    @SerialName("repsOnly") REPS_ONLY,
    /** Duration; the reps field holds seconds. */
    @SerialName("duration") DURATION,
}

/** Port of `SnapshotPhase`. */
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
