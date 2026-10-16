package health.pulse.strength.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.ui.active.ClockHandle
import health.pulse.strength.ui.active.TestScreenTheme
import health.pulse.strength.ui.active.applySystemBars
import health.pulse.strength.ui.active.tagged
import health.pulse.strength.ui.components.ExerciseMediaStore
import health.pulse.strength.ui.hub.HubTestSupport
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The layers of the root: a hub under a minimised workout clears a navigation bar at the side (landscape with three buttons), and a
 * full-screen layer hides the hub from a screen reader and is announced as a screen.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w640dp-h360dp-land-xxhdpi")
class RootLayersTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Before
    fun pinLocale() = HubTestSupport.fixLocale()

    private fun show(withWorkout: Boolean) {
        val environment = HubTestSupport.environment(seed = true, now = HubTestSupport.demoNow, withActiveWorkout = withWorkout)
        rule.setContent { TestScreenTheme(ClockHandle(HubTestSupport.demoNow)) { PulseStrengthRoot(environment) } }
    }

    private val paneTitles = SemanticsMatcher("has a pane title") { it.config.contains(SemanticsProperties.PaneTitle) }

    @Test
    fun theHubClearsASideNavigationBarWhileAWorkoutIsMinimised() {
        show(withWorkout = true)
        rule.applySystemBars(topDp = 24, bottomDp = 0, rightDp = 48)
        rule.waitForIdle()
        rule.tagged("in-progress-bar").assertIsDisplayed()
        val windowWidth = rule.onRoot().getUnclippedBoundsInRoot().let { it.right - it.left }
        // The "More" button is the right-most control of the hub's top bar.
        val more = rule.onNodeWithContentDescription("More").getUnclippedBoundsInRoot()
        assertThat(more.right).isAtMost(windowWidth - 48.dp)
        val bar = rule.tagged("in-progress-bar").getUnclippedBoundsInRoot()
        assertThat(bar.right).isAtMost(windowWidth - 48.dp)
    }

    @Test
    fun theWorkoutLayerHidesTheHubFromAScreenReaderAndIsAnnounced() {
        show(withWorkout = true)
        rule.onAllNodesWithText("Start Empty Workout").assertCountEquals(1)
        rule.onAllNodes(paneTitles).assertCountEquals(0)

        rule.tagged("in-progress-bar").performClick()
        rule.waitForIdle()
        rule.onAllNodesWithText("Start Empty Workout").assertCountEquals(0)
        rule.onAllNodes(SemanticsMatcher.expectValue(SemanticsProperties.PaneTitle, "Workout")).assertCountEquals(1)

        rule.onNodeWithContentDescription("Minimise workout").performClick()
        rule.waitForIdle()
        rule.onAllNodesWithText("Start Empty Workout").assertCountEquals(1)
    }

    @Test
    fun withoutPhotosATileShowsItsPlaceholderAndNothingClaimsPhotos() {
        val context = androidx.test.core.app.ApplicationProvider.getApplicationContext<android.app.Application>()
        assertThat(ExerciseMediaStore.isShipped(context)).isTrue()   // debug builds and tests carry the placeholder photos
        assertThat(ExerciseMediaStore.frames(context, "bench").hasAny).isTrue()
        assertThat(ExerciseMediaStore.frames(context, "bench", needsSecond = false).second).isNull()
        ExerciseMediaStore.enabled = false
        try {
            assertThat(ExerciseMediaStore.isShipped(context)).isFalse()
            assertThat(ExerciseMediaStore.frames(context, "bench").hasAny).isFalse()
        } finally {
            ExerciseMediaStore.enabled = true
        }
    }
}
