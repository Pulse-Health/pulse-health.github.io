package health.pulse.strength.ui.hub

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.ui.hub.HubTestSupport.clickDescription
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

/** Measured layout of the hub on the window sizes and font scales of the design brief (the pictures are in the screenshot classes). */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class HubLayoutTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()

    @Before fun setUp() = fixLocale()

    private fun show() {
        rule.setHub(HubTestSupport.environment())
        rule.waitForIdle()
    }

    private fun bounds(text: String) = rule.onNodeWithText(text).getUnclippedBoundsInRoot()

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
    fun aShortLandscapeWindowKeepsTheTitleInTheBarAndStartsTheContentHigh() {
        show()
        rule.onAllNodesWithText("Strength").assertCountEquals(1)
        rule.onNodeWithText("Today · Recommended").assertIsDisplayed()
        assertThat(bounds("Today · Recommended").top.value).isLessThan(120f)
        // Two columns: the recovery section sits to the right of the recommended card.
        assertThat(bounds("Muscle Recovery").left.value).isGreaterThan(bounds("Today · Recommended").right.value)
    }

    @Test
    @Config(qualifiers = "w800dp-h1280dp-xhdpi")
    fun aTabletInPortraitCentresOneColumnOfAtMost640dp() {
        show()
        val row = bounds("Start Empty Workout")
        assertThat(row.left.value).isAtLeast(80f)
        assertThat(row.right.value).isAtMost(720f)
        assertThat(bounds("Templates").left.value).isWithin(1f).of(80f) // (800 - 640) / 2
        assertThat(bounds("Muscle Recovery").left.value).isWithin(1f).of(80f)
        // The widest element (the recovery grid) spans the column: no wider than 640 dp.
        rule.onNodeWithText("This Week").performScrollTo()
        assertThat(bounds("Sessions").left.value).isAtLeast(80f)
        assertThat(bounds("Volume").right.value).isAtMost(720f)
    }

    @Test
    @Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
    fun aTabletInLandscapeUsesTwoColumns() {
        show()
        assertThat(bounds("Muscle Recovery").left.value).isGreaterThan(bounds("Templates").right.value)
        // Both columns together (2 x 560 dp and a 24 dp gap) stay centred: (1280 - 1144) / 2 on each side.
        assertThat(bounds("Strength").left.value).isWithin(1f).of(68f)
    }

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi", fontScale = 2.0f)
    fun everythingStaysReachableOnTheSmallestPhoneAtTwiceTheFontSize() {
        show()
        // Figures are stacked one per line instead of side by side.
        rule.onNodeWithText("Sessions").performScrollTo()
        val sessions = bounds("Sessions")
        val sets = bounds("Sets")
        assertThat(sets.top.value).isGreaterThan(sessions.bottom.value)
        assertThat(sets.left.value).isWithin(1f).of(sessions.left.value)
        // The last row opens the library, and the library's rows and filters work.
        rule.clickText("Exercise Library")
        rule.onNodeWithText("Search exercises").assertIsDisplayed()
        rule.onNodeWithText("Ab wheel rollout").assertIsDisplayed()
        rule.clickDescription("Back")
        rule.onNodeWithText("Exercise Library").assertIsDisplayed() // the home screen is back where it was scrolled to
    }

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi", fontScale = 2.0f)
    fun theTemplateScreenKeepsItsStartButtonAndScrollsItsExercises() {
        show()
        rule.clickTemplate("Upper A · Push")
        rule.onNodeWithText("Start Workout").assertIsDisplayed()
        rule.onNodeWithText("Cable crossover").performScrollTo().assertIsDisplayed()
        rule.onNodeWithText("Start Workout").assertIsDisplayed()
        // The bar stays on screen below the list.
        assertThat(bounds("Start Workout").bottom.value).isAtMost(640f)
    }

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi", fontScale = 1.3f)
    fun theRecommendedCardWrapsItsChipsInsteadOfClippingThemOnASmallPhone() {
        show()
        val chest = bounds("Chest 88%")
        val arms = bounds("Arms 79%")
        assertThat(arms.right.value).isAtMost(360f - 32f)
        assertThat(chest.left.value).isAtLeast(32f)
    }
}
