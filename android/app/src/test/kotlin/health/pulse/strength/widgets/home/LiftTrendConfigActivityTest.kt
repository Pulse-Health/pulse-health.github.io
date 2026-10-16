package health.pulse.strength.widgets.home

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.core.widgets.preview
import health.pulse.strength.runtime.PreviewRuntime
import health.pulse.strength.runtime.StrengthRuntime
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** The configuration screen of the lift trend widget: it lists the lifts, stores the pick per widget id, and reports back to the launcher. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w411dp-h891dp-xxhdpi")
class LiftTrendConfigActivityTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Before
    fun installThePreviewRuntime() {
        StrengthRuntime.installForTest(PreviewRuntime(WidgetSnapshot.preview))
    }

    @After
    fun restoreTheDefaultRuntime() {
        StrengthRuntime.installForTest(PreviewRuntime())
    }

    private fun launch(widgetId: Int?): ActivityScenario<LiftTrendConfigActivity> {
        val intent = Intent(context, LiftTrendConfigActivity::class.java)
        if (widgetId != null) intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        return ActivityScenario.launchActivityForResult(intent)
    }

    private fun storedLift(widgetId: Int): String? = runBlocking {
        val glanceId = GlanceAppWidgetManager(context).getGlanceIdBy(widgetId)
        getAppWidgetState(context, PreferencesGlanceStateDefinition, glanceId)[LiftTrendWidget.LiftKey]
    }

    @Test
    fun withoutAWidgetIdTheScreenClosesAndCancels() {
        val scenario = launch(widgetId = null)
        assertThat(scenario.state).isEqualTo(Lifecycle.State.DESTROYED)
        assertThat(scenario.result.resultCode).isEqualTo(Activity.RESULT_CANCELED)
    }

    @Test
    fun thePickerListsEveryLiftWithItsValueAndMarksTheFirstOneForANewWidget() {
        launch(widgetId = 41).use {
            compose.onNodeWithText("Choose a lift").assertExists()
            compose.onNodeWithText("Bench Press").assertExists()
            compose.onNodeWithText("Estimated 1RM 96 kg · 3 sessions").assertExists()
            compose.onNodeWithText("Back Squat").assertExists()
            compose.onNodeWithText("Deadlift").assertExists()
            compose.onNode(hasText("Bench Press") and hasContentDescription("Selected")).assertExists()
        }
    }

    @Test
    fun pickingALiftStoresItForThatWidgetAndReportsOk() {
        val scenario = launch(widgetId = 42)
        compose.onNodeWithText("Back Squat").performClick()
        compose.waitUntil(timeoutMillis = 5_000) { scenario.state == Lifecycle.State.DESTROYED }
        assertThat(scenario.result.resultCode).isEqualTo(Activity.RESULT_OK)
        assertThat(scenario.result.resultData.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)).isEqualTo(42)
        assertThat(storedLift(42)).isEqualTo("squat")
        // Another widget keeps its own choice.
        assertThat(storedLift(43)).isNull()
    }

    @Test
    fun reconfiguringMarksTheLiftThatIsShownNow() {
        runBlocking {
            val glanceId = GlanceAppWidgetManager(context).getGlanceIdBy(44)
            updateAppWidgetState(context, glanceId) { it[LiftTrendWidget.LiftKey] = "squat" }
        }
        launch(widgetId = 44).use {
            compose.onNode(hasText("Back Squat") and hasContentDescription("Selected")).assertExists()
            compose.onNode(hasText("Bench Press") and hasContentDescription("Selected")).assertDoesNotExist()
        }
    }

    @Test
    fun withoutLiftsThePickerExplainsAndStillAddsTheWidget() {
        StrengthRuntime.installForTest(PreviewRuntime(WidgetSnapshot.preview.copy(lifts = emptyList())))
        val scenario = launch(widgetId = 45)
        compose.onNodeWithText("No lifts yet", substring = true).assertExists()
        compose.onNodeWithText("Add widget").performClick()
        compose.waitUntil(timeoutMillis = 5_000) { scenario.state == Lifecycle.State.DESTROYED }
        assertThat(scenario.result.resultCode).isEqualTo(Activity.RESULT_OK)
        assertThat(storedLift(45)).isNull()
    }
}
