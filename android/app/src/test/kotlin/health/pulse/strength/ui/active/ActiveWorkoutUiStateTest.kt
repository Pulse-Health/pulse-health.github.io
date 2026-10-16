package health.pulse.strength.ui.active

import androidx.compose.runtime.saveable.SaverScope
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.SetRef
import health.pulse.strength.ui.KeypadField
import health.pulse.strength.ui.PickerMode
import java.util.UUID
import org.junit.Test

/** What the screen has open survives a rotation: the saver stores sheets by id and finds the exercise of the form sheet again. */
class ActiveWorkoutUiStateTest {
    private val everything = SaverScope { true }
    private val saver = ActiveWorkoutUiState.saver { id -> ExerciseLibrary.exercise(id) }

    private fun roundTrip(state: ActiveWorkoutUiState): ActiveWorkoutUiState {
        val saved = with(saver) { everything.save(state) }!!
        return saver.restore(saved)!!
    }

    private val exerciseID = UUID.fromString("00000000-0000-0000-0000-000000000001")
    private val setID = UUID.fromString("00000000-0000-0000-0000-000000000002")

    @Test
    fun emptyStateRoundTrips() {
        val restored = roundTrip(ActiveWorkoutUiState())
        assertThat(restored.sheet).isNull()
        assertThat(restored.optionsExerciseID).isNull()
        assertThat(restored.showFinishDialog).isFalse()
        assertThat(restored.showDiscardDialog).isFalse()
        assertThat(restored.showTemplateDialog).isFalse()
    }

    @Test
    fun everySheetRoundTrips() {
        val ref = SetRef(exerciseID, setID)
        val sheets = listOf(
            ActiveSheet.ExerciseList,
            ActiveSheet.Picker(PickerMode.Add),
            ActiveSheet.Picker(PickerMode.Replace(exerciseID)),
            ActiveSheet.Keypad(ref, KeypadField.WEIGHT),
            ActiveSheet.Keypad(ref, KeypadField.REPS),
            ActiveSheet.SetDetail(ref),
            ActiveSheet.RestSettings(exerciseID),
            ActiveSheet.Info(ExerciseLibrary.exercise("bench")!!),
        )
        for (sheet in sheets) {
            val state = ActiveWorkoutUiState().apply { this.sheet = sheet }
            assertThat(roundTrip(state).sheet).isEqualTo(sheet)
        }
    }

    @Test
    fun dialogsAndOptionsRoundTrip() {
        val state = ActiveWorkoutUiState().apply {
            optionsExerciseID = exerciseID
            showFinishDialog = true
            showDiscardDialog = true
            showTemplateDialog = true
        }
        val restored = roundTrip(state)
        assertThat(restored.optionsExerciseID).isEqualTo(exerciseID)
        assertThat(restored.showFinishDialog).isTrue()
        assertThat(restored.showDiscardDialog).isTrue()
        assertThat(restored.showTemplateDialog).isTrue()
    }

    @Test
    fun formSheetOfAnUnknownExerciseIsDroppedInsteadOfCrashing() {
        val state = ActiveWorkoutUiState().apply { sheet = ActiveSheet.Info(ExerciseLibrary.exercise("bench")!!) }
        val saved = with(saver) { everything.save(state) }!!
        val restored = ActiveWorkoutUiState.saver { null }.restore(saved)!!
        assertThat(restored.sheet).isNull()
    }

    @Test
    fun sheetIdsTellApartSheetsForOtherSetsAndExercises() {
        val a = ActiveSheet.Keypad(SetRef(exerciseID, setID), KeypadField.WEIGHT)
        val b = ActiveSheet.Keypad(SetRef(exerciseID, UUID.randomUUID()), KeypadField.WEIGHT)
        // The field is not part of the identity (the keypad switches between weight and reps itself); the set is.
        assertThat(a.id).isEqualTo(ActiveSheet.Keypad(SetRef(exerciseID, setID), KeypadField.REPS).id)
        assertThat(a.id).isNotEqualTo(b.id)
        assertThat(ActiveSheet.Picker(PickerMode.Add).id).isNotEqualTo(ActiveSheet.Picker(PickerMode.Replace(exerciseID)).id)
    }
}
