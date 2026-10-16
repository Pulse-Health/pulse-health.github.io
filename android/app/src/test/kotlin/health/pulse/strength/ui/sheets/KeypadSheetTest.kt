package health.pulse.strength.ui.sheets

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.SetType
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.ui.KeypadField
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The keypad sheet in its window: keys, steppers, "Use last", field switching and logging dispatch to the real controller. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class KeypadSheetTest {
    @get:Rule val rule = createComposeRule()

    private val fixture = SheetFixture()
    private var dismissed = 0

    /** Bench press set 3 (first working set, 82.5 kg x 6, barbell). */
    private val benchSet3 = fixture.ref(0, 2)

    private fun open(ref: health.pulse.strength.core.SetRef = benchSet3, field: KeypadField = KeypadField.WEIGHT) {
        rule.setContent {
            PulseTestTheme { KeypadSheet(fixture.controller, ref, field, onDismiss = { dismissed++ }) }
        }
        rule.waitForIdle()
    }

    private fun key(name: String) = rule.onNodeWithContentDescription(name).performClick()

    private fun benchSet() = fixture.set(0, 2)

    private fun SemanticsNodeInteraction.assertHasState(state: String) =
        assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, state))

    @Test
    fun showsTitleAndValueCards() {
        open()
        rule.onNodeWithText("Set 3 · Barbell bench press").assertExists()
        rule.onNodeWithText("82.5").assertExists()
        rule.onNodeWithContentDescription("Weight").assertHasState("82.5 kilograms")
        rule.onNodeWithContentDescription("Reps").assertHasState("6 reps")
        rule.onNodeWithText("Next: Reps").assertExists()
        rule.onNodeWithContentDescription("20 kilogram bar. 25 + 5 + 1.25 per side").assertExists()
    }

    @Test
    fun firstDigitReplacesWeightAndEveryKeyIsDispatched() {
        open()
        key("9")
        assertThat(benchSet().weightKg).isEqualTo(9.0)
        key("0")
        assertThat(benchSet().weightKg).isEqualTo(90.0)
        key("Decimal point")
        key("5")
        assertThat(benchSet().weightKg).isEqualTo(90.5)
        // A third decimal and a second decimal point are ignored.
        key("7")
        key("1")
        assertThat(benchSet().weightKg).isEqualTo(90.57)
        key("1")
        assertThat(benchSet().weightKg).isEqualTo(90.57)
        key("Delete")
        assertThat(benchSet().weightKg).isEqualTo(90.5)
        rule.onNodeWithText("90.5").assertExists()
        key("Delete")
        key("Delete")
        assertThat(benchSet().weightKg).isEqualTo(90.0)
        rule.onNodeWithText("90").assertExists()
    }

    @Test
    fun nextSwitchesToRepsAndLogSetLogsAndDismisses() {
        open()
        key("1"); key("0"); key("0")
        assertThat(benchSet().weightKg).isEqualTo(100.0)
        rule.onNodeWithText("Next: Reps").performClick()
        // Reps field: the decimal key is off, the first digit replaces the 6.
        rule.onNodeWithContentDescription("Decimal point").assertIsNotEnabled()
        key("8")
        assertThat(benchSet().reps).isEqualTo(8)
        key("5")
        assertThat(benchSet().reps).isEqualTo(85)
        key("9"); key("9")
        // 859 is fine, 8599 would be above 999 and is ignored.
        assertThat(benchSet().reps).isEqualTo(859)
        assertThat(benchSet().isDone).isFalse()
        rule.onNodeWithText("Log Set").performClick()
        rule.waitForIdle()
        assertThat(benchSet().isDone).isTrue()
        assertThat(dismissed).isEqualTo(1)
    }

    @Test
    fun steppersUseTheExercisesStep() {
        open()
        rule.onNodeWithContentDescription("Increase weight").performClick()
        assertThat(benchSet().weightKg).isEqualTo(85.0)
        rule.onNodeWithContentDescription("Decrease weight").performClick()
        rule.onNodeWithContentDescription("Decrease weight").performClick()
        assertThat(benchSet().weightKg).isEqualTo(80.0)
        // Reps step is 1.
        rule.onNodeWithContentDescription("Reps").performClick()
        rule.onNodeWithContentDescription("Increase reps").performClick()
        assertThat(benchSet().reps).isEqualTo(7)
        rule.onNodeWithContentDescription("Decrease reps").performClick()
        rule.onNodeWithContentDescription("Decrease reps").performClick()
        assertThat(benchSet().reps).isEqualTo(5)
    }

    @Test
    fun useLastTakesTheSameSetOfTheLastSession() {
        open()
        // Bench last session: 50x8, 70x5, 80x6, 80x6, 80x5 -> set 3 is 80 kg x 6.
        rule.onNodeWithText("Use last: 80 kg").performClick()
        assertThat(benchSet().weightKg).isEqualTo(80.0)
        rule.onNodeWithContentDescription("Reps").performClick()
        rule.onNodeWithText("Use last: 6 reps").assertExists()
    }

    @Test
    fun useLastIsOffWithoutHistory() {
        // The machine chest press has no previous session; add it to a fresh workout.
        val custom = health.pulse.strength.core.ExerciseLibrary.exercise("cpress")!!
        fixture.controller.send(WorkoutAction.AddExercises(listOf(custom)))
        val index = fixture.exercises.lastIndex
        open(fixture.ref(index, 0))
        rule.onNodeWithText("No previous session · ±2.5").assertExists().assertIsNotEnabled()
        // No plates for a machine.
        rule.onNodeWithContentDescription("20 kilogram bar", substring = true).assertDoesNotExist()
    }

    @Test
    fun bodyweightExerciseEditsRepsOnly() {
        val pushup = health.pulse.strength.core.ExerciseLibrary.exercise("pushup")!!
        fixture.controller.send(WorkoutAction.AddExercises(listOf(pushup)))
        val index = fixture.exercises.lastIndex
        // Even when asked for the weight, a bodyweight exercise starts on reps.
        open(fixture.ref(index, 0), KeypadField.WEIGHT)
        rule.onNodeWithText("BW").assertExists()
        rule.onNodeWithContentDescription("Weight").assertIsNotEnabled()
        rule.onNodeWithText("Log Set").assertExists()
        key("1"); key("5")
        assertThat(fixture.set(index, 0).reps).isEqualTo(15)
        assertThat(fixture.set(index, 0).weightKg).isEqualTo(0.0)
    }

    @Test
    fun doneButtonDismissesWithoutLogging() {
        open()
        rule.onNodeWithText("Done").assertIsEnabled().performClick()
        rule.waitForIdle()
        assertThat(dismissed).isEqualTo(1)
        assertThat(benchSet().isDone).isFalse()
    }

    @Test
    fun loggedSetShowsDoneAndDoesNotLogTwice() {
        fixture.controller.send(WorkoutAction.LogSet(benchSet3.exerciseID, benchSet3.setID))
        assertThat(benchSet().isDone).isTrue()
        open(benchSet3, KeypadField.REPS)
        // The title bar's "Done" and the primary button, which is "Done" for a logged set.
        rule.onAllNodesWithText("Done").assertCountEquals(2)
        assertThat(benchSet().type).isEqualTo(SetType.NORMAL)
    }

    @Test
    fun closesWhenTheSetDisappears() {
        open()
        fixture.controller.send(WorkoutAction.DeleteSet(benchSet3.exerciseID, benchSet3.setID))
        rule.waitForIdle()
        assertThat(dismissed).isEqualTo(1)
    }
}
