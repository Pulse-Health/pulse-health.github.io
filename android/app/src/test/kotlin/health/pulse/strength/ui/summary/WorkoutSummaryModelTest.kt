package health.pulse.strength.ui.summary

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.CompletedExercise
import health.pulse.strength.core.CompletedSet
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.PersonalRecord
import health.pulse.strength.core.SetType
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.ui.detail.ResultFixtures
import java.util.UUID
import org.junit.Test

/** The figures and spoken texts of the workout summary: pure Kotlin, no UI. */
class WorkoutSummaryModelTest {
    private val workout = ResultFixtures.demoRecordWorkout()

    private fun record(weight: Double, reps: Int, e1rm: Double, previous: Double) =
        PersonalRecord("bench", "Barbell bench press", weight, reps, e1rm, previous)

    // region Tiles

    @Test
    fun tilesListDurationVolumeSetsHeartRateAndRir() {
        val tiles = summaryTiles(workout)
        assertThat(tiles.map { it.id }).containsExactly("duration", "volume", "sets", "heartRate", "rir").inOrder()
        assertThat(tiles.map { it.title }).containsExactly("Duration", "Volume", "Sets", "Avg Heart Rate", "Avg RIR").inOrder()
        assertThat(tiles.map { it.value }).containsExactly("56m", "5,064 kg", "20", "131 bpm", "2.0").inOrder()
        assertThat(tiles.map { it.spoken })
            .containsExactly("56 minutes", "5,064 kilograms", "20", "131 beats per minute", "2.0 reps in reserve")
            .inOrder()
    }

    @Test
    fun heartRateAndRirTilesAppearOnlyWhenRecorded() {
        assertThat(summaryTiles(workout.copy(averageHeartRate = null)).map { it.id }).doesNotContain("heartRate")
        assertThat(summaryTiles(workout.copy(averageHeartRate = 0)).map { it.id }).doesNotContain("heartRate")
        assertThat(summaryTiles(workout.copy(averageRIR = null)).map { it.id }).doesNotContain("rir")
        assertThat(summaryTiles(workout.copy(averageHeartRate = null, averageRIR = null)).map { it.id })
            .containsExactly("duration", "volume", "sets").inOrder()
    }

    @Test
    fun volumeIsGroupedWithCommas() {
        assertThat(summaryTiles(workout.copy(volumeKg = 18_432.5)).first { it.id == "volume" }.value).isEqualTo("18,433 kg")
        assertThat(summaryTiles(workout.copy(volumeKg = 0.0)).first { it.id == "volume" }.value).isEqualTo("0 kg")
    }

    // endregion

    // region Records

    @Test
    fun gainIsTheDifferenceOfTheWholeKilograms() {
        assertThat(record(85.0, 5, 99.17, 95.0).gainKg()).isEqualTo(4.0)
        assertThat(record(100.0, 1, 100.0, 99.8).gainKg()).isNull()
    }

    @Test
    fun noGainWithoutAPreviousBest() {
        assertThat(record(85.0, 5, 99.17, 0.0).gainKg()).isNull()
    }

    @Test
    fun recordDetailAndSpokenText() {
        val record = record(85.0, 5, 99.17, 95.0)
        assertThat(record.detailText()).isEqualTo("85 kg × 5 · est. 1RM 99 kg")
        assertThat(record.spokenText()).isEqualTo(
            "New personal record, Barbell bench press, 85 kilograms for 5 reps, estimated one-rep max 99 kilograms, up 4 kilograms",
        )
    }

    @Test
    fun spokenRecordIsSingularForOneRepAndLeavesOutAMissingGain() {
        assertThat(record(100.0, 1, 100.0, 99.8).spokenText()).isEqualTo(
            "New personal record, Barbell bench press, 100 kilograms for 1 rep, estimated one-rep max 100 kilograms",
        )
    }

    // endregion

    // region Exercises

    @Test
    fun spokenExerciseNamesTheSetsAndTheRecord() {
        val exercise = CompletedExercise(
            id = UUID.randomUUID(), exerciseID = "bench", name = "Barbell bench press", muscle = MuscleGroup.CHEST, mediaKey = "bench",
            tracking = TrackingKind.WEIGHT_REPS,
            sets = listOf(CompletedSet(SetType.WARMUP, 50.0, 8), CompletedSet(SetType.NORMAL, 80.0, 6)),
            isPersonalRecord = true, bestE1RM = 96.0,
        )
        assertThat(exercise.spokenText()).isEqualTo("Barbell bench press, 2 sets, personal record. W 50×8, 80×6")
        assertThat(exercise.copy(isPersonalRecord = false, sets = exercise.sets.take(1)).spokenText())
            .isEqualTo("Barbell bench press, 1 set. W 50×8")
    }

    // endregion
}
