package health.pulse.strength.ui.sheets

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.ui.PickerMode
import health.pulse.strength.ui.ScreenshotSupport.capture
import health.pulse.strength.ui.ScreenshotSupport.snapshot
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Photographs the exercise picker and the create form (`build/screens/picker-*.png`, `create-*.png`). */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class PickerScreenshotTest {
    @get:Rule val rule = createComposeRule()

    private val fixture = SheetFixture()

    private fun shootPicker(
        name: String,
        mode: PickerMode = PickerMode.Add,
        dark: Boolean = false,
        interact: () -> Unit = {},
    ) {
        val file = rule.snapshot(name, dark) {
            SheetFrame(fullHeight = true) {
                ExercisePickerSheetContent(fixture.store, fixture.controller, mode, onClose = {})
            }
        }
        interact()
        rule.capture(name)
        assertThat(file.length()).isGreaterThan(1000)
    }

    private fun search(text: String) = rule.onNodeWithContentDescription("Search exercises").performTextInput(text)

    @Test
    fun addMode() = shootPicker("picker-add")

    @Test
    fun addModeWithSelection() = shootPicker("picker-add-selected") {
        search("press")
        rule.onNodeWithText("Machine chest press").performClick()
        rule.onNodeWithText("Dumbbell shoulder press").performClick()
    }

    @Test
    fun searchResults() = shootPicker("picker-search") { search("curl") }

    @Test
    fun noResults() = shootPicker("picker-empty") { search("kettlebell") }

    @Test
    fun replaceMode() = shootPicker("picker-replace", PickerMode.Replace(fixture.exercises[1].id)) {
        rule.onNodeWithText("Chest").performClick()
        rule.onNodeWithText("Machine chest press").performClick()
    }

    @Test
    fun dark() = shootPicker("picker-add-dark", dark = true) {
        rule.onNodeWithText("Legs").performClick()
        rule.onNodeWithText("Back squat").performClick()
    }

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi")
    fun smallPhone() = shootPicker("picker-small-phone")

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
    fun landscape() = shootPicker("picker-landscape")

    @Test
    @Config(qualifiers = "w800dp-h1280dp-xhdpi")
    fun tablet() = shootPicker("picker-tablet")

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi", fontScale = 2.0f)
    fun fontScale200() = shootPicker("picker-font-200") {
        rule.onNodeWithText("Create custom exercise").performClick()
    }

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi", fontScale = 2.0f)
    fun smallPhoneFontScale200() = shootPicker("picker-small-phone-font-200")

    // region Create form

    private fun shootCreate(name: String, initialName: String = "", dark: Boolean = false) {
        val file = rule.snapshot(name, dark) {
            SheetFrame(fullHeight = true) {
                CreateExerciseSheetContent(initialName, onCreate = {}, onClose = {})
            }
        }
        assertThat(file.length()).isGreaterThan(1000)
    }

    @Test
    fun createForm() = shootCreate("create-form", "Landmine press")

    @Test
    fun createFormEmptyDark() = shootCreate("create-form-dark", dark = true)

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
    fun createFormLandscape() = shootCreate("create-form-landscape", "Landmine press")

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi", fontScale = 2.0f)
    fun createFormSmallFont200() = shootCreate("create-form-small-font-200", "Landmine press")

    @Test
    @Config(qualifiers = "w800dp-h1280dp-xhdpi")
    fun createFormTablet() = shootCreate("create-form-tablet", "Landmine press")

    // endregion
}
