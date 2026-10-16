@file:UseSerializers(UuidSerializer::class, InstantSerializer::class)

package health.pulse.strength.core

import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

/**
 * Everything that can change a workout. [WorkoutReducer] is the only code that applies these.
 * Swift enum cases map to classes of the same name in PascalCase; cases without associated values are objects.
 */
@Serializable
sealed interface WorkoutAction {
    // region Set logging

    /** Tap on a set's check circle: toggles done / not done (starts rest when becoming done). */
    @Serializable @SerialName("toggleSet")
    data class ToggleSet(val exerciseID: UUID, val setID: UUID) : WorkoutAction

    /** Idempotent: marks a pending set done (same side effects as toggle); no-op if already done. */
    @Serializable @SerialName("logSet")
    data class LogSet(val exerciseID: UUID, val setID: UUID) : WorkoutAction

    /** Logs the next pending set (see `WorkoutTargets.nextPending`), moving to its exercise first. */
    @Serializable @SerialName("logNextSet")
    data object LogNextSet : WorkoutAction

    @Serializable @SerialName("setWeight")
    data class SetWeight(val exerciseID: UUID, val setID: UUID, val kg: Double) : WorkoutAction

    @Serializable @SerialName("setReps")
    data class SetReps(val exerciseID: UUID, val setID: UUID, val reps: Int) : WorkoutAction

    /**
     * Adjusts the next pending set: weight by [weightSteps] x Exercise.weightStepKg and
     * reps by [repsSteps] x Exercise.repsStep. Used by the notification actions.
     */
    @Serializable @SerialName("nudgeNextSet")
    data class NudgeNextSet(val weightSteps: Int, val repsSteps: Int) : WorkoutAction

    @Serializable @SerialName("setSetType")
    data class SetSetType(val exerciseID: UUID, val setID: UUID, val type: SetType) : WorkoutAction

    /** Explicit reps-in-reserve value (null clears it). Used by the set sheet. */
    @Serializable @SerialName("setRIR")
    data class SetRIR(val exerciseID: UUID, val setID: UUID, val rir: Int?) : WorkoutAction

    /** Rest-dock chips: applies to `lastLogged`; selecting the already selected value clears it. */
    @Serializable @SerialName("toggleLastSetRIR")
    data class ToggleLastSetRIR(val value: Int) : WorkoutAction

    @Serializable @SerialName("addSet")
    data class AddSet(val exerciseID: UUID) : WorkoutAction

    @Serializable @SerialName("deleteSet")
    data class DeleteSet(val exerciseID: UUID, val setID: UUID) : WorkoutAction

    @Serializable @SerialName("setNote")
    data class SetNote(val exerciseID: UUID, val note: String) : WorkoutAction

    // endregion

    // region Navigation

    @Serializable @SerialName("goTo")
    data class GoTo(val index: Int) : WorkoutAction

    @Serializable @SerialName("nextExercise")
    data object NextExercise : WorkoutAction

    @Serializable @SerialName("previousExercise")
    data object PreviousExercise : WorkoutAction

    // endregion

    // region Exercise list editing

    @Serializable @SerialName("addExercises")
    data class AddExercises(val exercises: List<Exercise>) : WorkoutAction

    @Serializable @SerialName("removeExercise")
    data class RemoveExercise(val exerciseID: UUID) : WorkoutAction

    @Serializable @SerialName("moveExercise")
    data class MoveExercise(val from: Int, val to: Int) : WorkoutAction

    @Serializable @SerialName("moveExerciseBy")
    data class MoveExerciseBy(val exerciseID: UUID, val delta: Int) : WorkoutAction

    @Serializable @SerialName("replaceExercise")
    data class ReplaceExercise(val exerciseID: UUID, val with: Exercise) : WorkoutAction

    /** Joins the exercise with the next one in a superset, or removes it from its superset. */
    @Serializable @SerialName("toggleSuperset")
    data class ToggleSuperset(val exerciseID: UUID) : WorkoutAction

    /** Per-exercise rest seconds; 0 turns the timer off for this exercise. */
    @Serializable @SerialName("setRest")
    data class SetRest(val exerciseID: UUID, val seconds: Int) : WorkoutAction

    // endregion

    // region Rest timer

    @Serializable @SerialName("adjustRest")
    data class AdjustRest(val seconds: Int) : WorkoutAction

    @Serializable @SerialName("skipRest")
    data object SkipRest : WorkoutAction

    @Serializable @SerialName("setAutoStartRest")
    data class SetAutoStartRest(val value: Boolean) : WorkoutAction

    @Serializable @SerialName("setAlertWhenRestEnds")
    data class SetAlertWhenRestEnds(val value: Boolean) : WorkoutAction

    // endregion

    // region Lifecycle

    @Serializable @SerialName("pause")
    data object Pause : WorkoutAction

    @Serializable @SerialName("resume")
    data object Resume : WorkoutAction

    /** Restores the last removed exercise / deleted set if its undo window is still open. */
    @Serializable @SerialName("undo")
    data object Undo : WorkoutAction

    @Serializable @SerialName("updateHeartRate")
    data class UpdateHeartRate(val bpm: Int?) : WorkoutAction

    @Serializable @SerialName("setUsedWatch")
    data class SetUsedWatch(val value: Boolean) : WorkoutAction

    @Serializable @SerialName("rename")
    data class Rename(val name: String) : WorkoutAction

    // endregion
}

/** Who initiated an action (used by side effects to avoid echoing it back). */
@Serializable
enum class ActionOrigin {
    @SerialName("phone") PHONE,
    @SerialName("watch") WATCH,
    @SerialName("liveActivity") LIVE_ACTIVITY,
    @SerialName("system") SYSTEM,
}
