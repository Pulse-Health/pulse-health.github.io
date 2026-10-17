package health.pulse.strength.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.StrengthAppEnvironment
import health.pulse.strength.core.FileStrengthPersistence
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.ui.active.ClockHandle
import health.pulse.strength.ui.active.TestScreenTheme
import health.pulse.strength.ui.active.tagged
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The first run of a real install through the real root: an empty hub, an empty workout, an exercise from the library, a logged set,
 * finish, the summary and the hub afterwards. The store is built the way [StrengthAppEnvironment.live] builds it (nothing seeded, no
 * invented "previous" results), so this is what a user sees after installing the app from Google Play.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class FirstRunFlowTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val productionLikeEnvironment: StrengthAppEnvironment by lazy {
        val persistence = FileStrengthPersistence.temporary()
        val store = StrengthStore(persistence, seedDemoData = false, usesLibraryHistory = false)
        StrengthAppEnvironment.forParts(persistence, store, WorkoutController(store, persistence))
    }

    private fun show(environment: StrengthAppEnvironment) {
        rule.setContent { TestScreenTheme(ClockHandle()) { PulseStrengthRoot(environment) } }
        rule.waitForIdle()
    }

    private fun click(text: String) {
        rule.onNodeWithText(text).performScrollTo().performClick()
        rule.waitForIdle()
    }

    /** For buttons of dialogs and sheets, which are not inside a scrolling list. */
    private fun clickPlain(text: String) {
        rule.onNodeWithText(text).performClick()
        rule.waitForIdle()
    }

    private val isSetCheck = SemanticsMatcher("is a set check") { node ->
        node.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("set-check-") == true
    }

    @Test
    fun emptyInstallStartsLogsAndFinishesAWorkout() {
        val environment = productionLikeEnvironment
        val store = environment.store
        val controller = environment.controller
        assertThat(store.templates).isEmpty()
        assertThat(store.history).isEmpty()
        show(environment)

        // The hub of a new install invites the user to plan, and does not claim any history.
        rule.onNodeWithText("Plan your training").performScrollTo().assertIsDisplayed()
        rule.onNodeWithText("Create Your First Template").assertIsDisplayed()
        rule.onAllNodesWithText("Recent Workouts").assertCountEquals(0)

        // An empty workout opens the workout screen with its empty state.
        click("Start Empty Workout")
        assertThat(controller.state.value).isNotNull()
        rule.tagged("active-empty").assertIsDisplayed()

        // The exercise comes from the real picker sheet.
        rule.tagged("empty-add").performClick()
        rule.waitForIdle()
        click("Barbell bench press")
        clickPlain("Add 1 exercise")
        val workout = controller.state.value!!
        assertThat(workout.exercises.map { it.exercise.id }).containsExactly("bench")
        rule.tagged("active-exercise-name").assertIsDisplayed()

        // A new install has no "previous" results for a library exercise: the lifter's own history is empty.
        assertThat(workout.exercises[0].exercise.previousBestE1RM).isEqualTo(0.0)
        assertThat(workout.exercises[0].exercise.previousSets).isEmpty()

        // Log the first set from the screen: the set gets its numbers, then the check circle ticks it.
        val exercise = workout.exercises[0]
        val set = exercise.sets[0]
        controller.send(WorkoutAction.SetWeight(exercise.id, set.id, 60.0))
        controller.send(WorkoutAction.SetReps(exercise.id, set.id, 8))
        rule.waitForIdle()
        rule.onAllNodes(isSetCheck, useUnmergedTree = true)[0].performClick()
        rule.waitForIdle()
        assertThat(controller.state.value!!.exercises[0].sets[0].isDone).isTrue()

        // Finishing saves the workout, closes the screen and shows the summary.
        rule.tagged("active-finish").performClick()
        rule.waitForIdle()
        clickPlain("Finish Workout")
        assertThat(controller.state.value).isNull()
        assertThat(store.history).hasSize(1)
        assertThat(store.history[0].loggedSets).isEqualTo(1)
        assertThat(store.history[0].volumeKg).isEqualTo(480.0)
        rule.onNodeWithText("Workout Complete").assertIsDisplayed()
        rule.onAllNodesWithTag("active-title", useUnmergedTree = true).assertCountEquals(0)

        // Done returns to the hub, which now lists the workout.
        clickPlain("Done")
        rule.onAllNodesWithText("Workout Complete").assertCountEquals(0)
        rule.onNodeWithText("Recent Workouts").performScrollTo().assertIsDisplayed()
    }

    @Test
    fun discardingTheOnlyWorkoutLeavesTheHubAsItWas() {
        val environment = productionLikeEnvironment
        show(environment)
        click("Start Empty Workout")
        rule.tagged("active-finish").performClick()
        rule.waitForIdle()
        clickPlain("Discard Workout")
        clickPlain("Discard")
        assertThat(environment.controller.state.value).isNull()
        assertThat(environment.store.history).isEmpty()
        rule.onNodeWithText("Create Your First Template").assertIsDisplayed()
    }
}
