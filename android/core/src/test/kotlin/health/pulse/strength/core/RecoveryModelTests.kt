package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import java.time.Instant
import java.util.UUID
import org.junit.Test

class RecoveryModelTests {
    private val now: Instant = Instant.parse("2026-03-10T12:00:00Z")

    private fun workout(hoursAgo: Double, vararg muscles: Pair<MuscleGroup, Int>): CompletedWorkout {
        val finished = now.addingTimeInterval(-hoursAgo * 3600)
        return CompletedWorkout(
            id = UUID.randomUUID(), name = "W", templateID = null,
            startedAt = finished.addingTimeInterval(-3600.0), finishedAt = finished, durationSeconds = 3600,
            volumeKg = 0.0, loggedSets = muscles.sumOf { it.second }, averageHeartRate = null, averageRIR = null,
            exercises = emptyList(), personalRecords = emptyList(),
            muscleSets = muscles.map { MuscleSets(it.first, it.second) },
        )
    }

    private fun percent(muscle: MuscleGroup, vararg workouts: CompletedWorkout) = RecoveryModel.compute(workouts.toList(), muscle, now)

    @Test
    fun aMuscleThatWasNeverTrainedIsFullyRecovered() {
        assertThat(percent(MuscleGroup.CHEST)).isEqualTo(100)
        assertThat(percent(MuscleGroup.CHEST, workout(1.0, MuscleGroup.LEGS to 10))).isEqualTo(100)
    }

    @Test
    fun recoveryGrowsLinearlyFromZeroToTheRecoveryTime() {
        assertThat(percent(MuscleGroup.CHEST, workout(0.0, MuscleGroup.CHEST to 6))).isEqualTo(0)
        assertThat(percent(MuscleGroup.CHEST, workout(12.0, MuscleGroup.CHEST to 6))).isEqualTo(25)
        assertThat(percent(MuscleGroup.CHEST, workout(24.0, MuscleGroup.CHEST to 6))).isEqualTo(50)
        assertThat(percent(MuscleGroup.CHEST, workout(48.0, MuscleGroup.CHEST to 6))).isEqualTo(100)
        assertThat(percent(MuscleGroup.CHEST, workout(500.0, MuscleGroup.CHEST to 6))).isEqualTo(100)
    }

    @Test
    fun moreSetsNeedMoreTimeUpToThreeDays() {
        assertThat(RecoveryModel.recoveryHours(3)).isEqualTo(48.0)
        assertThat(RecoveryModel.recoveryHours(6)).isEqualTo(48.0)
        assertThat(RecoveryModel.recoveryHours(9)).isEqualTo(60.0)
        assertThat(RecoveryModel.recoveryHours(12)).isEqualTo(72.0)
        assertThat(RecoveryModel.recoveryHours(40)).isEqualTo(72.0)
        assertThat(percent(MuscleGroup.LEGS, workout(36.0, MuscleGroup.LEGS to 12))).isEqualTo(50)
    }

    @Test
    fun onlyTheMostRecentWorkoutThatTrainedTheMuscleCounts() {
        val old = workout(100.0, MuscleGroup.BACK to 20)
        val recent = workout(24.0, MuscleGroup.BACK to 6)
        val other = workout(1.0, MuscleGroup.ARMS to 6)
        assertThat(percent(MuscleGroup.BACK, old, recent, other)).isEqualTo(50)
        assertThat(percent(MuscleGroup.BACK, other, recent, old)).isEqualTo(50)
    }

    @Test
    fun aFutureFinishTimeNeverGoesBelowZero() {
        assertThat(percent(MuscleGroup.CORE, workout(-5.0, MuscleGroup.CORE to 6))).isEqualTo(0)
    }

    @Test
    fun theModelFollowsTheHistoryAndTheClockAndCachesPerMinute() {
        var history = listOf(workout(24.0, MuscleGroup.CHEST to 6))
        var clockNow = now
        val model = RecoveryModel({ history }, { clockNow })
        assertThat(model.percent(MuscleGroup.CHEST)).isEqualTo(50)
        assertThat(model.provider(MuscleGroup.CHEST)).isEqualTo(50)

        clockNow = now.plusSeconds(12 * 3600L)
        assertThat(model.percent(MuscleGroup.CHEST)).isEqualTo(75)

        history = history + workout(0.0, MuscleGroup.CHEST to 6).copy(finishedAt = clockNow)
        assertThat(model.percent(MuscleGroup.CHEST)).isEqualTo(0)
        assertThat(model.percent(MuscleGroup.LEGS)).isEqualTo(100)
    }

    @Test
    fun aRealInstallShowsNoInventedPreviousResults() {
        val clean = StrengthData(usesLibraryHistory = false)
        val bench = clean.exercise("bench")!!
        assertThat(bench.previousBestE1RM).isEqualTo(0.0)
        assertThat(bench.previousSets).isEmpty()
        assertThat(clean.exercises().all { it.previousBestE1RM == 0.0 && it.previousSets.isEmpty() }).isTrue()

        // The demo behaviour (the design's numbers) is unchanged by default.
        assertThat(StrengthData().exercise("bench")!!.previousBestE1RM).isEqualTo(99.0)
    }

    @Test
    fun aRealInstallStillLearnsFromItsOwnHistory() {
        val workout = CompletedWorkout(
            id = UUID.randomUUID(), name = "Push", templateID = null, startedAt = now.minusSeconds(4000), finishedAt = now.minusSeconds(400),
            durationSeconds = 3600, volumeKg = 480.0, loggedSets = 1, averageHeartRate = null, averageRIR = null,
            exercises = listOf(
                CompletedExercise(
                    exerciseID = "bench", name = "Barbell bench press", muscle = MuscleGroup.CHEST, mediaKey = "bench",
                    tracking = TrackingKind.WEIGHT_REPS, sets = listOf(CompletedSet(SetType.NORMAL, 60.0, 8)),
                    isPersonalRecord = false, bestE1RM = 76.0,
                ),
            ),
            personalRecords = emptyList(), muscleSets = listOf(MuscleSets(MuscleGroup.CHEST, 1)),
        )
        val data = StrengthData(usesLibraryHistory = false).recording(workout, null)
        val bench = data.exercise("bench")!!
        assertThat(bench.previousBestE1RM).isEqualTo(76.0)
        assertThat(bench.previousSets).containsExactly(PreviousSet(60.0, 8))
    }

    @Test
    fun theStoreAndModelPassTheOptionThrough() {
        val store = StrengthStore(persistence = null, seedDemoData = false, usesLibraryHistory = false)
        assertThat(store.exercise("squat")!!.previousSets).isEmpty()
        assertThat(store.exercises.first { it.id == "bench" }.previousBestE1RM).isEqualTo(0.0)
    }
}
