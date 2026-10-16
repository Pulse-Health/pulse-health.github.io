package health.pulse.strength.ui.sheets

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.Equipment
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.TrackingKind
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The "New Exercise" form builds a custom exercise from its four inputs. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class CreateExerciseSheetTest {
    @get:Rule val rule = createComposeRule()

    private val created = mutableListOf<Exercise>()
    private var dismissed = 0

    private fun open(initialName: String = "") {
        rule.setContent {
            PulseTestTheme {
                CreateExerciseSheet(initialName, onCreate = { created.add(it) }, onDismiss = { dismissed++ })
            }
        }
        rule.waitForIdle()
    }

    @Test
    fun showsTheFormWithTheDesignsCopy() {
        open()
        rule.onNodeWithText("New Exercise").assertExists()
        rule.onNodeWithText("Cancel").assertExists()
        rule.onNodeWithText("Save").assertExists()
        rule.onNodeWithText("Name").assertExists()
        rule.onNodeWithText("e.g. Landmine press").assertExists()
        rule.onNodeWithText("Primary muscle").assertExists()
        rule.onNodeWithText("Equipment").assertExists()
        rule.onNodeWithText("Track").assertExists()
        rule.onNodeWithText("Weight × reps").assertExists()
        rule.onNodeWithText("Custom exercises are saved to your library and can be added to any workout.").assertExists()
    }

    @Test
    fun saveBuildsTheCustomExerciseAndCloses() {
        open()
        rule.onNodeWithContentDescription("Name").performTextInput("Landmine press")
        rule.onNodeWithText("Back").performClick()
        rule.onNodeWithText("Cable").performClick()
        rule.onNodeWithText("Time").performClick()
        rule.onNodeWithText("Save").performClick()
        rule.waitForIdle()
        assertThat(created).hasSize(1)
        val exercise = created.single()
        assertThat(exercise.name).isEqualTo("Landmine press")
        assertThat(exercise.muscle).isEqualTo(MuscleGroup.BACK)
        assertThat(exercise.equipment).isEqualTo(Equipment.CABLE)
        assertThat(exercise.tracking).isEqualTo(TrackingKind.DURATION)
        assertThat(exercise.isCustom).isTrue()
        assertThat(exercise.id).startsWith("custom-")
        assertThat(dismissed).isEqualTo(1)
    }

    @Test
    fun defaultsAreChestBarbellWeightReps() {
        open("Chest fly")
        rule.onNodeWithText("Save").performClick()
        rule.waitForIdle()
        val exercise = created.single()
        assertThat(exercise.name).isEqualTo("Chest fly")
        assertThat(exercise.muscle).isEqualTo(MuscleGroup.CHEST)
        assertThat(exercise.equipment).isEqualTo(Equipment.BARBELL)
        assertThat(exercise.tracking).isEqualTo(TrackingKind.WEIGHT_REPS)
    }

    @Test
    fun anEmptyNameBecomesCustomExercise() {
        open()
        rule.onNodeWithText("Save").performClick()
        rule.waitForIdle()
        assertThat(created.single().name).isEqualTo("Custom exercise")
    }

    @Test
    fun savingTwiceCreatesOneExercise() {
        open("Sled push")
        rule.onNodeWithText("Save").performClick()
        rule.onNodeWithText("Save").performClick()
        rule.waitForIdle()
        assertThat(created).hasSize(1)
    }

    @Test
    fun cancelClosesWithoutCreating() {
        open("Sled push")
        rule.onNodeWithText("Cancel").performClick()
        rule.waitForIdle()
        assertThat(created).isEmpty()
        assertThat(dismissed).isEqualTo(1)
    }
}
