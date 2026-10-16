package health.pulse.strength.ui.active

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.StrengthAppEnvironment
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.ui.PulseStrengthRoot
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The screen and the bar as the app root wires them: resume from the bar, minimise, system back, finish and discard. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ActiveWorkoutInRootTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private fun show(environment: StrengthAppEnvironment) {
        rule.setContent {
            TestScreenTheme(ClockHandle()) { PulseStrengthRoot(environment) }
        }
        rule.waitForIdle()
    }

    private fun barCount() = rule.onAllNodesWithTag("in-progress-bar", useUnmergedTree = true)
    private fun screenCount() = rule.onAllNodesWithTag("active-title", useUnmergedTree = true)

    @Test
    fun barResumesTheScreenAndTheChevronMinimisesIt() {
        val environment = StrengthAppEnvironment.preview(withActiveWorkout = true)
        show(environment)
        barCount().assertCountEquals(1)
        screenCount().assertCountEquals(0)

        rule.tagged("in-progress-bar").performClick()
        rule.waitForIdle()
        screenCount().assertCountEquals(1)
        barCount().assertCountEquals(0)

        rule.onNodeWithContentDescription("Minimise workout").performClick()
        rule.waitForIdle()
        screenCount().assertCountEquals(0)
        barCount().assertCountEquals(1)
        assertThat(environment.controller.state.value).isNotNull()
    }

    @Test
    fun systemBackMinimisesTheScreen() {
        val environment = StrengthAppEnvironment.preview(withActiveWorkout = true)
        show(environment)
        rule.tagged("in-progress-bar").performClick()
        rule.waitForIdle()
        screenCount().assertCountEquals(1)

        rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        rule.waitForIdle()
        screenCount().assertCountEquals(0)
        barCount().assertCountEquals(1)
    }

    @Test
    fun finishingEndsTheWorkoutAndRemovesBothScreenAndBar() {
        val environment = StrengthAppEnvironment.preview(withActiveWorkout = true)
        val controller = environment.controller
        val state = controller.state.value!!
        controller.send(WorkoutAction.ToggleSet(state.exercises[0].id, state.exercises[0].sets[2].id))
        show(environment)
        rule.tagged("in-progress-bar").performClick()
        rule.waitForIdle()

        rule.tagged("active-finish").performClick()
        rule.onNodeWithText("Finish Workout").performClick()
        rule.waitForIdle()
        assertThat(controller.state.value).isNull()
        assertThat(environment.store.history.first().loggedSets).isEqualTo(1)
        screenCount().assertCountEquals(0)
        barCount().assertCountEquals(0)
    }

    @Test
    fun discardingEndsTheWorkoutWithoutASummary() {
        val environment = StrengthAppEnvironment.preview(withActiveWorkout = true)
        val historyBefore = environment.store.history.size
        show(environment)
        rule.tagged("in-progress-bar").performClick()
        rule.waitForIdle()

        rule.tagged("active-finish").performClick()
        rule.onNodeWithText("Discard Workout").performClick()
        rule.onNodeWithText("Discard").performClick()
        rule.waitForIdle()
        assertThat(environment.controller.state.value).isNull()
        assertThat(environment.store.history).hasSize(historyBefore)
        screenCount().assertCountEquals(0)
        barCount().assertCountEquals(0)
    }
}
