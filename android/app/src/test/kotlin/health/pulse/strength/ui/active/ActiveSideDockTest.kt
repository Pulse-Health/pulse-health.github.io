package health.pulse.strength.ui.active

import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
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
 * Where the rest dock goes in a landscape window: beside the card only while the card keeps room for its rows, and then with the
 * window's insets counted once (the start inset in front of the card, the end inset inside the side pane).
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
abstract class ActiveSideDockScenarios {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    /** Bench with its warm-ups and the working set logged, resting, with a removed exercise to undo: dock and toast are both up. */
    private fun busyFixture() = ActiveFixture().also {
        it.log(0, 0..2, secondsAgo = 78)
        it.send(WorkoutAction.RemoveExercise(it.exerciseID(5)))
    }

    protected fun show(topDp: Int = 24, bottomDp: Int = 0, leftDp: Int = 0, rightDp: Int = 0) {
        rule.showActiveScreen(busyFixture())
        rule.applySystemBars(topDp, bottomDp, leftDp, rightDp)
    }

    /** The node's place in the root, not cut by the scroll area it may be in. */
    protected fun bounds(tag: String): Rect = rule.tagged(tag).fetchSemanticsNode().let { Rect(it.positionInRoot, it.size.toSize()) }

    protected fun dp(px: Float): Float = px / rule.density.density

    /** The dock is in the pane beside the card (not under it, where it would be as wide as the window allows). */
    protected fun assertDockBesideCard() {
        assertThat(bounds("rest-dock").left).isAtLeast(bounds("active-card").right)
        assertThat(dp(bounds("rest-dock").width)).isAtMost(340.5f)
    }

    protected fun assertDockUnderCard() {
        assertThat(dp(bounds("rest-dock").width)).isGreaterThan(340.5f)
    }
}

/** The 891 x 411 dp phone held sideways with a 48 dp bar on the right: the pane takes the bar, the card must not give it up again. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
class ActiveSideDockBarOnTheEndTest : ActiveSideDockScenarios() {
    @Test
    fun theEndInsetIsTakenOnlyByThePane() {
        show(rightDp = 48)
        assertDockBesideCard()
        // 891 dp minus the 354 dp pane, the page's 16 dp margins on both sides: nothing taken for the bar (it is inside the pane).
        assertThat(dp(bounds("active-card").width)).isWithin(1f).of(891f - 354f - 32f)
        // The dock stays clear of the bar.
        assertThat(dp(bounds("rest-dock").right)).isAtMost(891f - 48f)
        // The undo toast spans the page the same way (its node starts inside the 16 dp and 6 dp padding of the toast).
        assertThat(dp(bounds("undo-toast").left)).isWithin(1f).of(16f + 16f)
        assertThat(dp(bounds("undo-toast").right)).isWithin(1f).of(891f - 354f - 16f - 6f)
    }

    @Test
    fun theStartInsetIsTakenByThePage() {
        show(leftDp = 48, rightDp = 0)
        assertDockBesideCard()
        assertThat(dp(bounds("active-card").left)).isWithin(1f).of(48f + 16f)
        assertThat(dp(bounds("active-card").width)).isWithin(1f).of(891f - 354f - 48f - 32f)
    }

    @Test
    fun barsOnBothSidesCountOnceEach() {
        show(leftDp = 48, rightDp = 48)
        assertDockBesideCard()
        assertThat(dp(bounds("active-card").width)).isWithin(1f).of(891f - 354f - 48f - 32f)
    }
}

/** 780 x 360 dp (a tall phone held sideways): the card keeps 394 dp beside the dock, enough for its rows. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w780dp-h360dp-land-xxhdpi")
class ActiveSideDockJustRoomyTest : ActiveSideDockScenarios() {
    @Test
    fun dockIsBesideTheCard() {
        show()
        assertDockBesideCard()
        assertThat(dp(bounds("active-card").width)).isAtLeast(380f)
    }
}

/** 740 x 360 dp: beside the dock the card would get 354 dp, so the dock goes under it instead. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w740dp-h360dp-land-xxhdpi")
class ActiveSideDockTooNarrowTest : ActiveSideDockScenarios() {
    @Test
    fun dockStaysUnderTheCard() {
        show()
        assertDockUnderCard()
        assertThat(dp(bounds("active-card").width)).isAtLeast(380f)
    }
}

/** 640 x 360 dp with a bar on the right (the case that lost its check circles): no dock beside the card, and the card is the full page. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w640dp-h360dp-land-xxhdpi")
class ActiveSideDockShortLandscapeTest : ActiveSideDockScenarios() {
    @Test
    fun dockStaysUnderTheCardAndTheCardUsesTheWindow() {
        show(rightDp = 48)
        assertDockUnderCard()
        assertThat(dp(bounds("active-card").width)).isWithin(1f).of(640f - 48f - 32f)
    }
}
