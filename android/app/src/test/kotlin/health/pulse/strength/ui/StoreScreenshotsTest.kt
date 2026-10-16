package health.pulse.strength.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipe
import health.pulse.strength.ui.ScreenshotSupport.capture
import health.pulse.strength.ui.active.ActiveFixture
import health.pulse.strength.ui.active.ClockHandle
import health.pulse.strength.ui.active.ScreenEvents
import health.pulse.strength.ui.active.TestScreenTheme
import health.pulse.strength.ui.active.applySystemBars
import health.pulse.strength.ui.active.showActiveScreen
import health.pulse.strength.ui.detail.ExerciseDetailScreen
import health.pulse.strength.ui.hub.HubTestSupport
import health.pulse.strength.ui.summary.WorkoutSummaryScreen
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Renders the Google Play phone screenshots from the real screens with the demo data: `app/build/screens/store/NN-name.png`, 1080 x 2160
 * (a 360 x 720 dp window at xxhdpi; Google Play wants an aspect ratio of at most 2:1 and 320 to 3840 px). They are not tests of behaviour;
 * the other suites cover that. To refresh the listing, run this class and copy the files to `store/graphics/phone-screenshots/`.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h720dp-xxhdpi")
class StoreScreenshotsTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val demoNow = HubTestSupport.demoNow

    @Before
    fun pinLocale() = HubTestSupport.fixLocale()

    /** Drags the page up by [fraction] of the window height, like a thumb would. */
    private fun scrollUp(fraction: Float) {
        rule.onRoot().performTouchInput {
            swipe(start = Offset(centerX, height * 0.85f), end = Offset(centerX, height * (0.85f - fraction)), durationMillis = 600)
        }
        rule.waitForIdle()
    }

    private fun shot(name: String) = rule.capture("store/$name")

    @Test
    fun hub() {
        val environment = HubTestSupport.environment(seed = true, now = demoNow)
        rule.setContent { TestScreenTheme(ClockHandle(demoNow)) { PulseStrengthRoot(environment) } }
        rule.applySystemBars()
        shot("01-strength-hub")
    }

    @Test
    fun recoveryAndHistory() {
        val environment = HubTestSupport.environment(seed = true, now = demoNow)
        rule.setContent { TestScreenTheme(ClockHandle(demoNow)) { PulseStrengthRoot(environment) } }
        rule.applySystemBars()
        scrollUp(0.62f)
        shot("02-recovery-and-history")
    }

    @Test
    fun activeWorkout() {
        val fixture = ActiveFixture()
        fixture.log(exerciseIndex = 0, setIndices = 0..3, secondsAgo = 45)
        rule.showActiveScreen(fixture, ScreenEvents())
        rule.applySystemBars()
        shot("03-active-workout")
    }

    @Test
    fun activeWorkoutDark() {
        val fixture = ActiveFixture()
        fixture.log(exerciseIndex = 0, setIndices = 0..3, secondsAgo = 45)
        rule.showActiveScreen(fixture, ScreenEvents(), dark = true)
        rule.applySystemBars()
        shot("06-active-workout-dark")
    }

    @Test
    fun summary() {
        val environment = HubTestSupport.environment(seed = true, now = demoNow)
        val workout = environment.store.history.firstOrNull { it.personalRecords.isNotEmpty() } ?: environment.store.history.first()
        rule.setContent { TestScreenTheme(ClockHandle(demoNow)) { WorkoutSummaryScreen(workout = workout, onDone = {}) } }
        rule.applySystemBars()
        shot("04-workout-summary")
    }

    @Test
    fun exerciseDetail() {
        val environment = HubTestSupport.environment(seed = true, now = demoNow)
        val bench = environment.store.exercise("bench")!!
        rule.setContent {
            TestScreenTheme(ClockHandle(demoNow)) { ExerciseDetailScreen(exercise = bench, store = environment.store, onBack = {}) }
        }
        rule.applySystemBars()
        scrollUp(0.5f)
        shot("05-exercise-progress")
    }
}
