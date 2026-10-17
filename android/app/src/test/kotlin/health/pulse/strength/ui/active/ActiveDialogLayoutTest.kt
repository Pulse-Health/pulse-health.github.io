package health.pulse.strength.ui.active

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.WorkoutAction
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The finish, template and discard dialogs when the window is short for the text size: the stacked buttons keep their room and use
 * most of the height, so the message has to scroll in what is left (it used to be cut off with no way to read the rest), and a long
 * title stops at two lines. The dialogs are opened through the screen's UI state, so they do not depend on where the header is.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
abstract class ActiveDialogScenarios {
    @get:Rule
    val rule = createComposeRule()

    protected val templateMessage = "Changes: 1 removed. Save this exercise list for your next workouts?"

    /**
     * A logged workout on screen with its dialogs under the test's control; with [changedList] its exercise list differs from the
     * template (the "Update template?" question).
     */
    internal fun show(changedList: Boolean = false): ActiveWorkoutUiState {
        val fixture = ActiveFixture()
        fixture.log(0, 0..2)
        fixture.send(WorkoutAction.SkipRest)
        if (changedList) fixture.send(WorkoutAction.RemoveExercise(fixture.exerciseID(5)))
        val ui = ActiveWorkoutUiState()
        rule.showActiveScreen(fixture, uiState = ui)
        return ui
    }

    protected fun open(change: () -> Unit) {
        rule.runOnIdle(change)
        rule.waitForIdle()
    }

    protected fun lineCountOf(text: String): Int {
        val results = mutableListOf<TextLayoutResult>()
        rule.onNodeWithText(text).fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult].action!!.invoke(results)
        return results.single().lineCount
    }

    /** The message is a scroll container, on screen. */
    protected fun assertMessageIsScrollable(text: String) {
        val message = rule.onNodeWithText(text)
        message.assertIsDisplayed()
        message.assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.VerticalScrollAxisRange))
    }

    /** The message is a scroll container with more text than room, and it can be scrolled to its end. */
    protected fun assertMessageScrollsToItsEnd(text: String) {
        val message = rule.onNodeWithText(text)
        message.assertIsDisplayed()
        val before = message.fetchSemanticsNode().config[SemanticsProperties.VerticalScrollAxisRange]
        assertThat(before.maxValue()).isGreaterThan(0f)
        message.performSemanticsAction(SemanticsActions.ScrollBy) { it.invoke(0f, 100_000f) }
        rule.waitForIdle()
        val after = rule.onNodeWithText(text).fetchSemanticsNode().config[SemanticsProperties.VerticalScrollAxisRange]
        assertThat(after.value()).isEqualTo(after.maxValue())
        assertThat(after.value()).isGreaterThan(0f)
    }
}

/** A 732 x 320 dp phone held sideways at 200 % text: the message gets about one line between the title and the three buttons. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w732dp-h320dp-land-xxhdpi", fontScale = 2.0f)
class ActiveDialogShortLandscapeTest : ActiveDialogScenarios() {
    @Test
    fun templateDialogMessageScrollsAndTheButtonsStayInView() {
        val ui = show(changedList = true)
        open { ui.showTemplateDialog = true }

        assertMessageScrollsToItsEnd(templateMessage)
        rule.onNodeWithText("Update Template").assertIsDisplayed()
        rule.onNodeWithText("Only This Workout").assertIsDisplayed()
        rule.onNodeWithText("Back to Workout").assertIsDisplayed()
    }

    @Test
    fun finishDialogMessageScrolls() {
        val ui = show()
        open { ui.showFinishDialog = true }

        assertMessageScrollsToItsEnd("17 sets are not logged yet and will be left out.")
        rule.onNodeWithText("Finish Workout").assertIsDisplayed()
        rule.onNodeWithText("Keep Training").assertIsDisplayed()
        rule.onNodeWithText("Discard Workout").assertIsDisplayed()
    }

    @Test
    fun discardDialogMessageIsScrollable() {
        val ui = show()
        open { ui.showDiscardDialog = true }

        assertMessageIsScrollable("You will lose 3 logged sets.")
        rule.onNodeWithText("Discard").assertIsDisplayed()
        rule.onNodeWithText("Cancel").assertIsDisplayed()
    }
}

/** A 320 dp wide phone at 200 % text: a long workout name would need five lines in the title, which stops at two. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w320dp-h640dp-xhdpi", fontScale = 2.0f)
class ActiveDialogNarrowBigTextTest : ActiveDialogScenarios() {
    @Test
    fun titleStopsAtTwoLines() {
        val title = "Update “Upper A · Push Day With A Very Long Name”?"
        rule.setContent {
            TestScreenTheme(ClockHandle()) {
                StackedAlertDialog(
                    title = title,
                    message = templateMessage,
                    actions = listOf(DialogAction("Update Template", "template-update", onClick = {})),
                    onDismiss = {},
                )
            }
        }
        rule.waitForIdle()

        assertThat(lineCountOf(title)).isEqualTo(2)
        rule.onNodeWithText(templateMessage).assertIsDisplayed()
    }

    @Test
    fun theWorkoutsOwnTemplateDialogKeepsItsTitleWithinTwoLines() {
        val ui = show(changedList = true)
        open { ui.showTemplateDialog = true }

        assertThat(lineCountOf("Update “Upper A · Push”?")).isAtMost(2)
        rule.onNodeWithText(templateMessage).assertIsDisplayed()
    }
}
