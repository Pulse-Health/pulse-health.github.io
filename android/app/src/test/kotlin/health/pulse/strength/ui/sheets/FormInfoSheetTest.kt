package health.pulse.strength.ui.sheets

import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.activity.ComponentDialog
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.Equipment
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.ui.components.ExerciseMediaStore
import health.pulse.strength.core.TrackingKind
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.shadows.ShadowDialog

/** The form sheet shows the demo, muscles and cues; the host opens the history screen inside the same sheet. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class FormInfoSheetTest {
    @get:Rule val rule = createComposeRule()

    private val fixture = SheetFixture()
    private var dismissed = 0
    private val bench = ExerciseLibrary.exercise("bench")!!

    /** The system back button, delivered to the sheet's window (the latest dialog). */
    private fun pressBack() {
        val dialog = ShadowDialog.getLatestDialog() as ComponentDialog
        rule.runOnUiThread { dialog.onBackPressedDispatcher.onBackPressed() }
    }

    @Test
    fun showsNameChipsCuesAndAttribution() {
        rule.setContent { PulseTestTheme { FormInfoSheet(bench, onShowHistory = null, onDismiss = { dismissed++ }) } }
        rule.waitForIdle()
        rule.onNodeWithText("Form").assertExists()
        rule.onNodeWithText("Barbell bench press").assertExists()
        rule.onNodeWithText("Chest").assertExists()
        rule.onNodeWithText("Barbell").assertExists()
        rule.onNodeWithText("Shoulders · Triceps").assertExists()
        rule.onNodeWithText("How to").assertExists()
        for (cue in bench.cues) rule.onNodeWithContentDescription("Step ${bench.cues.indexOf(cue) + 1}. $cue").assertExists()
        rule.onNodeWithText("Start · End", useUnmergedTree = true).assertExists()
        rule.onNodeWithText("Demo photos from the Free Exercise DB.").assertExists()
        rule.onNodeWithContentDescription(
            "Form demo for Barbell bench press, alternating between the start and the end position",
        ).assertExists()
    }

    @Test
    fun historyRowOnlyWithACallback() {
        rule.setContent { PulseTestTheme { FormInfoSheet(bench, onShowHistory = null, onDismiss = {}) } }
        rule.waitForIdle()
        rule.onNodeWithText("History & records").assertDoesNotExist()
    }

    @Test
    fun historyRowCallsBack() {
        var opened = 0
        rule.setContent { PulseTestTheme { FormInfoSheet(bench, onShowHistory = { opened++ }, onDismiss = {}) } }
        rule.waitForIdle()
        rule.onNodeWithText("History & records").assertHeightIsAtLeast(48.dp).performClick()
        assertThat(opened).isEqualTo(1)
    }

    @After
    fun photosOn() {
        ExerciseMediaStore.enabled = true
    }

    @Test
    fun aBuildWithoutThePhotosShowsNoDemoTileBadgeOrCredit() {
        ExerciseMediaStore.enabled = false
        rule.setContent { PulseTestTheme { FormInfoSheet(bench, onShowHistory = null, onDismiss = {}) } }
        rule.waitForIdle()
        rule.onNodeWithText("Barbell bench press").assertExists()
        for (cue in bench.cues) rule.onNodeWithContentDescription("Step ${bench.cues.indexOf(cue) + 1}. $cue").assertExists()
        rule.onNodeWithText("Start · End", useUnmergedTree = true).assertDoesNotExist()
        rule.onNodeWithContentDescription("No form demo for this exercise yet").assertDoesNotExist()
        rule.onNodeWithContentDescription("Form demo for Barbell bench press", substring = true).assertDoesNotExist()
        rule.onNodeWithText("Demo photos from the Free Exercise DB.").assertDoesNotExist()
    }

    @Test
    fun exerciseWithoutMediaShowsThePlaceholderAndNoBadge() {
        val custom = Exercise.custom("Landmine press", MuscleGroup.SHOULDERS, Equipment.OTHER, TrackingKind.WEIGHT_REPS)
        rule.setContent { PulseTestTheme { FormInfoSheet(custom, onShowHistory = null, onDismiss = {}) } }
        rule.waitForIdle()
        rule.onNodeWithContentDescription("No form demo for this exercise yet").assertExists()
        rule.onNodeWithText("Start · End", useUnmergedTree = true).assertDoesNotExist()
        // "Custom" is a placeholder, not a muscle: no chip for it.
        rule.onNodeWithText("Custom").assertDoesNotExist()
        rule.onNodeWithText("Landmine press").assertExists()
        // No photo, so no photo credit either.
        rule.onNodeWithText("Demo photos from the Free Exercise DB.").assertDoesNotExist()
    }

    @Test
    fun doneDismisses() {
        rule.setContent { PulseTestTheme { FormInfoSheet(bench, onShowHistory = null, onDismiss = { dismissed++ }) } }
        rule.waitForIdle()
        rule.onNodeWithText("Done").performClick()
        rule.waitForIdle()
        assertThat(dismissed).isEqualTo(1)
    }

    @Test
    fun hostOpensHistoryInTheSameSheetAndBackReturnsToTheForm() {
        rule.setContent { PulseTestTheme { FormInfoHost(bench, fixture.store, onDismiss = { dismissed++ }) } }
        rule.waitForIdle()
        rule.onNodeWithText("History & records").performClick()
        rule.waitForIdle()
        // Page two: the exercise detail screen (a stand-in that shows the name while the real screen is ported elsewhere).
        rule.onNodeWithText("History & records").assertDoesNotExist()
        rule.onNodeWithText("How to").assertDoesNotExist()
        // System back returns to the form page and keeps the sheet.
        pressBack()
        rule.waitForIdle()
        rule.onNodeWithText("History & records").assertExists()
        assertThat(dismissed).isEqualTo(0)
        // Back on the form page closes the sheet.
        pressBack()
        rule.waitForIdle()
        assertThat(dismissed).isEqualTo(1)
    }
}
