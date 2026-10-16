package health.pulse.strength.ui.sheets

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.ui.PickerMode
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The picker adds or replaces exercises, filters the library, and creates custom exercises. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ExercisePickerSheetTest {
    @get:Rule val rule = createComposeRule()

    private val fixture = SheetFixture()
    private var dismissed = 0

    private fun open(mode: PickerMode = PickerMode.Add) {
        rule.setContent {
            PulseTestTheme { ExercisePickerSheet(fixture.store, fixture.controller, mode, onDismiss = { dismissed++ }) }
        }
        rule.waitForIdle()
    }

    private fun search(text: String) = rule.onNodeWithContentDescription("Search exercises").performTextInput(text)

    private fun scrollTo(text: String) = rule.onNode(hasScrollAction()).performScrollToNode(hasText(text))

    private fun ids() = fixture.exercises.map { it.exercise.id }

    private fun checked(value: Boolean) =
        SemanticsMatcher.expectValue(SemanticsProperties.ToggleableState, ToggleableState(value))

    @Test
    fun showsTheDesignsChromeAndTheWholeLibrary() {
        open()
        rule.onNodeWithText("Add Exercise").assertExists()
        rule.onNodeWithText("Cancel").assertExists()
        rule.onNodeWithText("Search").assertExists()
        for (label in listOf("All", "Chest", "Back", "Shoulders", "Arms", "Legs", "Core")) rule.onNodeWithText(label).assertExists()
        for (label in listOf("Any", "Barbell", "Dumbbell", "Cable", "Machine", "Bodyweight")) rule.onNodeWithText(label).assertExists()
        rule.onNodeWithText("Other").assertDoesNotExist()
        rule.onNodeWithText("Create custom exercise").assertExists()
        rule.onNodeWithText("${fixture.store.exercises.size} exercises").assertExists()
        rule.onNodeWithText("Select exercises").assertExists().assertIsNotEnabled()
    }

    @Test
    fun searchFiltersAndTheCountFollows() {
        open()
        search("bench")
        rule.onNodeWithText("Barbell bench press").assertExists()
        rule.onNodeWithText("Push-up").assertDoesNotExist()
        rule.onNodeWithText("Create “bench”").assertExists()
        // The clear button empties the field again.
        rule.onNodeWithContentDescription("Clear search").performClick()
        rule.onNodeWithText("Create custom exercise").assertExists()
        scrollTo("Push-up")
        rule.onNodeWithText("Push-up").assertExists()
    }

    @Test
    fun noMatchShowsTheEmptyMessage() {
        open()
        search("zzzz")
        rule.onNodeWithText("0 exercises").assertExists()
        rule.onNodeWithText("No exercise matches. Create it as a custom exercise.").assertExists()
        rule.onNodeWithText("Create “zzzz”").assertExists()
    }

    @Test
    fun muscleAndEquipmentChipsNarrowTheList() {
        open()
        rule.onNodeWithText("Legs").performClick()
        rule.onNodeWithText("Back squat").assertExists()
        rule.onNodeWithText("Push-up").assertDoesNotExist()
        rule.onNodeWithText("Machine").performClick()
        rule.onNodeWithText("Leg press").assertExists()
        rule.onNodeWithText("Back squat").assertDoesNotExist()
        rule.onNodeWithText("All").performClick()
        rule.onNodeWithText("Any").performClick()
        scrollTo("Push-up")
        rule.onNodeWithText("Push-up").assertExists()
    }

    @Test
    fun exercisesAlreadyInTheWorkoutAreNotSelectable() {
        open()
        search("bench")
        rule.onNodeWithText("Chest · Barbell · Already in workout").assertExists()
        rule.onNodeWithText("Barbell bench press").performClick()
        rule.onNodeWithText("Select exercises").assertExists()
    }

    @Test
    fun addModeSelectsSeveralAndAddsThemInOrder() {
        open()
        val before = ids()
        search("push-up")
        rule.onNodeWithText("Push-up").performClick()
        rule.onNodeWithText("Push-up").assert(checked(true))
        rule.onNodeWithText("Add 1 exercise").assertExists()
        // Selections survive a change of the search.
        rule.onNodeWithContentDescription("Clear search").performClick()
        search("machine chest")
        rule.onNodeWithText("Machine chest press").performClick()
        rule.onNodeWithText("Add 2 exercises").assertExists()
        rule.onNodeWithText("Add 2 exercises").performClick()
        rule.waitForIdle()
        assertThat(ids()).isEqualTo(before + listOf("pushup", "cpress"))
        assertThat(dismissed).isEqualTo(1)
    }

    @Test
    fun tappingASelectedRowDeselectsIt() {
        open()
        search("push-up")
        rule.onNodeWithText("Push-up").performClick()
        rule.onNodeWithText("Push-up").performClick()
        rule.onNodeWithText("Push-up").assert(checked(false))
        rule.onNodeWithText("Select exercises").assertExists()
    }

    @Test
    fun confirmingTwiceAddsOnce() {
        open()
        search("push-up")
        rule.onNodeWithText("Push-up").performClick()
        val before = ids().size
        rule.onNodeWithText("Add 1 exercise").performClick()
        rule.onNodeWithText("Add 1 exercise").performClick()
        rule.waitForIdle()
        assertThat(ids()).hasSize(before + 1)
    }

    @Test
    fun replaceModeKeepsOneSelectionAndReplacesInPlace() {
        val target = fixture.exercises[1]
        open(PickerMode.Replace(target.id))
        rule.onNodeWithText("Replace Exercise").assertExists()
        search("push-up")
        rule.onNodeWithText("Push-up").performClick()
        rule.onNodeWithContentDescription("Clear search").performClick()
        search("machine chest")
        rule.onNodeWithText("Machine chest press").performClick()
        rule.onNodeWithText("Replace with Machine chest press").assertExists()
        rule.onNodeWithText("Replace with Machine chest press").performClick()
        rule.waitForIdle()
        val replaced = fixture.exercises[1]
        assertThat(replaced.exercise.id).isEqualTo("cpress")
        // The workout entry keeps its place and id; the count does not change.
        assertThat(replaced.id).isEqualTo(target.id)
        assertThat(fixture.exercises).hasSize(6)
        assertThat(dismissed).isEqualTo(1)
    }

    @Test
    fun replaceModeAllowsAnyExerciseEvenOneInTheWorkout() {
        val target = fixture.exercises[1]
        open(PickerMode.Replace(target.id))
        search("bench")
        rule.onNodeWithText("Chest · Barbell").assertExists()
    }

    @Test
    fun createRowOpensTheFormAndSelectsTheNewExercise() {
        open()
        search("Landmine")
        rule.onNodeWithText("Create “Landmine”").performClick()
        rule.waitForIdle()
        // The form is prefilled with the search text.
        rule.onNodeWithText("New Exercise").assertExists()
        rule.onNodeWithContentDescription("Name").assertTextEquals("Landmine")
        rule.onNodeWithText("Save").performClick()
        rule.waitForIdle()
        val custom = fixture.store.customExercises
        assertThat(custom.map { it.name }).containsExactly("Landmine")
        rule.onNodeWithText("Add 1 exercise").assertExists()
        // The search was cleared so the new exercise is visible in the list.
        rule.onNodeWithText("Create custom exercise").assertExists()
        rule.onNodeWithText("Add 1 exercise").performClick()
        rule.waitForIdle()
        assertThat(fixture.exercises.last().exercise.name).isEqualTo("Landmine")
        assertThat(dismissed).isEqualTo(1)
    }

    @Test
    fun cancelDismissesWithoutChanges() {
        open()
        val before = ids()
        search("push-up")
        rule.onNodeWithText("Push-up").performClick()
        rule.onNodeWithText("Cancel").performClick()
        rule.waitForIdle()
        assertThat(dismissed).isEqualTo(1)
        assertThat(ids()).isEqualTo(before)
    }
}
