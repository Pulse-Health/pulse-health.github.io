package health.pulse.strength.ui.active

import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.junit4.ComposeContentTestRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.ui.ScreenshotSupport
import health.pulse.strength.ui.components.LocalPulseClock
import health.pulse.strength.ui.components.PulseClock
import health.pulse.strength.ui.theme.PulseTheme
import java.time.Instant

/** The node with [tag] in the unmerged semantics tree (most parts of the screen merge their children for the screen reader). */
internal fun ComposeContentTestRule.tagged(tag: String): SemanticsNodeInteraction = onNodeWithTag(tag, useUnmergedTree = true)

internal fun hasTag(tag: String) = hasTestTag(tag)

/** What a test host records of the screen's callbacks. */
internal class ScreenEvents {
    var minimised = 0
    val finished = mutableListOf<CompletedWorkout?>()
}

/**
 * Shows the active-workout screen of [fixture] in the Pulse theme with a clock that stands still at [time] (move it with
 * [ClockHandle.time]; changing it re-reads the time like a tick of the real clock).
 */
internal class ClockHandle(initial: Instant = ScreenshotSupport.fixedNow) {
    var time: Instant by mutableStateOf(initial)
}

@Composable
internal fun TestScreenTheme(clock: ClockHandle, dark: Boolean = false, content: @Composable () -> Unit) {
    val time = clock.time
    val pulseClock = remember(time) { PulseClock(now = { time }, ticks = false) }
    CompositionLocalProvider(LocalPulseClock provides pulseClock) {
        PulseTheme(darkTheme = dark, reduceMotion = true) { content() }
    }
}

internal fun ComposeContentTestRule.showActiveScreen(
    fixture: ActiveFixture,
    events: ScreenEvents = ScreenEvents(),
    uiState: ActiveWorkoutUiState = ActiveWorkoutUiState(),
    clock: ClockHandle = ClockHandle(),
    dark: Boolean = false,
) {
    setContent {
        TestScreenTheme(clock, dark) {
            ActiveWorkoutHost(
                controller = fixture.controller,
                store = fixture.store,
                uiState = uiState,
                onMinimise = { events.minimised += 1 },
                onFinished = { events.finished.add(it) },
            )
        }
    }
    waitForIdle()
}

/**
 * Gives the window the system bars of a real phone (status bar on top, navigation bar at the bottom, in dp), so the layout's use
 * of the window insets can be seen in the screenshots. Call it after `setContent`.
 */
internal fun AndroidComposeTestRule<*, ComponentActivity>.applySystemBars(
    topDp: Int = 28,
    bottomDp: Int = 24,
    leftDp: Int = 0,
    rightDp: Int = 0,
    imeDp: Int = 0,
) {
    val density = density
    fun px(dp: Int) = with(density) { dp.dp.roundToPx() }
    runOnUiThread {
        WindowCompat.setDecorFitsSystemWindows(activity.window, false)
        val insets = WindowInsetsCompat.Builder()
            .setInsets(WindowInsetsCompat.Type.statusBars(), Insets.of(0, px(topDp), 0, 0))
            .setInsets(WindowInsetsCompat.Type.navigationBars(), Insets.of(px(leftDp), 0, px(rightDp), px(bottomDp)))
            .setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, px(imeDp)))
            .setVisible(WindowInsetsCompat.Type.ime(), imeDp > 0)
            .build()
        ViewCompat.dispatchApplyWindowInsets(activity.window.decorView, insets)
    }
    waitForIdle()
}
