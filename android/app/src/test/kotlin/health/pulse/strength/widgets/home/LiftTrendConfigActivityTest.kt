package health.pulse.strength.widgets.home

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.glance.GlanceId
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
import org.robolectric.Shadows.shadowOf
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

    /** A lift trend widget that the system knows, as the launcher has bound it before it opens the configuration screen. */
    private fun boundWidget(widgetId: Int): GlanceId {
        val info = AppWidgetProviderInfo().apply { provider = ComponentName(context, LiftTrendReceiver::class.java) }
        shadowOf(AppWidgetManager.getInstance(context)).addBoundWidget(widgetId, info)
        return GlanceAppWidgetManager(context).getGlanceIdBy(widgetId)
    }

    private fun launch(widgetId: Int?): ActivityScenario<LiftTrendConfigActivity> {
        val intent = Intent(context, LiftTrendConfigActivity::class.java)
        if (widgetId != null) intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        return ActivityScenario.launchActivityForResult(intent)
    }

    /** What a screen that is closing reports to the launcher. */
    private data class Reported(val resultCode: Int, val widgetId: Int)

    /** Waits until the screen is finishing and returns its result (the test clock does not drive the scenario on to DESTROYED). */
    private fun ActivityScenario<LiftTrendConfigActivity>.awaitReported(): Reported {
        var finishing = false
        compose.waitUntil(timeoutMillis = 5_000) {
            onActivity { finishing = it.isFinishing }
            finishing
        }
        var reported: Reported? = null
        onActivity {
            val shadow = shadowOf(it)
            reported = Reported(shadow.resultCode, shadow.resultIntent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1))
        }
        return checkNotNull(reported)
    }

    private fun storedLift(widgetId: Int): String? = runBlocking {
        getAppWidgetState(context, PreferencesGlanceStateDefinition, boundWidget(widgetId))[LiftTrendWidget.LiftKey]
    }

    @Test
    fun withoutAWidgetIdTheScreenClosesAndCancels() {
        val scenario = launch(widgetId = null)
        assertThat(scenario.state).isEqualTo(Lifecycle.State.DESTROYED)
        assertThat(scenario.result.resultCode).isEqualTo(Activity.RESULT_CANCELED)
    }

    @Test
    fun anIdThatIsNoWidgetOfTheAppClosesAndCancelsToo() {
        // The screen is exported: whatever id another app sends, nothing is stored and nothing is shown.
        val scenario = launch(widgetId = 77)
        assertThat(scenario.state).isEqualTo(Lifecycle.State.DESTROYED)
        assertThat(scenario.result.resultCode).isEqualTo(Activity.RESULT_CANCELED)
    }

    @Test
    fun thePickerListsEveryLiftWithItsValueAndMarksTheFirstOneForANewWidget() {
        boundWidget(41)
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
        boundWidget(42)
        launch(widgetId = 42).use { scenario ->
            compose.onNodeWithText("Back Squat").performClick()
            assertThat(scenario.awaitReported()).isEqualTo(Reported(Activity.RESULT_OK, widgetId = 42))
            assertThat(storedLift(42)).isEqualTo("squat")
            // Another widget keeps its own choice.
            assertThat(storedLift(43)).isNull()
        }
    }

    @Test
    fun reconfiguringMarksTheLiftThatIsShownNow() {
        val glanceId = boundWidget(44)
        runBlocking { updateAppWidgetState(context, glanceId) { it[LiftTrendWidget.LiftKey] = "squat" } }
        launch(widgetId = 44).use {
            compose.onNode(hasText("Back Squat") and hasContentDescription("Selected")).assertExists()
            compose.onNode(hasText("Bench Press") and hasContentDescription("Selected")).assertDoesNotExist()
        }
    }

    @Test
    fun withoutLiftsThePickerExplainsAndStillAddsTheWidget() {
        StrengthRuntime.installForTest(PreviewRuntime(WidgetSnapshot.preview.copy(lifts = emptyList())))
        boundWidget(45)
        launch(widgetId = 45).use { scenario ->
            compose.onNodeWithText("No lifts yet", substring = true).assertExists()
            compose.onNodeWithText("Add widget").performClick()
            assertThat(scenario.awaitReported()).isEqualTo(Reported(Activity.RESULT_OK, widgetId = 45))
            assertThat(storedLift(45)).isNull()
        }
    }
}
