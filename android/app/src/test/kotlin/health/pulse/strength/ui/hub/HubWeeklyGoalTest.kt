package health.pulse.strength.ui.hub

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.DemoRecovery
import health.pulse.strength.ui.hub.HubTestSupport.fixLocale
import health.pulse.strength.ui.hub.HubTestSupport.setPulseContent
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The weekly goal under "This Week": the number the "Sessions" figure counts to, and the stepper that changes it. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class HubWeeklyGoalTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()

    @Before fun setUp() = fixLocale()

    private val actions = HubActions(push = {}, pop = {}, requestStart = {}, resume = {}, edit = {})

    private fun showHome(goal: Int, onChange: ((Int) -> Unit)?, store: StrengthStore = HubTestSupport.environment().store) {
        val time = HubTime(LocalDate.of(2026, 1, 17), ZoneId.of("UTC"), DayOfWeek.SUNDAY)
        // Read outside the composition: the test shows the data as it is now and does not follow later changes.
        val data = store.data.value
        rule.setPulseContent {
            HubHome(
                store = store,
                recovery = DemoRecovery.provider,
                home = homeData(data, runningTemplateID = null),
                time = time,
                actions = actions,
                weeklyGoal = goal,
                onWeeklyGoalChange = onChange,
            )
        }
        rule.waitForIdle()
    }

    @Test
    fun theSessionsFigureCountsToTheGoal() {
        showHome(goal = 6, onChange = null)
        rule.onNodeWithText("of 6", substring = true).performScrollTo().assertExists()
    }

    @Test
    fun theStepperShowsTheGoalAndChangesItByOne() {
        val changes = mutableListOf<Int>()
        showHome(goal = 4, onChange = { changes += it })
        rule.onNodeWithText("Weekly goal").performScrollTo().assertExists()
        rule.onNodeWithText("4 workouts a week").assertExists()
        rule.onNodeWithContentDescription("More workouts per week").performClick()
        rule.onNodeWithContentDescription("Fewer workouts per week").performClick()
        assertThat(changes).containsExactly(5, 3).inOrder()
    }

    @Test
    fun theGoalStaysBetweenOneAndSeven() {
        showHome(goal = 1, onChange = {})
        rule.onNodeWithText("1 workout a week").performScrollTo().assertExists()
        rule.onNodeWithContentDescription("Fewer workouts per week").assertIsNotEnabled()
        rule.onNodeWithContentDescription("More workouts per week").assertIsEnabled()
    }

    @Test
    fun aGoalOfSevenCannotGoHigher() {
        showHome(goal = 7, onChange = {})
        rule.onNodeWithText("7 workouts a week").performScrollTo().assertExists()
        rule.onNodeWithContentDescription("More workouts per week").assertIsNotEnabled()
    }

    @Test
    fun withoutSettingsThereIsNoStepper() {
        showHome(goal = 4, onChange = null)
        rule.onNodeWithText("Weekly goal").assertDoesNotExist()
    }
}
