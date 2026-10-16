package health.pulse.strength.ui.sheets

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.down
import androidx.compose.ui.test.moveBy
import androidx.compose.ui.test.up
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.WorkoutAction
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The exercise list: rows, reordering (drag and accessible actions), the options dialog and the nested sheets. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ExerciseListSheetTest {
    @get:Rule val rule = createComposeRule()

    private val fixture = SheetFixture()
    private var dismissed = 0

    private fun open() {
        rule.setContent {
            PulseTestTheme { ExerciseListSheet(fixture.controller, fixture.store, onDismiss = { dismissed++ }) }
        }
        rule.waitForIdle()
    }

    private fun names() = fixture.exercises.map { it.exercise.id }

    private fun SemanticsNodeInteraction.customAction(label: String): Boolean {
        val action = fetchSemanticsNode().config[SemanticsActions.CustomActions].first { it.label == label }
        return rule.runOnUiThread { action.action() }
    }

    @Test
    fun showsEveryExerciseWithProgressAndSupersetLabel() {
        open()
        rule.onNodeWithText("Exercises").assertExists()
        rule.onNodeWithText("Done").assertExists()
        rule.onNodeWithText("6 exercises · Drag the handle to reorder. Superset exercises alternate their sets.").assertExists()
        rule.onNodeWithText("Barbell bench press").assertExists()
        rule.onNodeWithText("0 of 5 sets · Chest · Now").assertExists()
        rule.onNodeWithText("0 of 3 sets · Shoulders").assertExists()
        rule.onNodeWithText("Superset A · 0 of 3 sets · Shoulders").assertExists()
        rule.onNodeWithText("Superset A · 0 of 3 sets · Arms").assertExists()
        rule.onNodeWithText("Add Exercise").assertExists()
    }

    @Test
    fun progressFollowsLoggedSets() {
        val ref = fixture.ref(0, 0)
        fixture.controller.send(WorkoutAction.LogSet(ref.exerciseID, ref.setID))
        open()
        rule.onNodeWithText("1 of 5 sets · Chest · Now").assertExists()
    }

    @Test
    fun tappingARowShowsThatExerciseAndCloses() {
        open()
        rule.onNodeWithText("Overhead press").performClick()
        rule.waitForIdle()
        assertThat(fixture.controller.state.value!!.currentIndex).isEqualTo(2)
        assertThat(dismissed).isEqualTo(1)
    }

    /** Presses the handle of row [row], moves it by [steps] (px each, a frame in between) and lifts the finger. */
    private fun drag(row: Int, vararg steps: Float) {
        val handle = rule.onNodeWithTag("reorder-handle-$row")
        handle.performTouchInput { down(center) }
        for (dy in steps) {
            handle.performTouchInput { moveBy(Offset(0f, dy)) }
            rule.waitForIdle()
        }
        handle.performTouchInput { up() }
        rule.waitForIdle()
    }

    /** One row (64 dp + 2 x 3 dp of spacing) in pixels at xxhdpi. */
    private val rowPx = 70f * 3f

    @Test
    fun draggingTheHandleReordersTheWorkout() {
        open()
        val before = names()
        drag(0, rowPx * 0.7f, rowPx * 0.7f)
        assertThat(names()).isEqualTo(listOf(before[1], before[0]) + before.drop(2))
        // The workout's "current" exercise follows its entry (bench is still the one being worked on).
        assertThat(fixture.controller.state.value!!.currentExercise!!.exercise.id).isEqualTo("bench")
    }

    @Test
    fun draggingPastSeveralRowsMovesFarther() {
        open()
        val before = names()
        drag(0, rowPx * 1.2f, rowPx, rowPx, rowPx * 0.5f)
        // 3.7 rows down: the bench ends up in the fourth place.
        assertThat(names().indexOf("bench")).isEqualTo(3)
        assertThat(names().filter { it != "bench" }).isEqualTo(before.filter { it != "bench" })
    }

    @Test
    fun aShortDragThatDoesNotPassTheNeighbourChangesNothing() {
        open()
        val before = names()
        drag(1, 30f)
        assertThat(names()).isEqualTo(before)
    }

    @Test
    fun draggingUpWorksToo() {
        open()
        val before = names()
        drag(2, -rowPx * 0.7f, -rowPx * 0.7f)
        assertThat(names()).isEqualTo(listOf(before[0], before[2], before[1]) + before.drop(3))
    }

    @Test
    fun aSecondDragWorksFromTheNewOrder() {
        open()
        val before = names()
        drag(0, rowPx * 0.7f, rowPx * 0.7f)
        assertThat(names()).isEqualTo(listOf(before[1], before[0]) + before.drop(2))
        // The bench now sits second; drag it down once more.
        drag(1, rowPx * 0.7f, rowPx * 0.7f)
        assertThat(names()).isEqualTo(listOf(before[1], before[2], before[0]) + before.drop(3))
    }

    @Test
    fun draggingBackToWhereItStartedChangesNothing() {
        open()
        val before = names()
        drag(1, rowPx * 1.3f, -rowPx * 1.3f)
        assertThat(names()).isEqualTo(before)
    }

    /** How far the list is scrolled (px), as its scroll semantics report it. */
    private fun scrolled(): Float =
        rule.onNode(hasScrollAction()).fetchSemanticsNode().config[SemanticsProperties.VerticalScrollAxisRange].value()

    /** A landscape phone with gesture navigation: the list has room for about 2.7 rows (187 dp), the rows are 70 dp. */
    private fun openOnALandscapePhone() {
        open()
        rule.deliverSheetInsets(status = 24, navigation = 24)
        val viewport = rule.onNode(hasScrollAction()).fetchSemanticsNode().boundsInRoot.height / 3f
        assertThat(viewport).isAtLeast(180f)
        assertThat(viewport).isAtMost(200f)
    }

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
    fun draggingOneRowDownInAShortListDoesNotScrollIt() {
        openOnALandscapePhone()
        val before = names()
        val handle = rule.onNodeWithTag("reorder-handle-0")
        handle.performTouchInput { down(center) }
        for (i in 1..2) {
            handle.performTouchInput { moveBy(Offset(0f, rowPx * 0.68f)) }
            rule.waitForIdle()
        }
        // The finger is 130 dp down, on the second row, short of the bottom zone (from 140 dp on this 187 dp list). The old zone
        // (56 dp) began at 131, and went by the dragged row's bottom edge, 153 dp.
        assertThat(scrolled()).isEqualTo(0f)
        handle.performTouchInput { up() }
        rule.waitForIdle()
        assertThat(names()).isEqualTo(listOf(before[1], before[0]) + before.drop(2))
        assertThat(scrolled()).isEqualTo(0f)
    }

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
    fun holdingTheFingerAtTheBottomEdgeScrollsTheListUntilItIsLifted() {
        openOnALandscapePhone()
        val handle = rule.onNodeWithTag("reorder-handle-0")
        handle.performTouchInput { down(center) }
        for (i in 1..4) {
            handle.performTouchInput { moveBy(Offset(0f, rowPx * 0.7f)) }
            rule.waitForIdle()
        }
        // The finger is 182 dp below the row's centre, in the bottom zone of the 187 dp list.
        assertThat(scrolled()).isGreaterThan(0f)
        handle.performTouchInput { up() }
        rule.waitForIdle()
        val stopped = scrolled()
        rule.mainClock.advanceTimeBy(500)
        rule.waitForIdle()
        assertThat(scrolled()).isEqualTo(stopped)
    }

    @Test
    fun screenReadersGetMoveUpAndMoveDownActions() {
        open()
        val before = names()
        // The first row cannot move up.
        val firstRow = rule.onNodeWithText("Barbell bench press")
        val firstActions = firstRow.fetchSemanticsNode().config[SemanticsActions.CustomActions].map { it.label }
        assertThat(firstActions).containsExactly("Move down")
        val middle = rule.onNodeWithText("Incline dumbbell press")
        assertThat(middle.fetchSemanticsNode().config[SemanticsActions.CustomActions].map { it.label })
            .containsExactly("Move up", "Move down").inOrder()
        assertThat(middle.customAction("Move down")).isTrue()
        rule.waitForIdle()
        assertThat(names()).isEqualTo(listOf(before[0], before[2], before[1]) + before.drop(3))
    }

    @Test
    fun optionsButtonOpensTheOptionsAndMovesAndRemovesWork() {
        open()
        val before = names()
        rule.onNodeWithContentDescription("Options for Incline dumbbell press").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Move up").performClick()
        rule.waitForIdle()
        assertThat(names()).isEqualTo(listOf(before[1], before[0]) + before.drop(2))
        // The list shows the new order and the dialog is gone.
        rule.onNodeWithText("Move up").assertDoesNotExist()
        rule.onNodeWithContentDescription("Options for Overhead press").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Remove exercise").performClick()
        rule.waitForIdle()
        assertThat(fixture.exercises).hasSize(5)
        rule.onNodeWithText("5 exercises · Drag the handle to reorder. Superset exercises alternate their sets.").assertExists()
    }

    @Test
    fun optionsRestTimerOpensTheRestSheet() {
        open()
        rule.onNodeWithContentDescription("Options for Barbell bench press").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Rest timer · 2:30").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Rest Timer").assertExists()
        rule.onNodeWithText("Rest after each set · Barbell bench press").assertExists()
        rule.onNodeWithContentDescription("1 minute").performClick()
        assertThat(fixture.exercises[0].restSeconds).isEqualTo(60)
    }

    @Test
    fun optionsReplaceOpensThePickerInReplaceMode() {
        open()
        rule.onNodeWithContentDescription("Options for Cable crossover").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Replace exercise").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Replace Exercise").assertExists()
    }

    @Test
    fun optionsFormOpensTheFormSheetWithHistory() {
        open()
        rule.onNodeWithContentDescription("Options for Barbell bench press").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Form & instructions").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Form").assertExists()
        rule.onNodeWithText("History & records").assertExists()
    }

    @Test
    fun addExerciseOpensThePickerAndAddsToTheWorkout() {
        open()
        rule.onNodeWithText("Add Exercise").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Select exercises").assertExists()
        rule.onNodeWithContentDescription("Search exercises").performTextInput("push-up")
        rule.onNodeWithText("Push-up").performClick()
        rule.onNodeWithText("Add 1 exercise").performClick()
        rule.waitForIdle()
        assertThat(names().last()).isEqualTo("pushup")
        // The list is still open behind the picker and now shows seven exercises.
        rule.onNodeWithText("7 exercises · Drag the handle to reorder. Superset exercises alternate their sets.").assertExists()
        assertThat(dismissed).isEqualTo(0)
    }

    @Test
    fun doneDismisses() {
        open()
        rule.onNodeWithText("Done").performClick()
        rule.waitForIdle()
        assertThat(dismissed).isEqualTo(1)
    }
}
