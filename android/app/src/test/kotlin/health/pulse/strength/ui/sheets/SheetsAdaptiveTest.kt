package health.pulse.strength.ui.sheets

import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
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

/**
 * The sheets on short and narrow windows and at large font sizes: everything stays reachable (in view or by scrolling), and the
 * UI state of a sheet survives a configuration change.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class SheetsAdaptiveTest {
    @get:Rule val rule = createComposeRule()

    private val fixture = SheetFixture()
    private val benchSet = fixture.ref(0, 2)

    private fun openKeypad(field: KeypadField = KeypadField.WEIGHT) {
        rule.setContent { PulseTestTheme { KeypadSheet(fixture.controller, benchSet, field, onDismiss = {}) } }
        rule.waitForIdle()
    }

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
    fun keypadInLandscapeShowsEverythingAtOnce() {
        openKeypad()
        rule.onNodeWithText("Next: Reps").assertIsDisplayed()
        rule.onNodeWithContentDescription("0").assertIsDisplayed()
        rule.onNodeWithContentDescription("Delete").assertIsDisplayed()
        rule.onNodeWithText("Done").assertIsDisplayed()
        rule.onNodeWithText("Use last: 80 kg").assertIsDisplayed()
    }

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi")
    fun keypadOnASmallPhoneIsReachable() {
        openKeypad()
        rule.onNodeWithContentDescription("7").performScrollTo().assertIsDisplayed()
        rule.onNodeWithText("Next: Reps").performScrollTo().assertIsDisplayed()
        rule.onNodeWithText("Done").assertIsDisplayed()
    }

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi", fontScale = 2.0f)
    fun keypadAtDoubleFontOnASmallPhoneIsReachable() {
        openKeypad()
        rule.onNodeWithContentDescription("0").performScrollTo().assertIsDisplayed()
        rule.onNodeWithText("Next: Reps").performScrollTo().assertIsDisplayed()
        rule.onNodeWithText("Done").assertIsDisplayed()
    }

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi", fontScale = 1.3f)
    fun keypadInLandscapeWithLargeFontScrollsInsteadOfClipping() {
        openKeypad()
        rule.onNodeWithText("Next: Reps").performScrollTo().assertIsDisplayed()
    }

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi", fontScale = 2.0f)
    fun restPresetsAtDoubleFontAreReachable() {
        val id = fixture.exercises[0].id
        rule.setContent { PulseTestTheme { RestSettingsSheet(fixture.controller, id, onDismiss = {}) } }
        rule.waitForIdle()
        rule.onNodeWithText("5:00").performScrollTo().assertIsDisplayed()
        rule.onNodeWithText("Alert when rest is over").performScrollTo().assertIsDisplayed()
    }

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi", fontScale = 2.0f)
    fun setDetailAtDoubleFontKeepsDeleteReachable() {
        rule.setContent { PulseTestTheme { SetDetailSheet(fixture.controller, benchSet, onDismiss = {}) } }
        rule.waitForIdle()
        rule.onNodeWithText("Delete Set").performScrollTo().assertIsDisplayed()
    }

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
    fun pickerInLandscapeKeepsTheActionAndTheResultsReachable() {
        rule.setContent {
            PulseTestTheme { ExercisePickerSheet(fixture.store, fixture.controller, PickerMode.Add, onDismiss = {}) }
        }
        rule.waitForIdle()
        rule.onNodeWithText("Select exercises").assertIsDisplayed()
        rule.onNode(hasScrollAction()).performScrollToNode(hasText("Back squat"))
        rule.onNodeWithText("Back squat").assertIsDisplayed()
        rule.onNodeWithText("Select exercises").assertIsDisplayed()
    }

    @Test
    @Config(qualifiers = "w800dp-h1280dp-xhdpi")
    fun sheetsAreCentredAndAtMost640DpWideOnATablet() {
        openKeypad()
        val bounds = rule.onNodeWithText("Next: Reps").fetchSemanticsNode().boundsInRoot
        val density = rule.density.density
        // The primary button spans the sheet's content: at most 640 dp minus the 16 dp gutters, centred on the 800 dp window.
        assertThat(bounds.width / density).isAtMost(640f - 32f + 0.5f)
        assertThat((bounds.left + bounds.right) / 2f / density).isWithin(1f).of(400f)
    }

    // region State restoration

    @Test
    fun keypadKeepsItsBufferAndFieldAcrossARecreation() {
        val tester = StateRestorationTester(rule)
        tester.setContent {
            PulseTestTheme { KeypadSheet(fixture.controller, benchSet, KeypadField.WEIGHT, onDismiss = {}) }
        }
        rule.waitForIdle()
        rule.onNodeWithContentDescription("9").performClick()
        rule.onNodeWithContentDescription("1").performClick()
        rule.onNodeWithText("Next: Reps").performClick()
        rule.onNodeWithContentDescription("4").performClick()
        tester.emulateSavedInstanceStateRestore()
        rule.waitForIdle()
        // Still on the reps field (the primary button is "Log Set") with the typed value.
        rule.onNodeWithText("Log Set").assertExists()
        assertThat(fixture.set(0, 2).reps).isEqualTo(4)
        rule.onNodeWithContentDescription("2").performClick()
        // The buffer was "4", not fresh: the digit is appended.
        assertThat(fixture.set(0, 2).reps).isEqualTo(42)
        assertThat(fixture.set(0, 2).weightKg).isEqualTo(91.0)
    }

    @Test
    fun pickerKeepsSearchAndSelectionAcrossARecreation() {
        val tester = StateRestorationTester(rule)
        tester.setContent {
            PulseTestTheme { ExercisePickerSheet(fixture.store, fixture.controller, PickerMode.Add, onDismiss = {}) }
        }
        rule.waitForIdle()
        rule.onNodeWithContentDescription("Search exercises").performTextInput("push-up")
        rule.onNodeWithText("Push-up").performClick()
        tester.emulateSavedInstanceStateRestore()
        rule.waitForIdle()
        rule.onNodeWithText("Add 1 exercise").assertExists()
        rule.onNodeWithContentDescription("Search exercises").assertExists()
        rule.onNodeWithText("Create “push-up”").assertExists()
    }

    // endregion
}
