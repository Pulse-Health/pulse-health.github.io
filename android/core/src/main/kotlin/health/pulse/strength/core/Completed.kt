@file:UseSerializers(UuidSerializer::class, InstantSerializer::class)

package health.pulse.strength.core

import java.time.Instant
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

// region Finished workouts

@Serializable
data class CompletedSet(
    val type: SetType,
    val weightKg: Double,
    val reps: Int,
    val rir: Int? = null,
)

@Serializable
data class CompletedExercise(
    val id: UUID = UUID.randomUUID(),
    val exerciseID: String,
    val name: String,
    val muscle: MuscleGroup,
    val mediaKey: String?,
    val tracking: TrackingKind,
    /** Only logged sets. */
    val sets: List<CompletedSet>,
    val isPersonalRecord: Boolean,
    /** Best estimated 1RM of the logged non-warm-up sets (0 when not applicable). */
    val bestE1RM: Double,
)

@Serializable
data class PersonalRecord(
    val exerciseID: String,
    val exerciseName: String,
    val weightKg: Double,
    val reps: Int,
    val estimated1RM: Double,
    /** The best estimated 1RM before this workout. */
    val previousBest: Double,
) {
    val id: String get() = exerciseID
}

@Serializable
data class MuscleSets(
    val muscle: MuscleGroup,
    val sets: Int,
) {
    val id: String get() = muscle.rawValue
}

/** The saved result of a workout (history, summary screen, Health export). */
@Serializable
data class CompletedWorkout(
    val id: UUID,
    val name: String,
    val templateID: UUID?,
    val startedAt: Instant,
    val finishedAt: Instant,
    val durationSeconds: Int,
    /** Warm-up sets excluded; weight-tracking exercises only. */
    val volumeKg: Double,
    val loggedSets: Int,
    val averageHeartRate: Int?,
    /** Mean of recorded RIR values; null when none recorded. */
    val averageRIR: Double?,
    val exercises: List<CompletedExercise>,
    val personalRecords: List<PersonalRecord>,
    val muscleSets: List<MuscleSets>,
)

// endregion

// region Personal bests and per-exercise history

@Serializable
data class PersonalBest(
    val exerciseID: String,
    val estimated1RM: Double,
    val weightKg: Double,
    val reps: Int,
    val date: Instant,
)

@Serializable
data class E1RMPoint(
    val date: Instant,
    val value: Double,
) {
    val id: Instant get() = date
}

data class ExerciseSession(
    /** The CompletedWorkout id. */
    val id: UUID,
    val date: Instant,
    val workoutName: String,
    val sets: List<CompletedSet>,
    val isPersonalRecord: Boolean,
)

data class ExerciseRecordRow(
    val id: String,
    val label: String,
    val value: String,
    val date: Instant? = null,
)

/** Data behind the exercise-detail screen. Built by `StrengthData.history(exerciseID, now)`. */
data class ExerciseHistory(
    val exerciseID: String,
    /** Newest first. */
    val sessions: List<ExerciseSession>,
    /** Oldest first, one point per session (best non-warm-up e1RM). */
    val e1RMSeries: List<E1RMPoint>,
    val bestE1RM: Double,
    /** "85 kg × 5" */
    val bestSetText: String? = null,
    val bestSetDate: Instant? = null,
    val volumeLast30Days: Double,
    val sessionsLast30Days: Int,
    val records: List<ExerciseRecordRow>,
)

// endregion
