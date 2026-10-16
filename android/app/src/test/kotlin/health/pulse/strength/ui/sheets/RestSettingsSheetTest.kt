package health.pulse.strength.ui.sheets

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import com.google.common.truth.Truth.assertThat
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The rest presets set the exercise's rest; the two switches set the workout settings. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class RestSettingsSheetTest {
    @get:Rule val rule = createComposeRule()

    private val fixture = SheetFixture()
    private var dismissed = 0

    private fun open(exerciseIndex: Int = 1) {
        val id = fixture.exercises[exerciseIndex].id
        rule.setContent { PulseTestTheme { RestSettingsSheet(fixture.controller, id, onDismiss = { dismissed++ }) } }
        rule.waitForIdle()
    }

    private fun isSelected(selected: Boolean) = SemanticsMatcher.expectValue(SemanticsProperties.Selected, selected)

    @Test
    fun showsTheExerciseItConfiguresAndItsCurrentPreset() {
        open()
        rule.onNodeWithText("Rest Timer").assertExists()
        rule.onNodeWithText("Rest after each set · Incline dumbbell press").assertExists()
        for (label in listOf("Off", "0:30", "0:45", "1:00", "1:30", "2:00", "2:30", "3:00", "4:00", "5:00")) {
            rule.onNodeWithText(label).assertExists()
        }
        // Incline dumbbell press rests 90 s in the demo workout.
        rule.onNodeWithContentDescription("1 minute 30 seconds").assert(isSelected(true))
        rule.onNodeWithContentDescription("2 minutes").assert(isSelected(false))
    }

    @Test
    fun presetsSetTheExercisesRestOnly() {
        open()
        val other = fixture.exercises[0].restSeconds
        rule.onNodeWithContentDescription("2 minutes 30 seconds").performClick()
        assertThat(fixture.exercises[1].restSeconds).isEqualTo(150)
        rule.onNodeWithContentDescription("30 seconds").performClick()
        assertThat(fixture.exercises[1].restSeconds).isEqualTo(30)
        rule.onNodeWithContentDescription("Rest timer off").performClick()
        assertThat(fixture.exercises[1].restSeconds).isEqualTo(0)
        rule.onNodeWithContentDescription("5 minutes").performClick()
        assertThat(fixture.exercises[1].restSeconds).isEqualTo(300)
        assertThat(fixture.exercises[0].restSeconds).isEqualTo(other)
        rule.onNodeWithContentDescription("5 minutes").assert(isSelected(true))
        assertThat(dismissed).isEqualTo(0)
    }

    @Test
    fun switchesDispatchTheWorkoutSettings() {
        open()
        assertThat(fixture.controller.state.value!!.settings.autoStartRest).isTrue()
        rule.onNodeWithText("Start after logging a set").performClick()
        assertThat(fixture.controller.state.value!!.settings.autoStartRest).isFalse()
        rule.onNodeWithText("Start after logging a set").performClick()
        assertThat(fixture.controller.state.value!!.settings.autoStartRest).isTrue()

        assertThat(fixture.controller.state.value!!.settings.alertWhenRestEnds).isTrue()
        rule.onNodeWithText("Alert when rest is over").performClick()
        assertThat(fixture.controller.state.value!!.settings.alertWhenRestEnds).isFalse()
        rule.onNodeWithText("Shorter after warm-up sets").assertExists()
        rule.onNodeWithText("Haptic, sound and Lock Screen update").assertExists()
    }

    @Test
    fun touchTargetsAreAtLeast48dp() {
        open()
        rule.onNodeWithContentDescription("3 minutes").assertHeightIsAtLeast(48.dp)
        rule.onNodeWithText("Start after logging a set").assertHeightIsAtLeast(48.dp)
    }

    @Test
    fun doneDismisses() {
        open()
        rule.onNodeWithText("Done").performClick()
        rule.waitForIdle()
        assertThat(dismissed).isEqualTo(1)
    }
}
