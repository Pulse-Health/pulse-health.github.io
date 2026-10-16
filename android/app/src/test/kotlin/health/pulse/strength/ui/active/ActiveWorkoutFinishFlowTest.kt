package health.pulse.strength.ui.active

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.WorkoutAction
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The Finish button, its confirmation, the "Update template?" question and the discard confirmation. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ActiveWorkoutFinishFlowTest {
    @get:Rule
    val rule = createComposeRule()

    private fun ActiveFixture.loggedWorkout(): ActiveFixture {
        log(0, 0..2)
        send(WorkoutAction.SkipRest)
        return this
    }

    private fun finishButton() = rule.tagged("active-finish")

    @Test
    fun finishAsksForConfirmationAndShowsTheLoggedSetCount() {
        val fixture = ActiveFixture().loggedWorkout()
        rule.showActiveScreen(fixture)

        finishButton().performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Finish workout?").assertExists()
        rule.onNodeWithText("17 sets are not logged yet and will be left out.").assertExists()
        rule.onNodeWithText("Finish Workout").assertExists()
        rule.onNodeWithText("Keep Training").assertExists()
        rule.onNodeWithText("Discard Workout").assertExists()
    }

    @Test
    fun keepTrainingClosesTheDialogAndKeepsTheWorkout() {
        val fixture = ActiveFixture().loggedWorkout()
        val events = ScreenEvents()
        rule.showActiveScreen(fixture, events)

        finishButton().performClick()
        rule.onNodeWithText("Keep Training").performClick()
        rule.waitForIdle()
        rule.onAllNodesWithText("Finish workout?").assertCountEquals(0)
        assertThat(fixture.controller.state.value).isNotNull()
        assertThat(events.finished).isEmpty()
    }

    @Test
    fun finishWorkoutRecordsTheWorkoutAndReportsIt() {
        val fixture = ActiveFixture().loggedWorkout()
        val events = ScreenEvents()
        rule.showActiveScreen(fixture, events)
        val historyBefore = fixture.store.history.size

        finishButton().performClick()
        rule.onNodeWithText("Finish Workout").performClick()
        rule.waitForIdle()

        assertThat(events.finished).hasSize(1)
        val completed = events.finished.single()
        assertThat(completed).isNotNull()
        assertThat(completed!!.loggedSets).isEqualTo(3)
        assertThat(fixture.controller.state.value).isNull()
        assertThat(fixture.store.history).hasSize(historyBefore + 1)
        // Ending the workout here must not also minimise the screen.
        assertThat(events.minimised).isEqualTo(0)
        // The template stays as it was (nothing changed in the exercise list, so no question was asked).
        assertThat(fixture.store.templates.first { it.name == "Upper A · Push" }.entries).hasSize(6)
    }

    @Test
    fun workoutWithNothingLoggedOffersOnlyKeepTrainingAndDiscard() {
        val fixture = ActiveFixture()
        rule.showActiveScreen(fixture)

        finishButton().performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Nothing logged yet").assertExists()
        rule.onNodeWithText("Log at least one set to save this workout.").assertExists()
        rule.onAllNodesWithText("Finish Workout").assertCountEquals(0)
        rule.onNodeWithText("Keep Training").assertExists()
        rule.onNodeWithText("Discard Workout").assertExists()
    }

    @Test
    fun discardWorkoutAsksAgainThenThrowsTheWorkoutAway() {
        val fixture = ActiveFixture().loggedWorkout()
        val events = ScreenEvents()
        rule.showActiveScreen(fixture, events)
        val historyBefore = fixture.store.history.size

        finishButton().performClick()
        rule.onNodeWithText("Discard Workout").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Discard workout?").assertExists()
        rule.onNodeWithText("You will lose 3 logged sets.").assertExists()
        // Cancel keeps it.
        rule.onNodeWithText("Cancel").performClick()
        rule.waitForIdle()
        assertThat(fixture.controller.state.value).isNotNull()

        finishButton().performClick()
        rule.onNodeWithText("Discard Workout").performClick()
        rule.onNodeWithText("Discard").performClick()
        rule.waitForIdle()
        assertThat(events.finished).containsExactly(null)
        assertThat(fixture.controller.state.value).isNull()
        assertThat(fixture.store.history).hasSize(historyBefore)
        assertThat(events.minimised).isEqualTo(0)
    }

    @Test
    fun discardFromTheMenuWithNothingLoggedSaysSo() {
        val fixture = ActiveFixture()
        val events = ScreenEvents()
        rule.showActiveScreen(fixture, events)

        rule.onNodeWithContentDescription("More").performClick()
        rule.onNodeWithText("Discard workout").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Nothing has been logged yet.").assertExists()
        rule.onNodeWithText("Discard").performClick()
        rule.waitForIdle()
        assertThat(events.finished).containsExactly(null)
    }

    @Test
    fun singleLoggedSetIsDescribedInTheSingular() {
        val fixture = ActiveFixture()
        fixture.log(0, 0..0)
        rule.showActiveScreen(fixture)
        finishButton().performClick()
        rule.onNodeWithText("Discard Workout").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("You will lose 1 logged set.").assertExists()
    }

    // region Update template

    @Test
    fun changedExerciseListAsksWhetherToUpdateTheTemplate() {
        val fixture = ActiveFixture().loggedWorkout()
        fixture.send(WorkoutAction.RemoveExercise(fixture.exerciseID(5)))
        val events = ScreenEvents()
        rule.showActiveScreen(fixture, events)

        finishButton().performClick()
        rule.onNodeWithText("Finish Workout").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Update “Upper A · Push”?").assertExists()
        rule.onNodeWithText("Changes: 1 removed. Save this exercise list for your next workouts?").assertExists()
        assertThat(events.finished).isEmpty()

        rule.onNodeWithText("Update Template").performClick()
        rule.waitForIdle()
        assertThat(events.finished).hasSize(1)
        assertThat(fixture.controller.state.value).isNull()
        assertThat(fixture.store.templates.first { it.name == "Upper A · Push" }.entries).hasSize(5)
    }

    @Test
    fun onlyThisWorkoutLeavesTheTemplateAlone() {
        val fixture = ActiveFixture().loggedWorkout()
        fixture.send(WorkoutAction.RemoveExercise(fixture.exerciseID(5)))
        val events = ScreenEvents()
        rule.showActiveScreen(fixture, events)

        finishButton().performClick()
        rule.onNodeWithText("Finish Workout").performClick()
        rule.onNodeWithText("Only This Workout").performClick()
        rule.waitForIdle()
        assertThat(events.finished).hasSize(1)
        assertThat(fixture.store.templates.first { it.name == "Upper A · Push" }.entries).hasSize(6)
    }

    @Test
    fun backToWorkoutKeepsTheWorkoutRunning() {
        val fixture = ActiveFixture().loggedWorkout()
        fixture.send(WorkoutAction.RemoveExercise(fixture.exerciseID(5)))
        val events = ScreenEvents()
        rule.showActiveScreen(fixture, events)

        finishButton().performClick()
        rule.onNodeWithText("Finish Workout").performClick()
        rule.onNodeWithText("Back to Workout").performClick()
        rule.waitForIdle()
        rule.onAllNodesWithText("Back to Workout").assertCountEquals(0)
        assertThat(fixture.controller.state.value).isNotNull()
        assertThat(events.finished).isEmpty()
    }

    @Test
    fun emptyWorkoutWithoutTemplateNeverAsksAboutTemplates() {
        val fixture = ActiveFixture(template = null)
        fixture.send(WorkoutAction.AddExercises(listOf(fixture.exercise("bench"))))
        fixture.log(0, 0..0)
        val events = ScreenEvents()
        rule.showActiveScreen(fixture, events)

        finishButton().performClick()
        rule.onNodeWithText("Finish Workout").performClick()
        rule.waitForIdle()
        assertThat(events.finished).hasSize(1)
    }

    // endregion
}
