package health.pulse.strength.ui.active

import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.toSize
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.WorkoutAction
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The set rows in windows that are wide but not roomy, where the rest dock beside the card once left a card too narrow for its rows
 * (the Previous column went and the check circle was squeezed out). Wherever the window is, a set must keep its 48 dp check circle.
 * The concrete subclasses set the window and its system bars (in dp) through `@Config`.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
abstract class ActiveSetRowFitScenarios(
    private val topDp: Int = 24,
    private val bottomDp: Int = 0,
    private val leftDp: Int = 0,
    private val rightDp: Int = 0,
    /** Whether the window has room for the Previous column (below about 300 dp of card it is hidden to keep the other columns whole). */
    private val showsPrevious: Boolean = true,
) {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    /** Bench with its two warm-ups logged; the first working set is logged after the window is set up, so the dock comes up and the next set is shown. */
    private fun restingFixture() = ActiveFixture().also { it.log(0, 0..1) }

    private fun show(fixture: ActiveFixture) {
        rule.showActiveScreen(fixture)
        rule.applySystemBars(topDp, bottomDp, leftDp, rightDp)
        fixture.log(0, 2..2, secondsAgo = 78)
        rule.waitForIdle()
    }

    private fun px(dp: Int) = with(rule.density) { dp.dp.toPx() }

    /** The node's place in the root, not cut by the scroll area it may be in. */
    private fun bounds(tag: String): Rect = rule.tagged(tag).fetchSemanticsNode().let { Rect(it.positionInRoot, it.size.toSize()) }

    @Test
    fun everySetKeepsItsWholeCheckCircle() {
        val fixture = restingFixture()
        show(fixture)
        val rows = fixture.presentation().card!!.rows
        for (row in rows) {
            rule.tagged("set-check-${row.id}").assertWidthIsAtLeast(48.dp)
            // It sits at the end of its row, after the reps cell.
            val checkBounds = bounds("set-check-${row.id}")
            val rowBounds = bounds("set-row-${row.id}")
            val repsBounds = bounds("set-reps-${row.id}")
            assertThat(checkBounds.right).isAtMost(rowBounds.right + 1f)
            assertThat(checkBounds.left).isAtLeast(repsBounds.right - 1f)
        }
        rule.tagged("set-check-${rows.first { it.isNext }.id}").assertIsDisplayed()
    }

    @Test
    fun theNextSetCanBeLoggedFromItsCheckCircleWithoutTheDock() {
        val fixture = restingFixture()
        show(fixture)
        fixture.send(WorkoutAction.SkipRest)
        rule.waitForIdle()
        val next = fixture.presentation().card!!.rows.first { it.isNext }
        rule.tagged("set-check-${next.id}").assertIsDisplayed().assertWidthIsAtLeast(48.dp)
    }

    @Test
    fun previousColumnIsKeptOnlyWhereThereIsRoomForIt() {
        val fixture = restingFixture()
        show(fixture)
        // A hidden column is not placed, so its title is not in the semantics tree at all.
        val titles = rule.onAllNodes(hasText("PREVIOUS"), useUnmergedTree = true).fetchSemanticsNodes()
        if (showsPrevious) {
            assertThat(titles).hasSize(1)
            assertThat(titles.single().size.width).isAtLeast(px(44).toInt())
        } else {
            assertThat(titles.filter { it.size.width > 0 }).isEmpty()
        }
    }
}

/** A phone held sideways (640 x 360 dp) with a three-button bar on the right: too narrow for the dock beside the card. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w640dp-h360dp-land-xxhdpi")
class ActiveShortLandscapeSetRowTest : ActiveSetRowFitScenarios(topDp = 24, rightDp = 48)

/** The same window with the bar on the left. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w640dp-h360dp-land-xxhdpi")
class ActiveShortLandscapeLeftBarSetRowTest : ActiveSetRowFitScenarios(topDp = 24, leftDp = 48)

/** A 600 x 480 dp window (a split screen or a resized window on a large screen). */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w600dp-h480dp-xhdpi")
class ActiveSplitWindowSetRowTest : ActiveSetRowFitScenarios(topDp = 24, bottomDp = 24)

/** The wide landscape phone (891 x 411 dp) with a bar on both sides: the dock is beside the card and the card is still roomy. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
class ActiveWideLandscapeSetRowTest : ActiveSetRowFitScenarios(topDp = 24, leftDp = 48, rightDp = 48)

/** A 320 dp wide phone at 200 % text: the Previous column has no room left (below 44 dp it is hidden), the check circle stays. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w320dp-h640dp-xhdpi", fontScale = 2.0f)
class ActiveNarrowPhoneSetRowTest : ActiveSetRowFitScenarios(showsPrevious = false, bottomDp = 24)

/** A 280 dp wide window (a narrow split screen): even the badge and the value cells give way, the check circle does not. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w280dp-h560dp-xhdpi")
class ActiveNarrowestWindowSetRowTest : ActiveSetRowFitScenarios(showsPrevious = false, bottomDp = 24)
