package health.pulse.strength.ui.sheets

import android.view.View
import androidx.core.graphics.Insets
import androidx.core.view.WindowInsetsCompat
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
    private fun deliverInsets(status: Int = 0, navigation: Int = 0, ime: Int = 0) {
        val decor: View = ShadowDialog.getLatestDialog().window!!.decorView
        val insets = WindowInsetsCompat.Builder()
            .setInsets(WindowInsetsCompat.Type.statusBars(), Insets.of(0, dp(status), 0, 0))
            .setInsets(WindowInsetsCompat.Type.navigationBars(), Insets.of(0, 0, 0, dp(navigation)))
            .setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, dp(ime)))
            .setVisible(WindowInsetsCompat.Type.ime(), ime > 0)
            .build()
            .toWindowInsets()!!
        rule.runOnUiThread { decor.dispatchApplyWindowInsets(insets) }
        rule.waitForIdle()
    }

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
