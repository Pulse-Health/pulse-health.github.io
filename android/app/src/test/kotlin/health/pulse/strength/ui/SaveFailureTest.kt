package health.pulse.strength.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.StrengthAppEnvironment
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.FileStrengthPersistence
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.ui.active.ClockHandle
import health.pulse.strength.ui.active.TestScreenTheme
import health.pulse.strength.ui.active.tagged
import java.io.File
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A full phone: what the user sees when the workout cannot be written. A workout that vanished silently was the finding; now a banner
 * says so while it is running, and Finish says so when the history cannot be written (the sets are kept on disk for "Try again").
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class SaveFailureTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val persistence = FileStrengthPersistence.temporary()
    private val store = StrengthStore(persistence, seedDemoData = false, usesLibraryHistory = false)
    private val controller = WorkoutController(store, persistence)
    private val environment = StrengthAppEnvironment.forParts(persistence, store, controller)

    private fun startAndLogASet() {
        controller.startWorkout(null, "Push day")
        controller.send(WorkoutAction.AddExercises(listOf(ExerciseLibrary.exercise("bench")!!)))
        val entry = controller.state.value!!.exercises[0]
        controller.send(WorkoutAction.LogSet(entry.id, entry.sets[0].id))
    }

    /** Makes a data file unwritable: a non-empty folder with its name cannot be replaced by the atomic write. */
    private fun block(name: String): File {
        val blocker = File(persistence.directory, name)
        if (blocker.isFile) assertThat(blocker.delete()).isTrue()
        assertThat(blocker.mkdirs()).isTrue()
        File(blocker, "keep").writeText("x")
        return blocker
    }

    private fun show() {
        rule.setContent { TestScreenTheme(ClockHandle()) { PulseStrengthRoot(environment) } }
        rule.waitForIdle()
    }

    private fun openWorkout() {
        rule.tagged("in-progress-bar").performClick()
        rule.waitForIdle()
    }

    private fun saveWarnings() = rule.onAllNodesWithTag("save-warning", useUnmergedTree = true)

    @Test
    fun aBannerSaysSoWhileTheRunningWorkoutCannotBeSavedAndGoesWhenItCan() {
        startAndLogASet()
        val blocker = block("active-workout.json")
        controller.send(WorkoutAction.AdjustRest(15))   // any change: the save of the running workout fails now
        assertThat(controller.persistenceError.value).isNotNull()
        show()
        openWorkout()
        saveWarnings().assertCountEquals(1)
        rule.onNodeWithText("Can't save your workout. The phone may be out of storage; free up some space. Your sets stay on screen.")
            .assertIsDisplayed()

        assertThat(blocker.deleteRecursively()).isTrue()
        controller.send(WorkoutAction.AdjustRest(15))
        rule.waitForIdle()
        saveWarnings().assertCountEquals(0)
    }

    @Test
    fun noBannerWhenEverythingIsSaved() {
        startAndLogASet()
        show()
        openWorkout()
        saveWarnings().assertCountEquals(0)
    }

    @Test
    fun finishingWithoutBeingAbleToSaveTellsTheUserAndTryAgainBringsTheWorkoutBack() {
        startAndLogASet()
        val blocker = block("history.json")
        show()
        openWorkout()

        rule.tagged("active-finish").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Finish Workout").performClick()
        rule.waitForIdle()

        // The summary appears as usual, but the user is told that the workout is not in the history.
        assertThat(controller.state.value).isNull()
        rule.onNodeWithText("Workout not saved").assertIsDisplayed()
        assertThat(persistence.loadHistory()).isEmpty()

        // Room again: "Try again" loads the workout back from disk (its sets were never deleted) and shows it.
        assertThat(blocker.deleteRecursively()).isTrue()
        rule.onNodeWithText("Try again").performClick()
        rule.waitForIdle()
        assertThat(controller.state.value).isNotNull()
        rule.onAllNodesWithTag("active-title", useUnmergedTree = true).assertCountEquals(1)

        // Finishing again saves it, once.
        rule.tagged("active-finish").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Finish Workout").performClick()
        rule.waitForIdle()
        assertThat(controller.lastPersistenceError).isNull()
        assertThat(persistence.loadHistory().map { it.name }).containsExactly("Push day")
        assertThat(store.history).hasSize(1)
        rule.onAllNodesWithText("Workout not saved").assertCountEquals(0)
    }

    @Test
    fun notNowKeepsTheSummaryAndTheWorkoutOnDiskForTheNextLaunch() {
        startAndLogASet()
        block("history.json")
        show()
        openWorkout()
        rule.tagged("active-finish").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Finish Workout").performClick()
        rule.waitForIdle()

        rule.onNodeWithText("Not now").performClick()
        rule.waitForIdle()
        rule.onAllNodesWithText("Workout not saved").assertCountEquals(0)
        rule.onNodeWithText("Workout Complete").assertIsDisplayed()
        assertThat(persistence.loadActiveWorkout()?.name).isEqualTo("Push day")
    }

    private fun androidx.compose.ui.test.junit4.ComposeContentTestRule.onAllNodesWithText(text: String) =
        onAllNodes(androidx.compose.ui.test.hasText(text))
}
