package health.pulse.strength.ui.active

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.WorkoutAction
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The undo toast for a screen reader or Switch Access. The undo is only valid for the reducer's 6 s window, which the screen cannot
 * stretch, so Undo is made reachable at once instead: the toast text is a live region (announced when it appears) and carries an
 * "Undo" custom action, so the user does not have to find the Undo button among the rest of the screen before the toast is gone.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ActiveUndoToastAccessibilityTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private fun removedExerciseFixture(): ActiveFixture {
        val fixture = ActiveFixture()
        fixture.send(WorkoutAction.RemoveExercise(fixture.exerciseID(5)))
        rule.showActiveScreen(fixture)
        return fixture
    }

    /** The toast text as a screen reader sees it (the merged tree). */
    private fun toastText() = rule.onNodeWithText("Removed Cable crossover")

    @Test
    fun toastTextIsAnAnnouncedLiveRegion() {
        removedExerciseFixture()
        assertThat(toastText().fetchSemanticsNode().config[SemanticsProperties.LiveRegion]).isEqualTo(LiveRegionMode.Polite)
    }

    @Test
    fun toastTextOffersAnUndoCustomActionThatRestoresTheExercise() {
        val fixture = removedExerciseFixture()
        val actions = toastText().fetchSemanticsNode().config[SemanticsActions.CustomActions]
        assertThat(actions.map { it.label }).containsExactly("Undo")

        actions.single().action()
        rule.waitForIdle()
        assertThat(fixture.controller.state.value!!.exercises).hasSize(6)
        rule.onAllNodesWithTag("undo-toast", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test
    fun deletedSetToastOffersTheSameUndo() {
        val fixture = ActiveFixture()
        fixture.send(WorkoutAction.DeleteSet(fixture.exerciseID(0), fixture.setID(0, 4)))
        val before = fixture.controller.state.value!!.exercises[0].sets.size
        rule.showActiveScreen(fixture)

        val actions = rule.onNodeWithText("Set deleted").fetchSemanticsNode().config[SemanticsActions.CustomActions]
        actions.single { it.label == "Undo" }.action()
        rule.waitForIdle()
        assertThat(fixture.controller.state.value!!.exercises[0].sets.size).isEqualTo(before + 1)
    }

    @Test
    fun theUndoButtonStaysAnotherWayToTheSameAction() {
        val fixture = removedExerciseFixture()
        rule.tagged("undo-button").performClick()
        rule.waitForIdle()
        assertThat(fixture.controller.state.value!!.exercises).hasSize(6)
    }
}
