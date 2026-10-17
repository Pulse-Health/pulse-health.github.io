@file:UseSerializers(UuidSerializer::class, InstantSerializer::class)

package health.pulse.strength.core

import java.time.Instant
import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

/** Reference to one set of one workout exercise. */
@Serializable
data class SetRef(val exerciseID: UUID, val setID: UUID)

/** A running (or finished) rest countdown. */
@Serializable
data class RestState(
    val endsAt: Instant,
    val totalSeconds: Int,
    /** Set while the workout is paused: the remaining time is frozen until resume. */
    val frozenRemaining: Double? = null,
)

@Serializable
data class WorkoutSettings(
    /** Start the rest timer when a set is logged. */
    val autoStartRest: Boolean = true,
    /** Sound / vibration / notification when rest ends. */
    val alertWhenRestEnds: Boolean = true,
)

@Serializable
sealed interface UndoPayload {
    /** A removed exercise, restorable at [index]. (Swift `.exercise`.) */
    @Serializable
    @SerialName("exercise")
    data class RemovedExercise(val index: Int, val exercise: WorkoutExercise) : UndoPayload

    /** A deleted set, restorable at [index] of the exercise [exerciseID]. (Swift `.set`.) */
    @Serializable
    @SerialName("set")
    data class DeletedSet(val exerciseID: UUID, val index: Int, val set: LoggedSet) : UndoPayload

    /**
     * An exercise that was replaced by another one (the replacement keeps the entry id): undoing swaps the original back, with its
     * logged sets and its note. (Swift `.replaced`.)
     */
    @Serializable
    @SerialName("replaced")
    data class ReplacedExercise(val exercise: WorkoutExercise) : UndoPayload
}

/** The last destructive edit (removed or replaced exercise / deleted set), restorable until [expiresAt]. */
@Serializable
data class UndoEntry(
    val payload: UndoPayload,
    val title: String,
    val expiresAt: Instant,
)

/**
 * The complete state of one workout in progress. An immutable value: it is persisted and is the single input of the
 * reducer and the presenter.
 */
@Serializable
data class WorkoutState(
    val id: UUID = UUID.randomUUID(),
    val name: String,
    val templateID: UUID? = null,
    /** Template entry ids in their original order; the baseline for "update template?" diffs. */
    val templateBaseline: List<UUID> = emptyList(),
    val exercises: List<WorkoutExercise> = emptyList(),
    val currentIndex: Int = 0,
    val startedAt: Instant,
    val pausedAt: Instant? = null,
    val pausedTotal: Double = 0.0,
    val rest: RestState? = null,
    val lastLogged: SetRef? = null,
    val settings: WorkoutSettings = WorkoutSettings(),
    val undo: UndoEntry? = null,
    /** Latest heart rate (bpm) from a connected source; null when none (the Android app has no heart-rate source yet). */
    val heartRate: Int? = null,
    /** Running totals of the reported heart-rate samples (for the average in the summary). */
    val heartRateSum: Int = 0,
    val heartRateCount: Int = 0,
    /** True while a wearable records the workout (reserved; the phone app never sets it). */
    val usedWatch: Boolean = false,
    /** Incremented by the reducer on every change. */
    val revision: Int = 0,
    val finishedAt: Instant? = null,
) {
    val isPaused: Boolean get() = pausedAt != null

    /** Mean of the reported heart-rate samples, null without samples. */
    val averageHeartRate: Int?
        get() = if (heartRateCount > 0) (heartRateSum.toDouble() / heartRateCount.toDouble()).roundedAwayFromZero().toInt() else null

    /** Index clamped into [exercises]; 0 when empty. */
    val clampedIndex: Int
        get() = if (exercises.isEmpty()) 0 else maxOf(0, minOf(currentIndex, exercises.size - 1))

    val currentExercise: WorkoutExercise?
        get() = if (exercises.isEmpty()) null else exercises[clampedIndex]

    fun exerciseIndex(id: UUID): Int? = exercises.indexOfFirst { it.id == id }.takeIf { it >= 0 }

    /** Whole seconds of active time (pauses excluded). */
    fun elapsedSeconds(now: Instant): Int {
        val reference = pausedAt ?: finishedAt ?: now
        val value = reference.timeIntervalSince(startedAt) - pausedTotal
        return maxOf(0, value.roundedDown().toInt())
    }

    /** Remaining rest in seconds (frozen while paused). null when no rest is active. */
    fun restRemaining(now: Instant): Double? {
        val rest = rest ?: return null
        rest.frozenRemaining?.let { return maxOf(0.0, it) }
        return maxOf(0.0, rest.endsAt.timeIntervalSince(now))
    }
}
