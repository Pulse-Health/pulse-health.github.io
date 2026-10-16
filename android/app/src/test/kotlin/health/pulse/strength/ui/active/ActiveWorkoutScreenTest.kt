package health.pulse.strength.ui.active

import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performImeAction
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.unit.dp
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.SetRef
import health.pulse.strength.core.SetType
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.ui.KeypadField
import health.pulse.strength.ui.PickerMode
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Interactions of the active-workout screen on a normal phone: what a tap dispatches to the controller, what it opens, and what the
 * screen shows afterwards (all texts come from the presenter).
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ActiveWorkoutScreenTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private fun state(fixture: ActiveFixture) = fixture.controller.state.value!!

    // region Header and navigator

    @Test
    fun headerShowsTitleClockAndStatsFromThePresenter() {
        val fixture = ActiveFixture()
        rule.showActiveScreen(fixture)

        rule.tagged("active-title").assertTextEquals("Upper A · Push")
        rule.tagged("active-clock").assertTextEquals("24:18")
        rule.tagged("active-volume").assertTextEquals("0")
        rule.tagged("active-sets").assertTextEquals("0 of 20")
        // The Android app has no heart-rate source: no heart item without a value.
        rule.onAllNodesWithText("bpm", useUnmergedTree = true).assertCountEquals(0)

        fixture.log(0, 2..2)
        rule.waitForIdle()
        rule.tagged("active-sets").assertTextEquals("1 of 20")
        rule.tagged("active-volume").assertTextEquals("495")
    }

    @Test
    fun heartRateAppearsOnlyWhileASourceReportsOne() {
        val fixture = ActiveFixture()
        rule.showActiveScreen(fixture)
        rule.onAllNodesWithText("bpm", useUnmergedTree = true).assertCountEquals(0)

        fixture.send(WorkoutAction.UpdateHeartRate(128))
        rule.waitForIdle()
        rule.onNodeWithText("bpm", useUnmergedTree = true).assertExists()
        rule.onNodeWithText("128", useUnmergedTree = true).assertExists()
    }

    @Test
    fun pausedWorkoutShowsPausedClock() {
        val fixture = ActiveFixture()
        fixture.send(WorkoutAction.Pause)
        rule.showActiveScreen(fixture)
        rule.tagged("active-clock").assertTextEquals("Paused · 24:18")
    }

    @Test
    fun navigatorMovesBetweenExercisesAndDisablesTheEnds() {
        val fixture = ActiveFixture()
        rule.showActiveScreen(fixture)
        rule.tagged("active-position").assertContentDescriptionEquals("Exercise 1 of 6")
        rule.onNodeWithContentDescription("Previous exercise").assertIsNotEnabled()
        rule.tagged("active-exercise-name").assertTextEquals("Barbell bench press")

        rule.onNodeWithContentDescription("Next exercise").performClick()
        rule.waitForIdle()
        assertThat(state(fixture).currentIndex).isEqualTo(1)
        rule.tagged("active-position").assertContentDescriptionEquals("Exercise 2 of 6")
        rule.tagged("active-exercise-name").assertTextEquals("Incline dumbbell press")
        rule.onNodeWithContentDescription("Previous exercise").assertIsEnabled()

        rule.onNodeWithContentDescription("Previous exercise").performClick()
        rule.waitForIdle()
        assertThat(state(fixture).currentIndex).isEqualTo(0)

        fixture.send(WorkoutAction.GoTo(5))
        rule.waitForIdle()
        rule.onNodeWithContentDescription("Next exercise").assertIsNotEnabled()
    }

    @Test
    fun minimiseButtonCallsBack() {
        val events = ScreenEvents()
        rule.showActiveScreen(ActiveFixture(), events)
        rule.onNodeWithContentDescription("Minimise workout").performClick()
        assertThat(events.minimised).isEqualTo(1)
    }

    @Test
    fun screenKeepsTheDisplayOn() {
        rule.showActiveScreen(ActiveFixture())
        val flags = rule.activity.window.attributes.flags
        assertThat(flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON).isNotEqualTo(0)
    }

    // endregion

    // region Exercise card

    @Test
    fun cardShowsExerciseRecoveryAndSupersetFromThePresenter() {
        val fixture = ActiveFixture()
        rule.showActiveScreen(fixture)
        rule.tagged("active-recovery").assertTextEquals("Chest · 88% recovered")
        rule.onAllNodesWithTag("active-superset", useUnmergedTree = true).assertCountEquals(0)

        fixture.send(WorkoutAction.GoTo(3))
        rule.waitForIdle()
        rule.tagged("active-exercise-name").assertTextEquals("Dumbbell lateral raise")
        rule.tagged("active-superset").assertExists()
        rule.onNodeWithText("Superset A", useUnmergedTree = true).assertExists()
    }

    @Test
    fun checkCircleLogsAndUnlogsTheSetAndStartsTheRest() {
        val fixture = ActiveFixture()
        rule.showActiveScreen(fixture)
        val exercise = fixture.exerciseID(0)
        val set = fixture.setID(0, 2)
        rule.onAllNodesWithTag("rest-dock", useUnmergedTree = true).assertCountEquals(0)

        rule.tagged("set-check-$set").performClick()
        rule.waitForIdle()
        assertThat(state(fixture).exercises[0].sets[2].isDone).isTrue()
        assertThat(state(fixture).lastLogged).isEqualTo(SetRef(exercise, set))
        // Logging a working set of the bench press starts its 2:30 rest.
        rule.tagged("rest-dock").assertExists()
        rule.tagged("rest-remaining").assertTextEquals("2:30")

        rule.tagged("set-check-$set").performClick()
        rule.waitForIdle()
        assertThat(state(fixture).exercises[0].sets[2].isDone).isFalse()
    }

    @Test
    fun addSetAppendsARowToTheCard() {
        val fixture = ActiveFixture()
        rule.showActiveScreen(fixture)
        val before = state(fixture).exercises[0].sets.size

        rule.tagged("add-set").performClick()
        rule.waitForIdle()
        val sets = state(fixture).exercises[0].sets
        assertThat(sets).hasSize(before + 1)
        rule.tagged("set-row-${sets.last().id}").assertExists()
    }

    @Test
    fun valueCellsBadgeAndButtonsOpenTheRightSheets() {
        val fixture = ActiveFixture()
        val ui = ActiveWorkoutUiState()
        rule.showActiveScreen(fixture, uiState = ui)
        val exercise = fixture.exerciseID(0)
        val ref = SetRef(exercise, fixture.setID(0, 2))

        rule.tagged("set-weight-${ref.setID}").performClick()
        assertThat(ui.sheet).isEqualTo(ActiveSheet.Keypad(ref, KeypadField.WEIGHT))
        rule.tagged("set-reps-${ref.setID}").performClick()
        assertThat(ui.sheet).isEqualTo(ActiveSheet.Keypad(ref, KeypadField.REPS))
        rule.tagged("set-badge-${ref.setID}").performClick()
        assertThat(ui.sheet).isEqualTo(ActiveSheet.SetDetail(ref))
        rule.tagged("rest-chip").performClick()
        assertThat(ui.sheet).isEqualTo(ActiveSheet.RestSettings(exercise))
        rule.tagged("active-media").performClick()
        assertThat(ui.sheet).isEqualTo(ActiveSheet.Info(state(fixture).exercises[0].exercise))
        rule.tagged("active-edit").performClick()
        assertThat(ui.sheet).isEqualTo(ActiveSheet.ExerciseList)

        ui.sheet = null
        rule.tagged("exercise-options").performClick()
        assertThat(ui.optionsExerciseID).isEqualTo(exercise)
    }

    @Test
    fun bodyweightExerciseHasNoWeightEditor() {
        val fixture = ActiveFixture(template = "Upper B · Pull")
        val ui = ActiveWorkoutUiState()
        rule.showActiveScreen(fixture, uiState = ui)
        // Pull-up: reps only, the weight column reads "BW" and is not a button.
        val set = fixture.setID(0, 0)
        rule.onNodeWithText("ADDED", useUnmergedTree = true).assertExists()
        rule.onAllNodesWithText("BW", useUnmergedTree = true).assertCountEquals(3)
        rule.tagged("set-weight-$set").performClick()
        assertThat(ui.sheet).isNull()
        rule.tagged("set-reps-$set").performClick()
        assertThat(ui.sheet).isInstanceOf(ActiveSheet.Keypad::class.java)
    }

    @Test
    fun durationExerciseCountsSecondsWithoutAWeight() {
        val fixture = ActiveFixture(template = null)
        fixture.send(WorkoutAction.AddExercises(listOf(fixture.exercise("plank"))))
        val ui = ActiveWorkoutUiState()
        rule.showActiveScreen(fixture, uiState = ui)
        val row = fixture.presentation().card!!.rows[0]
        assertThat(row.repsText).isEqualTo("45")
        rule.onNodeWithText("SEC", useUnmergedTree = true).assertExists()
        assertThat(row.weightText).isEqualTo("\u2013")
        rule.tagged("set-weight-${row.id}").performClick()
        assertThat(ui.sheet).isNull()
        // "Edit seconds" is the custom action of the row; the weight has no editor.
        val names = rule.tagged("set-row-${row.id}").fetchSemanticsNode().config[SemanticsActions.CustomActions].map { it.label }
        assertThat(names).containsExactly("Change set type", "Edit seconds").inOrder()
    }

    @Test
    fun setRowIsOneScreenReaderElementWithTheLabelAndCustomActions() {
        val fixture = ActiveFixture()
        val ui = ActiveWorkoutUiState()
        rule.showActiveScreen(fixture, uiState = ui)
        val exercise = fixture.exerciseID(0)
        val set = fixture.setID(0, 2)
        val label = fixture.presentation().card!!.rows[2].accessibilityLabel
        assertThat(label).isEqualTo("Set 3, working set, 82.5 kilograms, 6 reps, not logged")

        val row = rule.tagged("set-row-$set")
        val config = row.fetchSemanticsNode().config
        assertThat(config.getOrNull(SemanticsProperties.ContentDescription)).containsExactly(label)
        val names = config[SemanticsActions.CustomActions].map { it.label }
        assertThat(names).containsExactly("Change set type", "Edit weight", "Edit reps").inOrder()
        // The row's own action logs the set.
        row.performSemanticsAction(SemanticsActions.OnClick)
        rule.waitForIdle()
        assertThat(state(fixture).exercises[0].sets[2].isDone).isTrue()
        // The custom actions open the editors.
        val actions = rule.tagged("set-row-$set").fetchSemanticsNode().config[SemanticsActions.CustomActions]
        actions.first { it.label == "Edit weight" }.action()
        assertThat(ui.sheet).isEqualTo(ActiveSheet.Keypad(SetRef(exercise, set), KeypadField.WEIGHT))
        actions.first { it.label == "Change set type" }.action()
        assertThat(ui.sheet).isEqualTo(ActiveSheet.SetDetail(SetRef(exercise, set)))
    }

    @Test
    fun personalRecordAndRepsInReserveAppearOnLoggedRows() {
        val fixture = ActiveFixture()
        val exercise = fixture.exerciseID(0)
        fixture.send(WorkoutAction.SetWeight(exercise, fixture.setID(0, 2), 85.0))
        fixture.log(0, 2..2)
        fixture.send(WorkoutAction.ToggleLastSetRIR(2))
        rule.showActiveScreen(fixture)
        rule.onNodeWithText("PR", useUnmergedTree = true).assertExists()
        rule.onNodeWithText("RIR 2", useUnmergedTree = true).assertExists()
    }

    @Test
    fun warmupSetKeepsItsBadgeLetter() {
        val fixture = ActiveFixture()
        rule.showActiveScreen(fixture)
        val first = fixture.presentation().card!!.rows[0]
        assertThat(first.type).isEqualTo(SetType.WARMUP)
        rule.tagged("set-badge-${first.id}").assertExists()
        rule.onAllNodesWithText("W", useUnmergedTree = true).assertCountEquals(2)
    }

    @Test
    fun coachTipShowsOnlyWhileNoRestRuns() {
        val fixture = ActiveFixture()
        fixture.log(0, 0..0)
        rule.showActiveScreen(fixture)
        rule.onAllNodesWithTag("coach-tip", useUnmergedTree = true).assertCountEquals(0)

        fixture.send(WorkoutAction.SkipRest)
        rule.waitForIdle()
        rule.tagged("coach-tip").assertExists()
        assertThat(fixture.presentation().card!!.coachTip).isNotNull()
    }

    // endregion

    // region Note

    @Test
    fun noteButtonOpensTheFieldAndDoneSavesTheNote() {
        val fixture = ActiveFixture()
        rule.showActiveScreen(fixture)
        rule.onAllNodesWithTag("note-field", useUnmergedTree = true).assertCountEquals(0)

        rule.tagged("note-button").performClick()
        rule.waitForIdle()
        rule.tagged("note-field").assertExists()
        rule.tagged("note-field").performTextInput("Seat at 4")
        rule.tagged("note-field").performImeAction()
        rule.waitForIdle()
        assertThat(state(fixture).exercises[0].note).isEqualTo("Seat at 4")

        // Closing the field shows the saved note as a line.
        rule.tagged("note-button").performClick()
        rule.waitForIdle()
        rule.onAllNodesWithTag("note-field", useUnmergedTree = true).assertCountEquals(0)
        rule.tagged("note-line").assertContentDescriptionEquals("Note: Seat at 4")
    }

    @Test
    fun noteIsSavedWhenTheFieldIsClosedWithoutPressingDone() {
        val fixture = ActiveFixture()
        rule.showActiveScreen(fixture)
        rule.tagged("note-button").performClick()
        rule.waitForIdle()
        rule.tagged("note-field").performTextInput("Pause on chest")
        rule.tagged("note-button").performClick()
        rule.waitForIdle()
        assertThat(state(fixture).exercises[0].note).isEqualTo("Pause on chest")
    }

    // endregion

    // region Rest dock

    private fun restingFixture(): ActiveFixture {
        val fixture = ActiveFixture()
        fixture.log(0, 0..2, secondsAgo = 78)
        return fixture
    }

    @Test
    fun dockShowsTheCountdownAndAdjustsIt() {
        val fixture = restingFixture()
        rule.showActiveScreen(fixture)
        rule.tagged("rest-remaining").assertTextEquals("1:12")

        rule.tagged("dock-plus").performClick()
        rule.waitForIdle()
        rule.tagged("rest-remaining").assertTextEquals("1:27")
        assertThat(state(fixture).rest!!.totalSeconds).isEqualTo(165)

        rule.tagged("dock-minus").performClick()
        rule.tagged("dock-minus").performClick()
        rule.waitForIdle()
        rule.tagged("rest-remaining").assertTextEquals("0:57")
    }

    @Test
    fun skipEndsTheRestAndTheDockGoesAway() {
        val fixture = restingFixture()
        rule.showActiveScreen(fixture)
        rule.tagged("dock-skip").performClick()
        rule.waitForIdle()
        assertThat(state(fixture).rest).isNull()
        rule.onAllNodesWithTag("rest-dock", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test
    fun repsLeftChipsSetAndClearTheReservedReps() {
        val fixture = restingFixture()
        rule.showActiveScreen(fixture)
        val set = state(fixture).exercises[0].sets[2]
        assertThat(set.rir).isNull()

        rule.tagged("dock-rir-3").performClick()
        rule.waitForIdle()
        assertThat(state(fixture).exercises[0].sets[2].rir).isEqualTo(3)
        // Tapping the selected chip clears it.
        rule.tagged("dock-rir-3").performClick()
        rule.waitForIdle()
        assertThat(state(fixture).exercises[0].sets[2].rir).isNull()
        rule.tagged("dock-rir-4").performClick()
        rule.waitForIdle()
        assertThat(state(fixture).exercises[0].sets[2].rir).isEqualTo(4)
    }

    @Test
    fun finishedRestOffersDismiss() {
        val fixture = ActiveFixture()
        fixture.log(0, 0..2, secondsAgo = 160)
        rule.showActiveScreen(fixture)
        rule.tagged("rest-remaining").assertTextEquals("Go")
        rule.onNodeWithText("Rest over", useUnmergedTree = true).assertExists()
        rule.onAllNodesWithTag("dock-skip", useUnmergedTree = true).assertCountEquals(0)

        rule.tagged("dock-dismiss").performClick()
        rule.waitForIdle()
        assertThat(state(fixture).rest).isNull()
        rule.onAllNodesWithTag("rest-dock", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test
    fun repsLeftRowIsHiddenAfterAWarmupSet() {
        val fixture = ActiveFixture()
        fixture.log(0, 0..0, secondsAgo = 10)
        rule.showActiveScreen(fixture)
        rule.tagged("rest-dock").assertExists()
        rule.onAllNodesWithTag("dock-rir", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test
    fun pausedRestIsLabelledPaused() {
        val fixture = restingFixture()
        fixture.send(WorkoutAction.Pause)
        rule.showActiveScreen(fixture)
        rule.onNodeWithText("Rest · paused", useUnmergedTree = true).assertExists()
    }

    // endregion

    // region Undo toast and empty state

    @Test
    fun removedExerciseOffersUndoInAToast() {
        val fixture = ActiveFixture()
        rule.showActiveScreen(fixture)
        rule.onAllNodesWithTag("undo-toast", useUnmergedTree = true).assertCountEquals(0)

        fixture.send(WorkoutAction.RemoveExercise(fixture.exerciseID(5)))
        rule.waitForIdle()
        rule.onNodeWithText("Removed Cable crossover", useUnmergedTree = true).assertExists()
        assertThat(state(fixture).exercises).hasSize(5)

        rule.tagged("undo-button").performClick()
        rule.waitForIdle()
        assertThat(state(fixture).exercises).hasSize(6)
        rule.onAllNodesWithTag("undo-toast", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test
    fun deletedSetShowsTheToastToo() {
        val fixture = ActiveFixture()
        fixture.send(WorkoutAction.DeleteSet(fixture.exerciseID(0), fixture.setID(0, 4)))
        rule.showActiveScreen(fixture)
        rule.onNodeWithText("Set deleted", useUnmergedTree = true).assertExists()
    }

    @Test
    fun toastExpiresWithThePresenterClock() {
        val fixture = ActiveFixture()
        fixture.send(WorkoutAction.RemoveExercise(fixture.exerciseID(5)))
        val clock = ClockHandle()
        rule.showActiveScreen(fixture, clock = clock)
        rule.tagged("undo-toast").assertExists()

        clock.time = clock.time.plusSeconds(7)
        rule.waitForIdle()
        rule.onAllNodesWithTag("undo-toast", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test
    fun emptyWorkoutShowsTheEmptyStateWithAddExercise() {
        val fixture = ActiveFixture(template = null)
        val ui = ActiveWorkoutUiState()
        rule.showActiveScreen(fixture, uiState = ui)
        rule.onNodeWithText("No exercises yet", useUnmergedTree = true).assertExists()
        rule.onNodeWithText(
            "Add an exercise from the library, or create your own, to start logging sets.",
            useUnmergedTree = true,
        ).assertExists()
        rule.onAllNodesWithTag("active-position", useUnmergedTree = true).assertCountEquals(0)

        rule.tagged("empty-add").performClick()
        assertThat(ui.sheet).isEqualTo(ActiveSheet.Picker(PickerMode.Add))
    }

    // endregion

    // region More menu

    @Test
    fun moreMenuPausesAndResumesTheWorkout() {
        val fixture = ActiveFixture()
        rule.showActiveScreen(fixture)

        rule.onNodeWithContentDescription("More").performClick()
        rule.onNodeWithText("Pause workout").performClick()
        rule.waitForIdle()
        assertThat(state(fixture).isPaused).isTrue()
        rule.tagged("active-clock").assertTextEquals("Paused · 24:18")

        rule.onNodeWithContentDescription("More").performClick()
        rule.onNodeWithText("Resume workout").performClick()
        rule.waitForIdle()
        assertThat(state(fixture).isPaused).isFalse()
    }

    @Test
    fun moreMenuOpensTheListPickerAndRestSettings() {
        val fixture = ActiveFixture()
        val ui = ActiveWorkoutUiState()
        rule.showActiveScreen(fixture, uiState = ui)

        rule.onNodeWithContentDescription("More").performClick()
        rule.onNodeWithText("Edit exercises").performClick()
        assertThat(ui.sheet).isEqualTo(ActiveSheet.ExerciseList)

        rule.onNodeWithContentDescription("More").performClick()
        rule.onNodeWithText("Add exercise").performClick()
        assertThat(ui.sheet).isEqualTo(ActiveSheet.Picker(PickerMode.Add))

        rule.onNodeWithContentDescription("More").performClick()
        rule.onNodeWithText("Rest timer settings").performClick()
        assertThat(ui.sheet).isEqualTo(ActiveSheet.RestSettings(fixture.exerciseID(0)))
    }

    @Test
    fun emptyWorkoutMenuHasNoRestTimerSettings() {
        val fixture = ActiveFixture(template = null)
        rule.showActiveScreen(fixture)
        rule.onNodeWithContentDescription("More").performClick()
        rule.onNodeWithText("Add exercise").assertExists()
        rule.onAllNodesWithText("Rest timer settings").assertCountEquals(0)
    }

    // endregion

    // region Touch targets, insets and the keyboard

    @Test
    fun everyTappableControlHasATouchTargetOfAtLeast48Dp() {
        val fixture = ActiveFixture()
        fixture.log(0, 0..2, secondsAgo = 78)
        fixture.send(WorkoutAction.RemoveExercise(fixture.exerciseID(5)))
        rule.showActiveScreen(fixture)
        rule.tagged("note-button").performClick() // the note field is a control too
        rule.waitForIdle()

        val clickable = rule.onAllNodes(hasClickAction(), useUnmergedTree = true).fetchSemanticsNodes()
        assertThat(clickable.size).isAtLeast(20)
        val minimum = with(rule.density) { 48.dp.toPx() } - 1f
        val tooSmall = clickable.filter { node ->
            val bounds = node.touchBoundsInRoot
            bounds.width < minimum || bounds.height < minimum
        }
        assertThat(tooSmall.map { it.config.getOrNull(SemanticsProperties.TestTag) ?: it.config.toString() }).isEmpty()
    }

    @Test
    fun dockHidesWhileTheKeyboardIsUpAndComesBack() {
        val fixture = restingFixture()
        rule.showActiveScreen(fixture)
        rule.tagged("rest-dock").assertExists()

        rule.applySystemBars(imeDp = 300)
        rule.waitForIdle()
        rule.onAllNodesWithTag("rest-dock", useUnmergedTree = true).assertCountEquals(0)

        rule.applySystemBars(imeDp = 0)
        rule.waitForIdle()
        rule.tagged("rest-dock").assertExists()
    }

    // endregion

    @Test
    fun openNoteFieldAndDialogSurviveARotation() {
        val fixture = ActiveFixture()
        fixture.log(0, 0..0)
        fixture.send(WorkoutAction.SkipRest)
        val content: @Composable () -> Unit = {
            TestScreenTheme(ClockHandle()) {
                ActiveWorkoutScreen(controller = fixture.controller, store = fixture.store, onMinimise = {}, onFinished = {})
            }
        }
        rule.setContent(content)
        rule.tagged("note-button").performClick()
        rule.waitForIdle()
        rule.tagged("note-field").performTextInput("Seat at 4")
        rule.tagged("active-finish").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Finish workout?").assertExists()

        // Rotate: the activity is recreated and gets its saved state back.
        rule.activityRule.scenario.recreate()
        rule.activityRule.scenario.onActivity { activity -> activity.setContent(content = content) }
        rule.waitForIdle()
        rule.onNodeWithText("Finish workout?").assertExists()
        rule.tagged("note-field").assertTextContains("Seat at 4")
    }

    // endregion

    // region Ending the workout elsewhere

    @Test
    fun workoutEndedElsewhereLeavesTheScreen() {
        val fixture = ActiveFixture()
        val events = ScreenEvents()
        rule.showActiveScreen(fixture, events)
        assertThat(events.minimised).isEqualTo(0)

        fixture.controller.discard()
        rule.waitForIdle()
        assertThat(events.minimised).isEqualTo(1)
        assertThat(events.finished).isEmpty()
    }

    // endregion
}
