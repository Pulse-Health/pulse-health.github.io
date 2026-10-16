package health.pulse.strength.ui.active

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.performClick
import health.pulse.strength.core.WorkoutAction
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A long exercise: the next pending set is scrolled into view when the screen opens and after every logged set, whether the set
 * rows scroll inside the card (a normal phone) or the whole page scrolls (a short window).
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
abstract class ActiveNextSetVisibilityScenarios {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    /** Incline press with 25 sets, the first 14 logged long ago (no rest running). */
    private fun longExercise(): ActiveFixture {
        val fixture = ActiveFixture()
        fixture.send(WorkoutAction.GoTo(1))
        val exercise = fixture.exerciseID(1)
        repeat(22) { fixture.send(WorkoutAction.AddSet(exercise)) }
        fixture.log(1, 0..13, secondsAgo = 400)
        fixture.send(WorkoutAction.SkipRest)
        return fixture
    }

    private fun nextRowID(fixture: ActiveFixture) = fixture.presentation().card!!.rows.first { it.isNext }.id

    @Test
    fun nextSetIsInViewWhenTheScreenOpens() {
        val fixture = longExercise()
        rule.showActiveScreen(fixture)
        rule.tagged("set-row-${nextRowID(fixture)}").assertIsDisplayed()
    }

    @Test
    fun nextSetStaysInViewAsSetsAreLogged() {
        val fixture = longExercise()
        rule.showActiveScreen(fixture)
        repeat(3) {
            val next = nextRowID(fixture)
            rule.tagged("set-check-$next").performClick()
            rule.waitForIdle()
            rule.tagged("set-row-${nextRowID(fixture)}").assertIsDisplayed()
        }
    }

    @Test
    fun anotherExerciseStartsAtItsNextSet() {
        val fixture = longExercise()
        rule.showActiveScreen(fixture)
        fixture.send(WorkoutAction.GoTo(0))
        rule.waitForIdle()
        rule.tagged("set-row-${nextRowID(fixture)}").assertIsDisplayed()
    }
}

/** A normal phone: the set rows scroll inside the card. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ActiveNextSetVisibilityPhoneTest : ActiveNextSetVisibilityScenarios()

/** A short window: the page scrolls. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h640dp-xhdpi")
class ActiveNextSetVisibilitySmallPhoneTest : ActiveNextSetVisibilityScenarios()

/** Big text on a small phone: the page scrolls and the header scrolls with it. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h640dp-xhdpi", fontScale = 2.0f)
class ActiveNextSetVisibilityBigTextTest : ActiveNextSetVisibilityScenarios()
