package health.pulse.strength.live

import android.app.Application
import android.view.WindowManager
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.runtime.PreviewRuntime
import health.pulse.strength.runtime.StrengthRuntime
import health.pulse.strength.ui.components.LocalPulseClock
import health.pulse.strength.ui.components.PulseClock
import java.time.ZoneId
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** SB-02 / SB-04: bench mode drawn and pressed, with the clock frozen at [NOW]. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w411dp-h891dp-xxhdpi")
class BenchModeScreenTest {
    @get:Rule val rule = createComposeRule()

    private val calls = mutableListOf<String>()
    private val actions = BenchActions(
        adjustRest = { calls += "rest:$it" },
        skipRest = { calls += "skip" },
        logSet = { calls += "log" },
        resume = { calls += "resume" },
        openWorkout = { calls += "workout" },
        close = { calls += "close" },
    )

    @After
    fun restore() {
        StrengthRuntime.installForTest(PreviewRuntime())
    }

    private fun show(active: WorkoutSnapshot?, night: Boolean? = false, is24Hour: Boolean = true) {
        rule.setContent {
            CompositionLocalProvider(LocalPulseClock provides PulseClock(now = { NOW }, ticks = false)) {
                BenchModeScreen(previewWith(active), night, is24Hour, actions)
            }
        }
        rule.waitForIdle()
    }

    @Test
    fun restingShowsTheCountdownTheNextSetAndTheButtons() {
        show(restingSnapshot(remaining = 84))
        rule.onNodeWithText("1:24").assertIsDisplayed()
        rule.onNodeWithText("Resting · Bench Press").assertIsDisplayed()
        rule.onNodeWithText("Next: Set 4").assertIsDisplayed()
        rule.onNodeWithText("82.5 kg × 6").assertIsDisplayed()
        rule.onNodeWithContentDescription("Rest, 1 minute 24 seconds left. Next: Set 4, 82.5 kg × 6").assertIsDisplayed()

        rule.onNodeWithContentDescription("Add 15 seconds").performClick()
        rule.onNodeWithContentDescription("Skip rest").performClick()
        assertThat(calls).containsExactly("rest:15", "skip").inOrder()
    }

    @Test
    fun theButtonsAreBigEnoughToHitFromADistance() {
        show(restingSnapshot())
        rule.onNodeWithContentDescription("Add 15 seconds").assertHeightIsAtLeast(48.dp)
        rule.onNodeWithContentDescription("Skip rest").assertHeightIsAtLeast(48.dp)
        rule.onNodeWithContentDescription("Close bench mode").assertHeightIsAtLeast(48.dp)
        rule.onNodeWithText("Workout").assertHeightIsAtLeast(48.dp)
    }

    @Test
    fun whenTheRestIsOverItSaysGoAndOffersLogSet() {
        show(restingSnapshot(remaining = -3))
        rule.onNodeWithText("Go").assertIsDisplayed()
        rule.onNodeWithText("Rest over · Bench Press").assertIsDisplayed()
        rule.onNodeWithContentDescription("Log set").performClick()
        assertThat(calls).containsExactly("log")
    }

    @Test
    fun loggingShowsTheWeightAndTheRepsLarge() {
        show(loggingSnapshot())
        rule.onNodeWithText("Bench Press").assertIsDisplayed()
        rule.onNodeWithText("Set 4 of 5").assertIsDisplayed()
        rule.onNodeWithText("82.5").assertIsDisplayed()
        rule.onNodeWithText("kg").assertIsDisplayed()
        rule.onNodeWithText("6").assertIsDisplayed()
        rule.onNodeWithText("reps").assertIsDisplayed()
        rule.onNodeWithContentDescription("82.5 kilograms, 6 reps").assertIsDisplayed()
        rule.onNodeWithContentDescription("Log set").performClick()
        assertThat(calls).containsExactly("log")
    }

    @Test
    fun pausedOffersResume() {
        show(pausedSnapshot())
        rule.onNodeWithText("Paused").assertIsDisplayed()
        rule.onNodeWithText("24:18").assertIsDisplayed()
        rule.onNodeWithContentDescription("Resume workout").performClick()
        assertThat(calls).containsExactly("resume")
    }

    @Test
    fun aCompleteWorkoutSendsThePersonToTheAppToFinish() {
        show(completeSnapshot())
        rule.onNodeWithText("All sets logged").assertIsDisplayed()
        rule.onNodeWithText("20 of 20 sets · 4,980 kg").assertIsDisplayed()
        rule.onNodeWithContentDescription("Open the workout to finish it").performClick()
        assertThat(calls).containsExactly("workout")
    }

    @Test
    fun withoutAWorkoutTomorrowsSessionStandsBesideTheClock() {
        show(null, night = true)
        rule.onNodeWithText("Morning session").assertIsDisplayed()
        rule.onNodeWithText("Lower A · Quads").assertIsDisplayed()
        rule.onNodeWithText("Planned 7:00 · Gym bag ready?").assertIsDisplayed()
        val local = NOW.atZone(ZoneId.systemDefault())
        val (digits, _) = LiveText.timeParts(local.hour * 60 + local.minute, is24Hour = true)
        rule.onNodeWithText(digits).assertIsDisplayed()
        rule.onNodeWithContentDescription("Time $digits").assertIsDisplayed()
    }

    @Test
    fun theClockUsesTheTwelveHourStyleWithASmallSuffix() {
        show(null, is24Hour = false)
        val local = NOW.atZone(ZoneId.systemDefault())
        val (digits, suffix) = LiveText.timeParts(local.hour * 60 + local.minute, is24Hour = false)
        rule.onNodeWithText(digits).assertIsDisplayed()
        rule.onNodeWithText(suffix!!).assertIsDisplayed()
    }

    @Test
    fun theTopBarClosesBenchModeAndOpensTheWorkout() {
        show(loggingSnapshot())
        rule.onNodeWithContentDescription("Close bench mode").performClick()
        rule.onNodeWithText("Workout").performClick()
        assertThat(calls).containsExactly("close", "workout").inOrder()
    }

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
    fun lyingOnItsSideTheRingAndTheButtonsStillFit() {
        show(restingSnapshot(remaining = 84))
        rule.onNodeWithText("1:24").assertIsDisplayed()
        rule.onNodeWithContentDescription("Add 15 seconds").assertIsDisplayed()
        rule.onNodeWithContentDescription("Skip rest").assertIsDisplayed()
    }

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi")
    fun aSmallPhoneStillShowsTheSetAndTheButton() {
        show(loggingSnapshot().copy(weightText = "142.5", repsText = "10"))
        rule.onNodeWithText("142.5").assertIsDisplayed()
        rule.onNodeWithText("10").assertIsDisplayed()
        rule.onNodeWithContentDescription("Log set").assertIsDisplayed()
    }

    @Test
    fun theActivityKeepsTheScreenOnAndStartsWithoutAWorkout() {
        val app = ApplicationProvider.getApplicationContext<Application>()
        val activity = Robolectric.buildActivity(BenchModeActivity::class.java, BenchMode.intent(app, night = true)).setup().get()
        assertThat(activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON).isNotEqualTo(0)
        assertThat(activity.isFinishing).isFalse()
    }
}
