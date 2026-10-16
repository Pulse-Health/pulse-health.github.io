package health.pulse.strength.ui.active

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.performClick
import androidx.lifecycle.Lifecycle
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.ActiveWorkoutPresentation.DockPhase
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.ui.components.rememberNow
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The haptic + "Rest over" announcement when a rest ends: the rule itself, on the workout screen and on the in-progress bar. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class RestEndFeedbackTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    // region The rule

    @Test
    fun playsOnlyWhenARunningRestFinishesInTheForegroundWithAlertsOn() {
        val running = DockPhase.RUNNING
        val finished = DockPhase.FINISHED
        assertThat(RestEndFeedback.shouldPlay(running, finished, isForeground = true, alertsEnabled = true)).isTrue()
        assertThat(RestEndFeedback.shouldPlay(running, finished, isForeground = false, alertsEnabled = true)).isFalse()
        assertThat(RestEndFeedback.shouldPlay(running, finished, isForeground = true, alertsEnabled = false)).isFalse()
        // Only the RUNNING -> FINISHED edge counts.
        assertThat(RestEndFeedback.shouldPlay(null, finished, isForeground = true, alertsEnabled = true)).isFalse()
        assertThat(RestEndFeedback.shouldPlay(finished, finished, isForeground = true, alertsEnabled = true)).isFalse()
        assertThat(RestEndFeedback.shouldPlay(running, null, isForeground = true, alertsEnabled = true)).isFalse()
        assertThat(RestEndFeedback.shouldPlay(running, running, isForeground = true, alertsEnabled = true)).isFalse()
        assertThat(RestEndFeedback.shouldPlay(finished, running, isForeground = true, alertsEnabled = true)).isFalse()
    }

    @Test
    fun announcementIsRestOver() {
        assertThat(RestEndFeedback.Announcement).isEqualTo("Rest over")
    }

    // endregion

    // region On the workout screen

    private class Plays {
        var count = 0
    }

    /** A rest of 10 s is running at the clock's start; the clock then moves past it. */
    private fun ActiveFixture.restEndingInTenSeconds(): ActiveFixture {
        log(0, 0..2, secondsAgo = 140)
        return this
    }

    private fun showScreen(fixture: ActiveFixture, plays: Plays, clock: ClockHandle = ClockHandle()): ClockHandle {
        rule.setContent {
            TestScreenTheme(clock) {
                CompositionLocalProvider(LocalRestEndPlayer provides RestEndPlayer { plays.count += 1 }) {
                    ActiveWorkoutHost(
                        controller = fixture.controller,
                        store = fixture.store,
                        uiState = ActiveWorkoutUiState(),
                        onMinimise = {},
                        onFinished = {},
                    )
                }
            }
        }
        rule.waitForIdle()
        return clock
    }

    @Test
    fun screenPlaysTheCueOnceWhenTheRestRunsOut() {
        val fixture = ActiveFixture().restEndingInTenSeconds()
        val plays = Plays()
        val clock = showScreen(fixture, plays)
        assertThat(fixture.presentation().dock!!.phase).isEqualTo(DockPhase.RUNNING)
        assertThat(plays.count).isEqualTo(0)

        clock.time = clock.time.plusSeconds(11)
        rule.waitForIdle()
        assertThat(plays.count).isEqualTo(1)
        clock.time = clock.time.plusSeconds(5)
        rule.waitForIdle()
        assertThat(plays.count).isEqualTo(1)
    }

    @Test
    fun screenStaysSilentWhenAlertsAreOff() {
        val fixture = ActiveFixture().restEndingInTenSeconds()
        fixture.send(WorkoutAction.SetAlertWhenRestEnds(false))
        val plays = Plays()
        val clock = showScreen(fixture, plays)

        clock.time = clock.time.plusSeconds(11)
        rule.waitForIdle()
        assertThat(plays.count).isEqualTo(0)
    }

    @Test
    fun screenStaysSilentWhenTheAppIsNotInTheForeground() {
        val fixture = ActiveFixture().restEndingInTenSeconds()
        val plays = Plays()
        val clock = showScreen(fixture, plays)

        rule.activityRule.scenario.moveToState(Lifecycle.State.STARTED)
        rule.waitForIdle()
        clock.time = clock.time.plusSeconds(11)
        rule.waitForIdle()
        assertThat(plays.count).isEqualTo(0)
    }

    @Test
    fun skippingTheRestBeforeItEndsIsSilent() {
        val fixture = ActiveFixture().restEndingInTenSeconds()
        val plays = Plays()
        val clock = showScreen(fixture, plays)

        rule.tagged("dock-skip").performClick()
        rule.waitForIdle()
        clock.time = clock.time.plusSeconds(30)
        rule.waitForIdle()
        assertThat(plays.count).isEqualTo(0)
    }

    @Test
    fun aRestThatAlreadyEndedWhenTheScreenOpensIsSilent() {
        val fixture = ActiveFixture()
        fixture.log(0, 0..2, secondsAgo = 200)
        val plays = Plays()
        showScreen(fixture, plays)
        assertThat(fixture.presentation().dock!!.phase).isEqualTo(DockPhase.FINISHED)
        assertThat(plays.count).isEqualTo(0)
    }

    @Test
    fun extendingTheRestStartsAFreshCountdownThatPlaysAgain() {
        val fixture = ActiveFixture().restEndingInTenSeconds()
        val plays = Plays()
        val clock = showScreen(fixture, plays)
        clock.time = clock.time.plusSeconds(11)
        rule.waitForIdle()
        assertThat(plays.count).isEqualTo(1)

        // +15 on the finished rest runs again (the dock is back to RUNNING), and its end is a new cue.
        fixture.now = clock.time
        rule.tagged("dock-dismiss").performClick()
        fixture.send(WorkoutAction.AdjustRest(15))
        rule.waitForIdle()
        clock.time = clock.time.plusSeconds(20)
        rule.waitForIdle()
        assertThat(plays.count).isEqualTo(2)
    }

    // endregion

    // region On the in-progress bar

    private fun showBar(
        fixture: ActiveFixture,
        plays: Plays,
        clock: ClockHandle = ClockHandle(),
        alertsEnabled: Boolean? = null,
    ): ClockHandle {
        rule.setContent {
            TestScreenTheme(clock) {
                CompositionLocalProvider(LocalRestEndPlayer provides RestEndPlayer { plays.count += 1 }) {
                    val now = rememberNow().value
                    val presentation = fixture.controller.presentation(now)
                    if (presentation != null) {
                        if (alertsEnabled == null) {
                            WorkoutInProgressBar(presentation = presentation, onResume = {})
                        } else {
                            CompositionLocalProvider(LocalRestAlertsEnabled provides alertsEnabled) {
                                WorkoutInProgressBar(presentation = presentation, onResume = {})
                            }
                        }
                    }
                }
            }
        }
        rule.waitForIdle()
        return clock
    }

    @Test
    fun barPlaysTheCueWhileTheWorkoutIsMinimised() {
        val fixture = ActiveFixture().restEndingInTenSeconds()
        val plays = Plays()
        val clock = showBar(fixture, plays)
        assertThat(plays.count).isEqualTo(0)

        clock.time = clock.time.plusSeconds(11)
        rule.waitForIdle()
        assertThat(plays.count).isEqualTo(1)
    }

    @Test
    fun barHonoursTheAlertSettingItIsGiven() {
        val fixture = ActiveFixture().restEndingInTenSeconds()
        val plays = Plays()
        val clock = showBar(fixture, plays, alertsEnabled = false)

        clock.time = clock.time.plusSeconds(11)
        rule.waitForIdle()
        assertThat(plays.count).isEqualTo(0)
    }

    @Test
    fun barIsSilentWithoutARunningRest() {
        val fixture = ActiveFixture()
        val plays = Plays()
        val clock = showBar(fixture, plays)
        clock.time = clock.time.plusSeconds(120)
        rule.waitForIdle()
        assertThat(plays.count).isEqualTo(0)
    }

    // endregion
}
