package health.pulse.strength.ui.sheets

import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.Exercise
import java.util.UUID
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The exercise options dispatch like the iOS confirmation dialog and offer only the actions that apply. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ExerciseOptionsDialogTest {
    @get:Rule val rule = createComposeRule()

    private val fixture = SheetFixture()
    private var dismissed = 0
    private var shownInfo: Exercise? = null
    private var shownRest: UUID? = null
    private var replaced: UUID? = null

    private fun open(index: Int) {
        val id = fixture.exercises[index].id
        rule.setContent {
            PulseTestTheme {
                ExerciseOptionsDialog(
                    controller = fixture.controller,
                    exerciseID = id,
                    onShowInfo = { shownInfo = it },
                    onShowRestSettings = { shownRest = it },
                    onReplace = { replaced = it },
                    onDismiss = { dismissed++ },
                )
            }
        }
        rule.waitForIdle()
    }

    private fun ids() = fixture.exercises.map { it.exercise.id }

    @Test
    fun middleExerciseOffersEverything() {
        open(1)
        rule.onNodeWithText("Incline dumbbell press").assertExists()
        for (label in listOf(
            "Form & instructions", "Rest timer · 1:30", "Replace exercise", "Superset with next", "Move up", "Move down",
            "Remove exercise",
        )) {
            rule.onNodeWithText(label).assertExists()
        }
        rule.onNodeWithText("Remove from superset").assertDoesNotExist()
    }

    @Test
    fun firstExerciseCannotMoveUp_lastCannotMoveDownOrJoinASuperset() {
        open(0)
        rule.onNodeWithText("Move up").assertDoesNotExist()
        rule.onNodeWithText("Move down").assertExists()
        rule.onNodeWithText("Rest timer · 2:30").assertExists()
    }

    @Test
    fun lastExercise() {
        open(5)
        rule.onNodeWithText("Move down").assertDoesNotExist()
        rule.onNodeWithText("Superset with next").assertDoesNotExist()
        rule.onNodeWithText("Move up").assertExists()
    }

    @Test
    fun supersetMembersCanLeave() {
        open(3)
        assertThat(fixture.exercises[3].supersetGroup).isEqualTo("A")
        rule.onNodeWithText("Remove from superset").performClick()
        rule.waitForIdle()
        assertThat(fixture.exercises[3].supersetGroup).isNull()
        // The partner is left alone, so the group dissolves.
        assertThat(fixture.exercises[4].supersetGroup).isNull()
        assertThat(dismissed).isEqualTo(1)
    }

    @Test
    fun supersetWithNextJoinsTheNextExercise() {
        open(1)
        rule.onNodeWithText("Superset with next").performClick()
        rule.waitForIdle()
        val group = fixture.exercises[1].supersetGroup
        assertThat(group).isNotNull()
        assertThat(fixture.exercises[2].supersetGroup).isEqualTo(group)
        assertThat(dismissed).isEqualTo(1)
    }

    @Test
    fun moveUpAndDownReorderTheWorkout() {
        open(1)
        val before = ids()
        rule.onNodeWithText("Move up").performClick()
        rule.waitForIdle()
        assertThat(ids()).isEqualTo(listOf(before[1], before[0]) + before.drop(2))
        assertThat(dismissed).isEqualTo(1)
    }

    @Test
    fun moveDownReordersToo() {
        open(1)
        val before = ids()
        rule.onNodeWithText("Move down").performClick()
        rule.waitForIdle()
        assertThat(ids()).isEqualTo(listOf(before[0], before[2], before[1]) + before.drop(3))
    }

    @Test
    fun removeDeletesTheExerciseAndCloses() {
        open(2)
        val removed = fixture.exercises[2].id
        rule.onNodeWithText("Remove exercise").performClick()
        rule.waitForIdle()
        assertThat(fixture.exercises).hasSize(5)
        assertThat(fixture.exercises.none { it.id == removed }).isTrue()
        assertThat(dismissed).isEqualTo(1)
        assertThat(fixture.controller.state.value!!.undo).isNotNull()
    }

    @Test
    fun followUpActionsAreReportedToTheHost() {
        open(1)
        rule.onNodeWithText("Form & instructions").performClick()
        rule.waitForIdle()
        assertThat(shownInfo?.id).isEqualTo("incline")
        assertThat(dismissed).isEqualTo(1)
    }

    @Test
    fun restAndReplaceAreReportedWithTheWorkoutEntryId() {
        open(1)
        val entry = fixture.exercises[1]
        rule.onNodeWithText("Rest timer · 1:30").performClick()
        rule.waitForIdle()
        assertThat(shownRest).isEqualTo(entry.id)
    }

    @Test
    fun replaceIsReported() {
        open(1)
        val entry = fixture.exercises[1]
        rule.onNodeWithText("Replace exercise").performClick()
        rule.waitForIdle()
        assertThat(replaced).isEqualTo(entry.id)
        // Nothing was changed in the workout by merely asking to replace.
        assertThat(fixture.exercises).hasSize(6)
    }

    @Test
    fun rowsAreAtLeast48dpTall() {
        open(1)
        rule.onNodeWithText("Move up").assertHeightIsAtLeast(48.dp)
    }

    @Test
    fun closesWhenTheExerciseIsNotInTheWorkout() {
        val id = UUID.randomUUID()
        rule.setContent {
            PulseTestTheme {
                ExerciseOptionsDialog(fixture.controller, id, {}, {}, {}, onDismiss = { dismissed++ })
            }
        }
        rule.waitForIdle()
        assertThat(dismissed).isEqualTo(1)
    }
}
