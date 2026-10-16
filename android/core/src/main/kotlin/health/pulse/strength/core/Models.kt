@file:UseSerializers(UuidSerializer::class, InstantSerializer::class)

package health.pulse.strength.core

import java.time.Instant
import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

// region Vocabulary

@Serializable
enum class MuscleGroup(val rawValue: String) {
    @SerialName("Chest") CHEST("Chest"),
    @SerialName("Back") BACK("Back"),
    @SerialName("Shoulders") SHOULDERS("Shoulders"),
    @SerialName("Arms") ARMS("Arms"),
    @SerialName("Legs") LEGS("Legs"),
    @SerialName("Core") CORE("Core");

    val id: String get() = rawValue
    val title: String get() = rawValue
}

@Serializable
enum class Equipment(val rawValue: String) {
    @SerialName("Barbell") BARBELL("Barbell"),
    @SerialName("Dumbbell") DUMBBELL("Dumbbell"),
    @SerialName("Cable") CABLE("Cable"),
    @SerialName("Machine") MACHINE("Machine"),
    @SerialName("Bodyweight") BODYWEIGHT("Bodyweight"),
    @SerialName("Other") OTHER("Other");

    val id: String get() = rawValue
    val title: String get() = rawValue
}

@Serializable
enum class TrackingKind {
    /** Weight (kg) x reps. */
    @SerialName("weightReps") WEIGHT_REPS,

    /** Reps only (bodyweight). The weight column shows "BW". */
    @SerialName("repsOnly") REPS_ONLY,

    /** Duration. `LoggedSet.reps` holds seconds. */
    @SerialName("duration") DURATION;

    val title: String
        get() = when (this) {
            WEIGHT_REPS -> "Weight × reps"
            REPS_ONLY -> "Reps"
            DURATION -> "Time"
        }
}

@Serializable
enum class SetType {
    @SerialName("normal") NORMAL,
    @SerialName("warmup") WARMUP,
    @SerialName("drop") DROP,
    @SerialName("failure") FAILURE;

    val title: String
        get() = when (this) {
            NORMAL -> "Normal"
            WARMUP -> "Warm-up"
            DROP -> "Drop set"
            FAILURE -> "To failure"
        }

    /** One-letter badge used in set rows ("#" is replaced by the working-set number). */
    val badge: String
        get() = when (this) {
            NORMAL -> "#"
            WARMUP -> "W"
            DROP -> "D"
            FAILURE -> "F"
        }

    /** Warm-up sets are left out of volume, estimated 1RM and personal records. */
    val countsTowardVolume: Boolean get() = this != WARMUP
}

// endregion

// region Exercise library entry

@Serializable
data class PreviousSet(val weightKg: Double, val reps: Int)

@Serializable
data class ExerciseDefaults(val sets: Int, val weightKg: Double, val reps: Int, val restSeconds: Int)

@Serializable
data class Exercise(
    /** Stable id. Built-in exercises use short slugs ("bench"); custom ones use "custom-<uuid>". */
    val id: String,
    val name: String,
    val muscle: MuscleGroup,
    /** Free text shown under the name, e.g. "Shoulders · Triceps". */
    val secondary: String = "",
    val equipment: Equipment,
    val tracking: TrackingKind = TrackingKind.WEIGHT_REPS,
    /** Base name of the two form-demo frames in the app's assets: "<key>-a" and "<key>-b" (.jpg). */
    val mediaKey: String? = null,
    /** Best estimated 1RM from earlier sessions (kg). 0 means "no history": no PR can be flagged. */
    val previousBestE1RM: Double = 0.0,
    /** Last session's sets, aligned by set index (used for the PREVIOUS column). */
    val previousSets: List<PreviousSet> = emptyList(),
    val defaults: ExerciseDefaults,
    val cues: List<String> = emptyList(),
    /** Empty-bar weight used by the plate calculator (barbell exercises only). */
    val barKg: Double = 20.0,
    val isCustom: Boolean = false,
) {
    /** Increment used by the - / + steppers (keypad, notification actions). */
    val weightStepKg: Double
        get() = when (equipment) {
            Equipment.DUMBBELL -> 2.0
            Equipment.BARBELL, Equipment.CABLE, Equipment.MACHINE -> 2.5
            Equipment.BODYWEIGHT, Equipment.OTHER -> 1.0
        }

    /** Reps stepper increment; durations move in 5 s steps. */
    val repsStep: Int get() = if (tracking == TrackingKind.DURATION) 5 else 1

    val tracksWeight: Boolean get() = tracking == TrackingKind.WEIGHT_REPS
    val supportsPlates: Boolean get() = equipment == Equipment.BARBELL && tracking == TrackingKind.WEIGHT_REPS

    companion object {
        /** A user-created exercise with sensible defaults (3 sets, 90 s rest). */
        fun custom(
            name: String,
            muscle: MuscleGroup,
            equipment: Equipment,
            tracking: TrackingKind,
            id: String = "custom-" + UUID.randomUUID().toString().lowercase(),
        ): Exercise {
            val trimmed = name.trim()
            return Exercise(
                id = id,
                name = trimmed.ifEmpty { "Custom exercise" },
                muscle = muscle,
                secondary = "Custom",
                equipment = equipment,
                tracking = tracking,
                mediaKey = null,
                previousBestE1RM = 0.0,
                previousSets = emptyList(),
                defaults = ExerciseDefaults(
                    sets = 3,
                    weightKg = if (tracking == TrackingKind.WEIGHT_REPS) 20.0 else 0.0,
                    reps = if (tracking == TrackingKind.DURATION) 45 else 10,
                    restSeconds = 90,
                ),
                cues = listOf("Your own exercise. Add a note to remember how you like to perform it."),
                barKg = 20.0,
                isCustom = true,
            )
        }
    }
}

