package health.pulse.strength.wear.ui

import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.wear.WearFixtures
import health.pulse.strength.wear.WearFixtures.now
import health.pulse.strength.wear.data.WearCommands
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The watch app on a tall round screen (so that every item of the list is composed): what each state shows and which command each
 * control sends.
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w227dp-h900dp-round")
class WearScreenTest {
    @get:Rule
    val compose = createComposeRule()

    private val sent = mutableListOf<WidgetCommand>()

    private fun show(state: WearUiState) {
        compose.setContent { PulseWearTheme { WearScreen(state) { sent += it } } }
    }

    private fun idle(isPlaceholder: Boolean = false, starting: Boolean = false, notice: String? = null) =
        WearUiState(WearFixtures.preview, isPlaceholder, now, starting, notice)

    private fun running(active: WorkoutSnapshot, notice: String? = null) =
        WearUiState(WearFixtures.withWorkout(active), isPlaceholder = false, now = now, notice = notice)

    private fun text(value: String) = compose.onNodeWithText(value, useUnmergedTree = true)

    private fun description(value: String) = compose.onNodeWithContentDescription(value, useUnmergedTree = true)

    // region Waiting and idle

    @Test
    fun beforeTheFirstSyncTheAppWaitsForThePhone() {
        show(idle(isPlaceholder = true))

        text("Waiting for your phone").assertExists()
        text("Open Pulse Strength on your phone to sync your week.").assertExists()
        text("Start").assertDoesNotExist()
        text("Upper A · Push").assertDoesNotExist()
    }

    @Test
    fun withoutAWorkoutTheAppShowsTheWeekAndTheNextWorkout() {
        show(idle())

        text("3/4").assertExists()
        text("Push day").assertExists()
        text("Upper A · Push").assertExists()
        text("6 exercises · ~55 min").assertExists()
        text("6 week streak").assertExists()
        text("Last workout 3 days ago").assertExists()
    }

    @Test
    fun theWeekIsReadAsOneSentence() {
        show(idle())

        compose.onNodeWithContentDescription("3 of 4 workouts this week. 6 week streak. Last workout 3 days ago").assertExists()
    }

    @Test
    fun startAsksThePhoneToStartTheNextWorkout() {
        show(idle())

        text("Start").performClick()

        assertThat(sent).containsExactly(WearCommands.startNext())
    }

    @Test
    fun whileTheWorkoutIsStartingTheButtonIsDisabled() {
        show(idle(starting = true))

        text("Starting…").assertExists()
        compose.onNode(hasClickAction() and hasText("Starting…")).assertIsNotEnabled()
    }

    @Test
    fun withoutTemplatesTheAppSaysWhereToAddOne() {
        show(WearUiState(WearFixtures.preview.copy(nextUp = null), isPlaceholder = false, now = now))

        text("No workout planned").assertExists()
        text("Add one in Pulse on your phone.").assertExists()
        text("Start").assertDoesNotExist()
    }

    @Test
    fun withNoHistoryTheWeekIsZeroOfTheGoal() {
        val week = WearFixtures.preview.week.copy(completed = 0, streakWeeks = 0, daysSinceLastWorkout = null, lastWorkoutAt = null)

        show(WearUiState(WearFixtures.preview.copy(week = week), isPlaceholder = false, now = now))

        text("0/4").assertExists()
        text("6 week streak").assertDoesNotExist()
    }

    // endregion

    // region Logging

    @Test
    fun loggingShowsTheClockTheExerciseTheSetAndWhatToLift() {
        show(running(WearFixtures.workout()))

        text("Upper A · Push").assertExists()
        text("25:00").assertExists()
        text("Bench Press").assertExists()
        text("Set 3 of 4").assertExists()
        text("80 kg × 6").assertExists()
    }

    @Test
    fun logSetSendsLogNextSet() {
        show(running(WearFixtures.workout()))

        text("Log set").performClick()

        assertThat(sent).containsExactly(WearCommands.logNextSet())
    }

    @Test
    fun theSteppersNudgeTheWeightAndTheReps() {
        show(running(WearFixtures.workout()))

        description("Increase weight").performClick()
        description("Decrease weight").performClick()
        description("Increase reps").performClick()
        description("Decrease reps").performClick()

        assertThat(sent).containsExactly(
            WearCommands.nudge(1, 0),
            WearCommands.nudge(-1, 0),
            WearCommands.nudge(0, 1),
            WearCommands.nudge(0, -1),
        ).inOrder()
    }

    @Test
    fun theSteppersShowTheValuesWithTheirUnits() {
        show(running(WearFixtures.workout()))

        text("80").assertExists()
        text("kg").assertExists()
        text("6").assertExists()
        text("reps").assertExists()
        compose.onNodeWithContentDescription("weight, 80 kilograms").assertExists()
        compose.onNodeWithContentDescription("reps, 6 reps").assertExists()
    }

