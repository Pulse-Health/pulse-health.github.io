package health.pulse.strength.ui.hub

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.junit4.ComposeContentTestRule
import health.pulse.strength.StrengthAppEnvironment
import health.pulse.strength.core.DemoRecovery
import health.pulse.strength.core.FileStrengthPersistence
import health.pulse.strength.core.RecoveryProvider
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.core.WorkoutTemplate
import health.pulse.strength.ui.components.LocalPulseClock
import health.pulse.strength.ui.components.PulseClock
import health.pulse.strength.ui.theme.PulseTheme
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import java.time.Instant
import java.util.Locale
import java.util.TimeZone

/** Environments and content setup shared by the hub tests. */
object HubTestSupport {
    /** A Saturday: the demo history (3 and 5 days ago) falls into the same Sunday-based week, so "This Week" is filled. */
    val demoNow: Instant = Instant.parse("2026-01-17T10:00:00Z")

    /** Makes dates and week boundaries independent of the machine running the tests. */
    fun fixLocale() {
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
        Locale.setDefault(Locale.US)
    }

    /**
     * A real environment on a temporary folder. [seed] adds the demo data relative to [now] (the production store seeds nothing:
     * `seed = false` is the first-run state).
     */
    fun environment(
        seed: Boolean = true,
        now: Instant = demoNow,
        withActiveWorkout: Boolean = false,
        recovery: RecoveryProvider = DemoRecovery.provider,
    ): StrengthAppEnvironment {
        val persistence = FileStrengthPersistence.temporary()
        val store = StrengthStore(persistence, seedDemoData = seed, now = now)
        val controller = WorkoutController(store, persistence, recovery)
        if (withActiveWorkout) controller.startWorkout(store.templates.firstOrNull())
        return StrengthAppEnvironment.forParts(persistence, store, controller)
    }

    /** A second store on the same folder: what the next app launch would read. */
    fun reopenedStore(environment: StrengthAppEnvironment): StrengthStore = StrengthStore(environment.persistence, seedDemoData = false)

    /** Sets [content] in the Pulse theme with a frozen clock and no animations. */
    fun ComposeContentTestRule.setPulseContent(dark: Boolean = false, now: Instant = demoNow, content: @Composable () -> Unit) {
        setContent {
            CompositionLocalProvider(LocalPulseClock provides PulseClock(now = { now }, ticks = false)) {
                PulseTheme(darkTheme = dark, reduceMotion = true) { content() }
            }
        }
    }

    fun ComposeContentTestRule.setHub(
        environment: StrengthAppEnvironment,
        dark: Boolean = false,
        now: Instant = demoNow,
        onStart: (WorkoutTemplate?) -> Unit = {},
        onResume: () -> Unit = {},
    ) {
        setPulseContent(dark, now) { StrengthHubScreen(environment, onStart, onResume) }
    }

    // region Interaction and capture helpers for the screenshot tests

    private fun SemanticsNodeInteraction.scrollIfNeeded(): SemanticsNodeInteraction {
        val visible = runCatching { assertIsDisplayed() }.isSuccess
        return if (visible) this else performScrollTo()
    }

    fun ComposeContentTestRule.clickText(text: String) {
        onNodeWithText(text).scrollIfNeeded().performClick()
        waitForIdle()
    }

    fun ComposeContentTestRule.clickDescription(description: String) {
        onNodeWithContentDescription(description).scrollIfNeeded().performClick()
        waitForIdle()
    }

    /** A template row of the hub or of "See All" (the name alone also matches the recent workouts of the same name). */
    fun ComposeContentTestRule.clickTemplate(name: String) {
        onNode(hasClickAction() and hasText(name) and hasText("exercises", substring = true)).scrollIfNeeded().performClick()
        waitForIdle()
    }

    /**
     * A sheet drawn over [background] the way a modal bottom sheet looks (scrim, rounded top, grabber). The sheet window itself cannot
     * be captured, so the screenshots render the sheets' content composables inside this frame.
     */
    @Composable
    fun SheetPreview(container: Color, background: @Composable () -> Unit, content: @Composable () -> Unit) {
        Box(Modifier.fillMaxSize()) {
            background()
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.32f)))
            Column(
                Modifier
                    .align(Alignment.BottomCenter)
                    .padding(top = 44.dp)
                    .widthIn(max = 640.dp)
                    .fillMaxSize()
                    .background(container, RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)),
            ) {
                Box(
                    Modifier
                        .align(Alignment.CenterHorizontally)
                        .padding(vertical = 10.dp)
                        .size(width = 32.dp, height = 4.dp)
                        .background(PulseTheme.colors.inkTertiary, RoundedCornerShape(2.dp)),
                )
                content()
            }
        }
    }

    // endregion
}
