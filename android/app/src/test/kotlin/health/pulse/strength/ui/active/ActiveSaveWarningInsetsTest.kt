package health.pulse.strength.ui.active

import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.unit.toSize
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.WorkoutAction
import java.io.File
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The "Can't save your workout" warning keeps clear of the status bar, the navigation bar and display cut-outs: at the top when
 * nothing pinned sits above it (the header scrolls with the page on a short window or with big text), at the sides always.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
abstract class ActiveSaveWarningScenarios {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    /** Shows the screen with the given system bars (dp), then makes the workout unsavable and changes it, so the warning comes up. */
    internal fun showUnsavable(topDp: Int, bottomDp: Int, leftDp: Int = 0, rightDp: Int = 0): ActiveFixture {
        val fixture = ActiveFixture()
        fixture.log(0, 0..2, secondsAgo = 78)
        rule.showActiveScreen(fixture)
        rule.applySystemBars(topDp, bottomDp, leftDp, rightDp)
        // A non-empty folder with the file's name cannot be replaced by the atomic write: the next save fails.
        val blocker = File(fixture.persistence.directory, "active-workout.json")
        if (blocker.isFile) assertThat(blocker.delete()).isTrue()
        assertThat(blocker.mkdirs()).isTrue()
        File(blocker, "keep").writeText("x")
        fixture.send(WorkoutAction.AdjustRest(15))
        rule.waitForIdle()
        assertThat(fixture.controller.persistenceError.value).isNotNull()
        return fixture
    }

    /** The node's place in the root, not cut by the scroll area it may be in. */
    protected fun bounds(tag: String): Rect = rule.tagged(tag).fetchSemanticsNode().let { Rect(it.positionInRoot, it.size.toSize()) }

    protected fun dp(px: Float): Float = px / rule.density.density
}

/** A small phone at 200 % text: the header scrolls away with the page, so the warning is the first thing under the status bar. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h640dp-xhdpi", fontScale = 2.0f)
class ActiveSaveWarningBigTextTest : ActiveSaveWarningScenarios() {
    @Test
    fun warningStartsBelowTheStatusBar() {
        showUnsavable(topDp = 28, bottomDp = 24)
        assertThat(dp(bounds("save-warning").top)).isAtLeast(28f)
        // The page below does not leave the status bar's room empty a second time: its header follows right under the warning.
        assertThat(dp(bounds("active-minimise").top - bounds("save-warning").bottom)).isLessThan(28f)
    }

    @Test
    fun warningKeepsClearOfCutOutsAtTheSides() {
        showUnsavable(topDp = 28, bottomDp = 24, leftDp = 20, rightDp = 20)
        val warning = bounds("save-warning")
        // 20 dp cut-out + the 16 dp margin on each side.
        assertThat(dp(warning.left)).isAtLeast(36f)
        assertThat(dp(warning.right)).isAtMost(360f - 36f)
    }
}

/** A normal phone: the header is pinned above the warning, which then only needs the sides. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ActiveSaveWarningPhoneTest : ActiveSaveWarningScenarios() {
    @Test
    fun warningSitsUnderThePinnedHeaderAndClearOfCutOuts() {
        showUnsavable(topDp = 28, bottomDp = 24, leftDp = 24, rightDp = 24)
        val warning = bounds("save-warning")
        val header = bounds("active-sets")
        assertThat(warning.top).isAtLeast(header.top + header.height)
        assertThat(dp(warning.left)).isAtLeast(24f + 16f)
        assertThat(dp(warning.right)).isAtMost(411f - 24f - 16f)
    }
}

/** A phone held sideways, too narrow for the dock beside the card: the header scrolls, the bar is on the left. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w640dp-h360dp-land-xxhdpi")
class ActiveSaveWarningLandscapeTest : ActiveSaveWarningScenarios() {
    @Test
    fun warningKeepsClearOfTheBarAndTheStatusBar() {
        showUnsavable(topDp = 24, bottomDp = 0, leftDp = 48)
        val warning = bounds("save-warning")
        assertThat(dp(warning.top)).isAtLeast(24f)
        assertThat(dp(warning.left)).isAtLeast(48f + 16f)
    }
}
