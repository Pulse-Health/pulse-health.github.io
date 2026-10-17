package health.pulse.strength.ui.sheets

import android.view.View
import androidx.core.graphics.Insets
import androidx.core.view.WindowInsetsCompat
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performTextInput
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.ui.KeypadField
import health.pulse.strength.ui.PickerMode
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.shadows.ShadowDialog

/**
 * The sheets stay clear of the system bars and the keyboard: the system insets are delivered to the sheet's window the way the
 * system does it, and the content must end up inside the free area.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class SheetInsetsTest {
    @get:Rule val rule = createComposeRule()

    private val fixture = SheetFixture()
    private val density = 3f // xxhdpi
    private val windowHeight = 891f * 3f

    private fun dp(value: Int) = (value * density).toInt()

    /** Delivers system bar and keyboard insets (dp) to the window of the latest sheet. */
    private fun deliverInsets(status: Int = 0, navigation: Int = 0, ime: Int = 0) = rule.deliverSheetInsets(status, navigation, ime)

    private fun bottomOf(text: String) = rule.onNodeWithText(text).fetchSemanticsNode().boundsInRoot.bottom

    private fun topOf(text: String) = rule.onNodeWithText(text).fetchSemanticsNode().boundsInRoot.top

    @Test
    fun keypadButtonStaysAboveTheNavigationBar() {
        rule.setContent {
            PulseTestTheme { KeypadSheet(fixture.controller, fixture.ref(0, 2), KeypadField.WEIGHT, onDismiss = {}) }
        }
        rule.waitForIdle()
        val before = bottomOf("Next: Reps")
        deliverInsets(status = 24, navigation = 48)
        val after = bottomOf("Next: Reps")
        assertThat(after).isAtMost(windowHeight - dp(48) + 1f)
        // The content moved up by the navigation bar (the sheet itself still reaches the screen edge).
        assertThat(before - after).isAtLeast(dp(48) - 2f)
    }

    @Test
    fun fullHeightSheetStaysBelowTheStatusBar() {
        rule.setContent {
            PulseTestTheme { ExercisePickerSheet(fixture.store, fixture.controller, PickerMode.Add, onDismiss = {}) }
        }
        rule.waitForIdle()
        deliverInsets(status = 40, navigation = 48)
        assertThat(topOf("Add Exercise")).isAtLeast(dp(40).toFloat())
        assertThat(bottomOf("Select exercises")).isAtMost(windowHeight - dp(48) + 1f)
    }

    @Test
    fun pickerActionAndSearchStayAboveTheKeyboard() {
        rule.setContent {
            PulseTestTheme { ExercisePickerSheet(fixture.store, fixture.controller, PickerMode.Add, onDismiss = {}) }
        }
        rule.waitForIdle()
        deliverInsets(status = 24, navigation = 48, ime = 300)
        val keyboardTop = windowHeight - dp(300)
        assertThat(bottomOf("Select exercises")).isAtMost(keyboardTop + 1f)
        val search = rule.onNodeWithContentDescription("Search exercises").fetchSemanticsNode().boundsInRoot
        assertThat(search.bottom).isAtMost(keyboardTop)
        assertThat(search.top).isAtLeast(dp(24).toFloat())
    }

    /** The height of the display in px (the sheet window is as tall). */
    private fun displayHeight() = RuntimeEnvironment.getApplication().resources.displayMetrics.heightPixels.toFloat()

    /** The visible parts of the picker's result rows (the rows with a check circle). */
    private fun resultRows(): List<Rect> =
        rule.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.ToggleableState)).fetchSemanticsNodes().map { it.boundsInRoot }

    /** Opens the picker, types a search that matches many exercises and brings up a keyboard of [ime] dp; returns the search field. */
    private fun openPickerWithKeyboard(status: Int, navigation: Int, ime: Int): Rect {
        rule.setContent {
            PulseTestTheme { ExercisePickerSheet(fixture.store, fixture.controller, PickerMode.Add, onDismiss = {}) }
        }
        rule.waitForIdle()
        rule.onNodeWithContentDescription("Search exercises").performTextInput("press")
        deliverInsets(status = status, navigation = navigation, ime = ime)
        val search = rule.onNodeWithContentDescription("Search exercises").fetchSemanticsNode().boundsInRoot
        assertThat(search.bottom).isAtMost(displayHeight() - dp(ime))
        assertThat(search.top).isAtLeast(dp(status).toFloat())
        return search
    }

    /** The result rows that show in full between the search field and the keyboard. */
    private fun fullRowsAbove(keyboardTop: Float, search: Rect) =
        resultRows().filter { it.height >= dp(64) - 1f && it.top >= search.bottom - 1f && it.bottom <= keyboardTop + 1f }

    @Test
    @Config(qualifiers = "w360dp-h800dp-xxhdpi")
    fun pickerShowsSeveralMatchesAboveTheKeyboardOnASmallPhone() {
        val search = openPickerWithKeyboard(status = 24, navigation = 24, ime = 300)
        val keyboardTop = displayHeight() - dp(300)
        assertThat(fullRowsAbove(keyboardTop, search).size).isAtLeast(2)
        // The title bar and the action bar stay in a window that has the room.
        assertThat(bottomOf("Select exercises")).isAtMost(keyboardTop + 1f)
        rule.onNodeWithText("Cancel").assertExists()
    }

    @Test
    @Config(qualifiers = "w411dp-h914dp-xxhdpi")
    fun pickerShowsSeveralMatchesAboveTheKeyboardOnATallPhone() {
        val search = openPickerWithKeyboard(status = 24, navigation = 24, ime = 300)
        val keyboardTop = displayHeight() - dp(300)
        assertThat(fullRowsAbove(keyboardTop, search).size).isAtLeast(2)
        assertThat(bottomOf("Select exercises")).isAtMost(keyboardTop + 1f)
    }

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
    fun pickerShowsAMatchAboveTheKeyboardInLandscape() {
        val search = openPickerWithKeyboard(status = 24, navigation = 24, ime = 200)
        val keyboardTop = displayHeight() - dp(200)
        // About 160 dp are left: the search field and the first match (the title bar and the action bar wait for the keyboard to go).
        val visible = resultRows().filter { it.top >= search.bottom - 1f && it.bottom <= keyboardTop + 1f }
        assertThat(visible).isNotEmpty()
        assertThat(visible.first().height).isAtLeast(dp(48).toFloat())
    }

    @Test
    @Config(qualifiers = "w360dp-h800dp-xxhdpi")
    fun theFiltersAndTheCountGiveWayToTheKeyboardAndComeBack() {
        openPickerWithKeyboard(status = 24, navigation = 24, ime = 300)
        rule.onNodeWithText("Chest").assertDoesNotExist()
        rule.onNodeWithText("Machine").assertDoesNotExist()
        deliverInsets(status = 24, navigation = 24, ime = 0)
        rule.onNodeWithText("Chest").assertExists()
        rule.onNodeWithText("Machine").assertExists()
        rule.onNodeWithText("Select exercises").assertExists()
    }

    @Test
    fun createFormNameFieldStaysAboveTheKeyboard() {
        rule.setContent {
            PulseTestTheme { CreateExerciseSheet("", onCreate = {}, onDismiss = {}) }
        }
        rule.waitForIdle()
        rule.onNodeWithContentDescription("Name").performTextInput("Landmine")
        deliverInsets(status = 24, navigation = 48, ime = 340)
        val keyboardTop = windowHeight - dp(340)
        val field = rule.onNodeWithContentDescription("Name").fetchSemanticsNode().boundsInRoot
        assertThat(field.bottom).isAtMost(keyboardTop)
        assertThat(topOf("New Exercise")).isAtLeast(dp(24).toFloat())
    }

    @Test
    fun sideInsetsMoveTheContentInAsInLandscapeWithACutout() {
        rule.setContent {
            PulseTestTheme { RestSettingsSheet(fixture.controller, fixture.exercises[0].id, onDismiss = {}) }
        }
        rule.waitForIdle()
        val decor: View = ShadowDialog.getLatestDialog().window!!.decorView
        val before = rule.onNodeWithText("Done").fetchSemanticsNode().boundsInRoot.right
        val insets = WindowInsetsCompat.Builder()
            .setInsets(WindowInsetsCompat.Type.displayCutout(), Insets.of(0, 0, dp(48), 0))
            .build()
            .toWindowInsets()!!
        rule.runOnUiThread { decor.dispatchApplyWindowInsets(insets) }
        rule.waitForIdle()
        val after = rule.onNodeWithText("Done").fetchSemanticsNode().boundsInRoot.right
        assertThat(before - after).isAtLeast(dp(48) - 2f)
    }
}