    @Test
    fun anExerciseWithoutAWeightHasOnlyTheRepsStepper() {
        show(running(WearFixtures.workout(tracking = TrackingKind.REPS_ONLY, showsWeight = false)))

        description("Increase weight").assertDoesNotExist()
        description("Increase reps").assertExists()
        text("6 reps").assertExists()
    }

    @Test
    fun aTimedExerciseNudgesTheDuration() {
        show(running(WearFixtures.workout(tracking = TrackingKind.DURATION, showsWeight = false)))

        description("Increase duration").performClick()

        assertThat(sent).containsExactly(WearCommands.nudge(0, 1))
        text("6 s").assertExists()
    }

    @Test
    fun pauseSendsPause() {
        show(running(WearFixtures.workout()))

        text("Pause").performClick()

        assertThat(sent).containsExactly(WearCommands.pause())
    }

    @Test
    fun afterTheRestTheLogSetPageMarksRestOver() {
        show(running(WearFixtures.workout(phase = SnapshotPhase.REST_OVER)))

        text("Rest over").assertExists()
        text("Log set").assertExists()
    }

    @Test
    fun aVeryLongExerciseNameStaysOnTheScreenInTwoLines() {
        val name = "Single-Arm Cable Crossover with Rotational Finish"

        show(running(WearFixtures.workout(exerciseName = name)))

        text(name).assertExists()
    }

    // endregion

    // region Resting

    @Test
    fun restingShowsTheCountdownTheRingAndTheNextSet() {
        show(running(WearFixtures.resting(seconds = 84, total = 120)))

        text("1:24").assertExists()
        text("Next · 80 kg × 6").assertExists()
        compose.onNodeWithContentDescription("Rest timer").assertExists()
    }

    @Test
    fun theRestButtonsSendSkipAndFifteenSeconds() {
        show(running(WearFixtures.resting()))

        description("Skip rest").performClick()
        description("Add 15 seconds to the rest").performClick()
        description("Subtract 15 seconds from the rest").performClick()

        assertThat(sent).containsExactly(
            WearCommands.skipRest(),
            WearCommands.adjustRest(15),
            WearCommands.adjustRest(-15),
        ).inOrder()
    }

    @Test
    fun aSetCanBeLoggedBeforeTheRestEnds() {
        show(running(WearFixtures.resting()))

        text("Log set").performClick()

        assertThat(sent).containsExactly(WearCommands.logNextSet())
    }

    @Test
    fun aRestThatRanOutIsTheLogSetPage() {
        show(running(WearFixtures.workout(phase = SnapshotPhase.RESTING, restEndsAt = now.minusSeconds(3))))

        text("Rest over").assertExists()
        text("Skip rest").assertDoesNotExist()
    }

    // endregion

    // region Paused and finished

    @Test
    fun pausedShowsPausedAndResumeAndTheFrozenClock() {
        show(running(WearFixtures.workout(isPaused = true, elapsedWhenPaused = 1480)))

        text("Paused").assertExists()
        text("24:40").assertExists()
        text("Resume").performClick()

        assertThat(sent).containsExactly(WearCommands.resume())
    }

    @Test
    fun aPausedRestShowsWhatWasLeft() {
        show(running(WearFixtures.resting().copy(isPaused = true, restFrozenRemaining = 61)))

        text("Rest 1:01 left").assertExists()
    }

    @Test
    fun afterTheLastSetTheAppOffersToFinishTheWorkout() {
        show(running(WearFixtures.workout(phase = SnapshotPhase.COMPLETE, loggedSets = 20)))

        text("All sets logged").assertExists()
        text("20 sets").assertExists()
        text("Finish workout").performClick()

        assertThat(sent).containsExactly(WearCommands.finish())
    }

    // endregion

    // region Notice and touch targets

    @Test
    fun aNoticeIsShownOverTheList() {
        show(idle(notice = "Your phone is not reachable."))

        text("Your phone is not reachable.").assertExists()
    }

    private fun assertEveryControlIsAtLeast48DpHigh() {
        val minimum = with(compose.density) { 48.dp.roundToPx() }
        val controls = compose.onAllNodes(hasClickAction()).fetchSemanticsNodes()

        assertThat(controls).isNotEmpty()
        controls.forEach { control -> assertThat(control.size.height).isAtLeast(minimum - 1) }
    }

    @Test
    fun theControlsOfTheIdleScreenAreBigEnough() {
        show(idle())

        assertEveryControlIsAtLeast48DpHigh()
    }

    @Test
    fun theControlsOfTheLogSetScreenAreBigEnough() {
        show(running(WearFixtures.workout()))

        assertEveryControlIsAtLeast48DpHigh()
    }

    @Test
    fun theControlsOfTheRestScreenAreBigEnough() {
        show(running(WearFixtures.resting()))

        assertEveryControlIsAtLeast48DpHigh()
    }

    // endregion
}
