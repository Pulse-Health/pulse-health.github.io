package health.pulse.strength.ui.active

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.performClick
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.ui.ScreenshotSupport
import health.pulse.strength.ui.components.LocalPulseClock
import health.pulse.strength.ui.components.PulseClock
import health.pulse.strength.ui.theme.PulseTheme
import java.time.Instant
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The countdown and the clock right after an action. The 1 Hz ticker is up to a second behind the real clock that the reducer stamps
 * the rest's end with, so a presentation built at the tick's time showed one second too much (2:31 for a fresh 2:30 rest) until the
 * next tick. Here the ticker is frozen at the start while the real clock moves on 0.9 s, the worst case.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ActiveRealTimeTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    /** A clock that moves without ticking: the screen's ticker keeps the time it read when it started. */
    private class RealClock(var time: Instant) {
        val clock = PulseClock(now = { time }, ticks = false)
    }

    private fun show(fixture: ActiveFixture, real: RealClock) {
        rule.setContent {
            CompositionLocalProvider(LocalPulseClock provides real.clock) {
                PulseTheme(darkTheme = false, reduceMotion = true) {
                    ActiveWorkoutHost(
                        controller = fixture.controller,
                        store = fixture.store,
                        uiState = remember { ActiveWorkoutUiState() },
                        onMinimise = {},
                        onFinished = {},
                    )
                }
            }
        }
        rule.waitForIdle()
    }

    /** The real clock (and the controller's) moves on by [millis] while the ticker does not. */
    private fun advance(fixture: ActiveFixture, real: RealClock, millis: Long) {
        real.time = real.time.plusMillis(millis)
        fixture.now = real.time
    }

    @Test
    fun aFreshRestStartsAtItsFullTimeNotOneSecondMore() {
        val fixture = ActiveFixture()
        val real = RealClock(ScreenshotSupport.fixedNow)
        show(fixture, real)
        advance(fixture, real, 900)

        rule.tagged("set-check-${fixture.setID(0, 2)}").performClick()
        rule.waitForIdle()
        // Bench press rests 2:30 after a working set.
        rule.tagged("rest-remaining").assertTextEquals("2:30")
    }

    @Test
    fun resumeShowsTheFrozenRestWithoutJumpingUp() {
        val fixture = ActiveFixture()
        fixture.log(0, 0..2, secondsAgo = 78)
        fixture.send(WorkoutAction.Pause)
        val real = RealClock(ScreenshotSupport.fixedNow)
        show(fixture, real)
        rule.tagged("rest-remaining").assertTextEquals("1:12")
        advance(fixture, real, 900)

        fixture.send(WorkoutAction.Resume)
        rule.waitForIdle()
        rule.tagged("rest-remaining").assertTextEquals("1:12")
    }

    @Test
    fun theRestAndTheClockStillRunOnTheTicker() {
        val fixture = ActiveFixture()
        fixture.log(0, 0..2, secondsAgo = 78)
        val clock = ClockHandle()
        rule.showActiveScreen(fixture, clock = clock)
        rule.tagged("rest-remaining").assertTextEquals("1:12")
        rule.tagged("active-clock").assertTextEquals("24:18")

        // A tick of the clock without any action: the idle seconds still count.
        clock.time = clock.time.plusSeconds(10)
        rule.waitForIdle()
        rule.tagged("rest-remaining").assertTextEquals("1:02")
        rule.tagged("active-clock").assertTextEquals("24:28")
    }
}