// endregion

// region Logged workout content

@Serializable
data class LoggedSet(
    val id: UUID = UUID.randomUUID(),
    val type: SetType = SetType.NORMAL,
    val weightKg: Double,
    /** Reps, or seconds when the exercise tracks duration. */
    val reps: Int,
    val isDone: Boolean = false,
    /** Reps in reserve, 0...4 (4 means "4+"). null = not recorded. */
    val rir: Int? = null,
)

@Serializable
data class WorkoutExercise(
    /** Unique per workout entry (the same Exercise may appear twice). */
    val id: UUID = UUID.randomUUID(),
    /** Denormalised definition so a state value is self-describing. */
    val exercise: Exercise,
    val sets: List<LoggedSet>,
    val restSeconds: Int,
    /** "A", "B", ... Exercises sharing a group alternate sets. null = not in a superset. */
    val supersetGroup: String? = null,
    val note: String = "",
    /** The template entry this was created from; null for exercises added during the workout. */
    val templateEntryID: UUID? = null,
) {
    val doneCount: Int get() = sets.count { it.isDone }
    val isComplete: Boolean get() = sets.isNotEmpty() && doneCount == sets.size
}

// endregion

// region Templates

@Serializable
data class PlannedSet(
    val type: SetType = SetType.NORMAL,
    val weightKg: Double,
    val reps: Int,
)

@Serializable
data class TemplateEntry(
    val id: UUID = UUID.randomUUID(),
    val exercise: Exercise,
    val plannedSets: List<PlannedSet>,
    val restSeconds: Int,
    val supersetGroup: String? = null,
)

@Serializable
data class WorkoutTemplate(
    val id: UUID = UUID.randomUUID(),
    val name: String,
    val entries: List<TemplateEntry>,
    val lastPerformed: Instant? = null,
) {
    /**
     * Rough duration: working time per set (45 s) plus rest, rounded to 5 minutes.
     *
     * The rest after a set follows the reducer: the exercise's rest, 40 % of it (at least 30 s) after a warm-up, and none at all
     * when the exercise's rest is 0 (timer off), for every set type.
     *
     * A rest outside `0..WorkoutReducer.maximumRestSeconds` (only possible for a template that did not come through the
     * reducer, such as a damaged file) counts as the nearest bound, so the arithmetic cannot overflow.
     */
    val estimatedMinutes: Int
        get() {
            var seconds = 0
            for (entry in entries) {
                val rest = maxOf(0, minOf(entry.restSeconds, WorkoutReducer.maximumRestSeconds))
                for (set in entry.plannedSets) {
                    val restAfterSet = if (rest == 0) 0 else if (set.type == SetType.WARMUP) maxOf(30, rest * 2 / 5) else rest
                    seconds += 45 + restAfterSet
                }
            }
            val minutes = (seconds.toDouble() / 60.0 / 5.0).roundedAwayFromZero().toInt() * 5
            return maxOf(5, minutes)
        }
}

// endregion
