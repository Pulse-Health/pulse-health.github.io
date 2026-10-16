package health.pulse.strength.ui.active

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.ui.ScreenshotSupport.snapshot
import health.pulse.strength.ui.theme.PulseTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The floating "workout in progress" bar: texts, tap, semantics and a few renderings. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h300dp-xxhdpi")
class WorkoutInProgressBarTest {
    @get:Rule
    val rule = createComposeRule()

    /** The bar as the root shows it: 14 dp from the sides, over the hub's ground. */
    @Composable
    private fun Stage(fixture: ActiveFixture) {
        Column(Modifier.fillMaxWidth().background(PulseTheme.colors.ground)) {
            Spacer(Modifier.height(24.dp))
            Box(Modifier.padding(start = 14.dp, end = 14.dp, bottom = 12.dp)) {
                WorkoutInProgressBar(presentation = fixture.presentation(), onResume = {})
            }
        }
    }

    @Test
    fun showsTitleAndProgressLine() {
        val fixture = ActiveFixture()
        fixture.log(0, 0..2)
        rule.snapshot("bar-light") { Stage(fixture) }
        rule.onNodeWithTag("bar-title", useUnmergedTree = true).assertTextEquals("Upper A · Push")
        rule.onNodeWithTag("bar-subtitle", useUnmergedTree = true).assertTextEquals("Exercise 1 of 6 · 24:18 · 3 of 20 sets")
    }

    @Test
    fun pausedWorkoutSaysPaused() {
        val fixture = ActiveFixture()
        fixture.send(WorkoutAction.Pause)
        rule.snapshot("bar-paused") { Stage(fixture) }
        rule.onNodeWithTag("bar-subtitle", useUnmergedTree = true).assertTextEquals("Exercise 1 of 6 · Paused · 24:18 · 0 of 20 sets")
    }

    @Test
    fun emptyWorkoutHasNoExercisePart() {
        val fixture = ActiveFixture(template = null)
        rule.snapshot("bar-empty") { Stage(fixture) }
        rule.onNodeWithTag("bar-title", useUnmergedTree = true).assertTextEquals("Workout")
        rule.onNodeWithTag("bar-subtitle", useUnmergedTree = true).assertTextEquals("24:18 · 0 of 0 sets")
    }

    @Test
    fun darkAndLongTitle() {
        val fixture = ActiveFixture()
        fixture.send(WorkoutAction.Rename("Saturday upper body push day with a very long name"))
        rule.snapshot("bar-dark", dark = true) { Stage(fixture) }
        rule.onNodeWithTag("in-progress-bar", useUnmergedTree = true).assertExists()
    }

    @Test
    fun tapResumesAndTheBarIsOneLabelledButton() {
        val fixture = ActiveFixture()
        var resumed = 0
        rule.setContent {
            PulseTheme {
                WorkoutInProgressBar(presentation = fixture.presentation(), onResume = { resumed += 1 })
            }
        }
        val bar = rule.onNodeWithTag("in-progress-bar")
        bar.performClick()
        assertThat(resumed).isEqualTo(1)

        val config = bar.fetchSemanticsNode().config
        assertThat(config.getOrNull(SemanticsProperties.ContentDescription)).containsExactly("Resume workout in progress")
        assertThat(config.getOrNull(SemanticsProperties.StateDescription))
            .isEqualTo("Upper A · Push, Exercise 1 of 6 · 24:18 · 0 of 20 sets")
    }
}

/** The bar with the system font at 200 %: the texts wrap, the bar grows, nothing is cut off. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h400dp-xhdpi", fontScale = 2.0f)
class WorkoutInProgressBarFontScaleTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun barAt200PercentFontScale() {
        val fixture = ActiveFixture()
        fixture.log(0, 0..2)
        val file = rule.snapshot("bar-font2") {
            Column(Modifier.fillMaxWidth().background(PulseTheme.colors.ground)) {
                Spacer(Modifier.height(24.dp))
                Box(Modifier.padding(start = 14.dp, end = 14.dp, bottom = 12.dp)) {
                    WorkoutInProgressBar(presentation = fixture.presentation(), onResume = {})
                }
            }
        }
        assertThat(file.length()).isGreaterThan(1000)
    }
}
