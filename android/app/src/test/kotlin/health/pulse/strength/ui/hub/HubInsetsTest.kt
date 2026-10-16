package health.pulse.strength.ui.hub

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import androidx.compose.ui.unit.dp
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.ui.ScreenshotSupport.capture
import health.pulse.strength.ui.hub.HubTestSupport.clickTemplate
import health.pulse.strength.ui.hub.HubTestSupport.clickText
import health.pulse.strength.ui.hub.HubTestSupport.fixLocale
import health.pulse.strength.ui.hub.HubTestSupport.setHub
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The hub drawn edge to edge: with a status bar and a navigation bar (and a keyboard) the content must clear them, never
 * with fixed bar heights. The insets are dispatched to the activity window like the system does after `enableEdgeToEdge()`.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class HubInsetsTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()

    private val density get() = rule.activity.resources.displayMetrics.density
    private fun px(dp: Int) = (dp * density).toInt()

    @Before fun setUp() = fixLocale()

    private fun dispatchInsets(statusDp: Int = 0, navigationDp: Int = 0, imeDp: Int = 0) {
        rule.runOnUiThread {
            WindowCompat.setDecorFitsSystemWindows(rule.activity.window, false)
            val insets = WindowInsetsCompat.Builder()
                .setInsets(WindowInsetsCompat.Type.statusBars(), Insets.of(0, px(statusDp), 0, 0))
                .setInsets(WindowInsetsCompat.Type.navigationBars(), Insets.of(0, 0, 0, px(navigationDp)))
                .setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, px(imeDp)))
                .setVisible(WindowInsetsCompat.Type.ime(), imeDp > 0)
                .build()
            ViewCompat.dispatchApplyWindowInsets(rule.activity.window.decorView, insets)
        }
        rule.waitForIdle()
    }

    private fun show() {
        rule.setHub(HubTestSupport.environment())
        rule.waitForIdle()
    }

    @Test
    fun topBarClearsTheStatusBar() {
        show()
        val before = rule.onNodeWithContentDescription("Settings").getBoundsInRoot().top
        dispatchInsets(statusDp = 40)
        val after = rule.onNodeWithContentDescription("Settings").getBoundsInRoot().top
        assertThat((after - before).value).isWithin(1f).of(40f)
        rule.capture("hub-insets-home-status-nav")
    }

    @Test
    fun pushedScreensClearTheStatusBarToo() {
        show()
        rule.clickText("Exercise Library")
        val before = rule.onNodeWithContentDescription("Back").getBoundsInRoot().top
        dispatchInsets(statusDp = 40, navigationDp = 48)
        val after = rule.onNodeWithContentDescription("Back").getBoundsInRoot().top
        assertThat((after - before).value).isWithin(1f).of(40f)
    }

    @Test
    fun startBarOfATemplateClearsTheNavigationBar() {
        show()
        rule.clickTemplate("Upper A · Push")
        val rootHeight = rule.onRoot().getBoundsInRoot().bottom
        val before = rule.onNodeWithText("Start Workout").getBoundsInRoot().bottom
        dispatchInsets(statusDp = 24, navigationDp = 48)
        val after = rule.onNodeWithText("Start Workout").getBoundsInRoot().bottom
        assertThat(after.value).isAtMost((rootHeight - 48.dp).value)
        assertThat((before - after).value).isGreaterThan(40f)
        rule.capture("hub-insets-template-detail")
    }

    @Test
    fun theLastRowOfTheHomeScreenScrollsAboveTheNavigationBar() {
        show()
        dispatchInsets(statusDp = 24, navigationDp = 48)
        rule.onNodeWithText("Exercise Library").performScrollTo()
        rule.onRoot().performTouchInput { repeat(3) { swipeUp() } } // all the way to the end of the page
        rule.waitForIdle()
        val rootHeight = rule.onRoot().getBoundsInRoot().bottom
        val bottom = rule.onNodeWithText("Exercise Library").getBoundsInRoot().bottom
        assertThat(bottom.value).isAtMost((rootHeight - 48.dp - 16.dp).value)
        rule.capture("hub-insets-home-bottom")
    }

    @Test
    fun theKeyboardPushesTheBottomOfALongListUp() {
        show()
        rule.clickText("Exercise Library")
        dispatchInsets(navigationDp = 48, imeDp = 300)
        // The search field stays where it is (top of the screen), the list area ends above the keyboard.
        val field = rule.onNodeWithText("Search exercises").getBoundsInRoot()
        val rootHeight = rule.onRoot().getBoundsInRoot().bottom
        assertThat(field.bottom.value).isAtMost((rootHeight - 300.dp).value)
    }

    @Test
    fun sidesClearADisplayCutoutInLandscape() {
        show()
        rule.runOnUiThread {
            WindowCompat.setDecorFitsSystemWindows(rule.activity.window, false)
            val insets = WindowInsetsCompat.Builder()
                .setInsets(WindowInsetsCompat.Type.displayCutout(), Insets.of(px(48), 0, 0, 0))
                .build()
            ViewCompat.dispatchApplyWindowInsets(rule.activity.window.decorView, insets)
        }
        rule.waitForIdle()
        val left = rule.onNodeWithText("Start Empty Workout").getBoundsInRoot().left
        assertThat(left.value).isAtLeast(48f + 16f)
    }
}
