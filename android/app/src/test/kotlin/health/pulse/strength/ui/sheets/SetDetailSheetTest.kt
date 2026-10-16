package health.pulse.strength.ui.sheets

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.SetType
import health.pulse.strength.core.WorkoutAction
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Set type, reps in reserve and delete dispatch the right actions. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class SetDetailSheetTest {
    @get:Rule val rule = createComposeRule()

    private val fixture = SheetFixture()
    private var dismissed = 0
    private val ref = fixture.ref(0, 2)

    private fun open() {
        rule.setContent { PulseTestTheme { SetDetailSheet(fixture.controller, ref, onDismiss = { dismissed++ }) } }
        rule.waitForIdle()
    }

    private fun set() = fixture.set(0, 2)

    private fun isSelected(selected: Boolean) = SemanticsMatcher.expectValue(SemanticsProperties.Selected, selected)

    @Test
    fun showsTitleTypesAndCurrentChoice() {
        open()
        rule.onNodeWithText("Set 3 · Barbell bench press").assertExists()
        rule.onNodeWithText("Set type").assertExists()
        rule.onNodeWithText("Reps in reserve").assertExists()
        for (title in listOf("Normal", "Warm-up", "Drop set", "To failure")) rule.onNodeWithText(title).assertExists()
        rule.onNodeWithText("Counts toward volume").assertExists()
        rule.onNodeWithText("Left out of volume and PRs").assertExists()
        rule.onNodeWithText("Lower weight, little rest").assertExists()
        rule.onNodeWithText("Until you cannot do another rep").assertExists()
        rule.onNodeWithText("Normal").assert(isSelected(true))
        rule.onNodeWithText("Warm-up").assert(isSelected(false))
        rule.onNodeWithContentDescription("Not recorded").assert(isSelected(true))
    }

    @Test
    fun pickingATypeDispatchesAndKeepsTheSheetOpen() {
        open()
        rule.onNodeWithText("Drop set").performClick()
        assertThat(set().type).isEqualTo(SetType.DROP)
        rule.onNodeWithText("Drop set").assert(isSelected(true))
        rule.onNodeWithText("To failure").performClick()
        assertThat(set().type).isEqualTo(SetType.FAILURE)
        rule.onNodeWithText("Warm-up").performClick()
        assertThat(set().type).isEqualTo(SetType.WARMUP)
        assertThat(dismissed).isEqualTo(0)
    }

    @Test
    fun repsInReserveSegments() {
        open()
        rule.onNodeWithContentDescription("2 reps in reserve").performClick()
        assertThat(set().rir).isEqualTo(2)
        rule.onNodeWithContentDescription("2 reps in reserve").assert(isSelected(true))
        rule.onNodeWithContentDescription("0 reps in reserve").performClick()
        assertThat(set().rir).isEqualTo(0)
        rule.onNodeWithContentDescription("1 rep in reserve").performClick()
        assertThat(set().rir).isEqualTo(1)
        rule.onNodeWithContentDescription("4 or more reps in reserve").performClick()
        assertThat(set().rir).isEqualTo(4)
        rule.onNodeWithContentDescription("Not recorded").performClick()
        assertThat(set().rir).isNull()
        assertThat(dismissed).isEqualTo(0)
    }

    @Test
    fun segmentsAreComfortableTouchTargets() {
        open()
        rule.onNodeWithContentDescription("3 reps in reserve").assertHeightIsAtLeast(48.dp)
        rule.onNodeWithText("Done").assertHeightIsAtLeast(48.dp)
    }

    @Test
    fun deleteRemovesTheSetAndClosesTheSheet() {
        open()
        val before = fixture.exercises[0].sets.size
        rule.onNodeWithText("Delete Set").performClick()
        rule.waitForIdle()
        assertThat(fixture.exercises[0].sets).hasSize(before - 1)
        assertThat(fixture.exercises[0].sets.none { it.id == ref.setID }).isTrue()
        assertThat(dismissed).isEqualTo(1)
        // The workout screen offers Undo.
        assertThat(fixture.controller.state.value!!.undo).isNotNull()
    }

    @Test
    fun doneClosesWithoutChangingAnything() {
        open()
        val before = fixture.controller.state.value
        rule.onNodeWithText("Done").performClick()
        rule.waitForIdle()
        assertThat(dismissed).isEqualTo(1)
        assertThat(fixture.controller.state.value).isEqualTo(before)
    }

    @Test
    fun closesWhenTheSetWasRemovedElsewhere() {
        open()
        fixture.controller.send(WorkoutAction.DeleteSet(ref.exerciseID, ref.setID))
        rule.waitForIdle()
        assertThat(dismissed).isEqualTo(1)
    }
}
