package health.pulse.strength.widgets.home

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.widgets.tablet.TabletWidgets
import health.pulse.strength.widgets.tablet.TrainingBlockWidget
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.xmlpull.v1.XmlPullParser

/**
 * The manifest and the provider files of the widgets of this folder: every provider exists, is exported for the launcher, has the cell
 * size of widgets/SPEC.md, never updates on a timer, and only the two small widgets of SB-01 are offered on the glanceable hub.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WidgetRegistryTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private class Expected(val receiver: String, val label: String, val cells: Pair<Int, Int>, val keyguard: Boolean = false)

    private val home = "health.pulse.strength.widgets.home."
    private val expected = listOf(
        Expected(home + "NextUpReceiver", "Next up", 2 to 2, keyguard = true),
        Expected(home + "NextUpWideReceiver", "Next workout", 4 to 2),
        Expected(home + "WeeklyGoalReceiver", "Weekly goal", 2 to 2, keyguard = true),
        Expected(home + "WeeklyGoalThemedReceiver", "Weekly goal (themed)", 2 to 2),
        Expected(home + "PrSpotlightReceiver", "PR spotlight", 2 to 2),
        Expected(home + "MuscleFreshnessReceiver", "Muscle freshness", 2 to 2),
        Expected(home + "OverloadReceiver", "Beat last time", 2 to 2),
        Expected(home + "WeeklySetsReceiver", "Weekly sets", 4 to 2),
        Expected(home + "LiftTrendReceiver", "Lift trend", 4 to 2),
        Expected(home + "TrainingWeekReceiver", "Training week", 4 to 4),
        Expected(home + "TemplateLauncherReceiver", "Template launcher", 4 to 4),
        Expected(home + "MonthHeatmapReceiver", "Month heatmap", 4 to 4),
        Expected("health.pulse.strength.widgets.tablet.TrainingBlockReceiver", "Training block", 6 to 4),
    )

    private class Provider(val targetWidth: Int, val targetHeight: Int, val category: Int, val resizeMode: Int, val updatePeriod: Int, val configure: String?, val description: Int, val initialLayout: Int)

    private fun provider(receiver: String): Provider {
        val info = context.packageManager.getReceiverInfo(ComponentName(context, receiver), PackageManager.GET_META_DATA)
        val xml = info.metaData.getInt("android.appwidget.provider")
        assertThat(xml).isNotEqualTo(0)
        val parser = context.resources.getXml(xml)
        var event = parser.eventType
        while (event != XmlPullParser.START_TAG) event = parser.next()
        assertThat(parser.name).isEqualTo("appwidget-provider")
        return Provider(
            targetWidth = parser.getAttributeIntValue(ANDROID, "targetCellWidth", -1),
            targetHeight = parser.getAttributeIntValue(ANDROID, "targetCellHeight", -1),
            category = parser.getAttributeIntValue(ANDROID, "widgetCategory", -1),
            resizeMode = parser.getAttributeIntValue(ANDROID, "resizeMode", -1),
            updatePeriod = parser.getAttributeIntValue(ANDROID, "updatePeriodMillis", -1),
            configure = parser.getAttributeValue(ANDROID, "configure"),
            description = parser.getAttributeResourceValue(ANDROID, "description", 0),
            initialLayout = parser.getAttributeResourceValue(ANDROID, "initialLayout", 0),
        )
    }

    @Test
    fun everyWidgetHasAnExportedReceiverWithItsLabel() {
        for (widget in expected) {
            val info = context.packageManager.getReceiverInfo(ComponentName(context, widget.receiver), 0)
            assertThat(info.exported).isTrue()
            assertThat(info.loadLabel(context.packageManager).toString()).isEqualTo(widget.label)
        }
    }

    @Test
    fun everyProviderHasTheCellSizeOfTheSpecAndNeverUpdatesOnATimer() {
        for (widget in expected) {
            val provider = provider(widget.receiver)
            assertThat(provider.targetWidth to provider.targetHeight).isEqualTo(widget.cells)
            assertThat(provider.updatePeriod).isEqualTo(0)
            assertThat(provider.resizeMode).isEqualTo(RESIZE_HORIZONTAL or RESIZE_VERTICAL)
            assertThat(provider.description).isNotEqualTo(0)
            assertThat(provider.initialLayout).isNotEqualTo(0)
            assertThat(context.getString(provider.description)).isNotEmpty()
        }
    }

    @Test
    fun onlyNextUpAndWeeklyGoalAreOfferedOnTheGlanceableHub() {
        for (widget in expected) {
            val category = provider(widget.receiver).category
            if (widget.keyguard) {
                assertThat(category).isEqualTo(HOME_SCREEN or KEYGUARD)
            } else {
                assertThat(category).isEqualTo(HOME_SCREEN)
            }
        }
    }

    @Test
    fun theLiftTrendProviderNamesItsConfigurationScreenAndIsReconfigurable() {
        val provider = provider(home + "LiftTrendReceiver")
        assertThat(provider.configure).isEqualTo(home + "LiftTrendConfigActivity")
        assertThat(Class.forName(provider.configure!!)).isEqualTo(LiftTrendConfigActivity::class.java)
        val configure = Intent("android.appwidget.action.APPWIDGET_CONFIGURE").setPackage(context.packageName)
        val activities = context.packageManager.queryIntentActivities(configure, 0)
        assertThat(activities.map { it.activityInfo.name }).contains(home + "LiftTrendConfigActivity")
        assertThat(activities.first { it.activityInfo.name == home + "LiftTrendConfigActivity" }.activityInfo.exported).isTrue()
        // No other provider has a configuration screen.
        expected.filter { !it.receiver.endsWith("LiftTrendReceiver") }.forEach { assertThat(provider(it.receiver).configure).isNull() }
    }

    @Test
    fun everyReceiverDrivesTheWidgetThatTheRefreshUpdates() {
        val widgetClasses = HomeWidgets.all().map { it::class.java } + TabletWidgets.all().map { it::class.java }
        assertThat(widgetClasses).containsNoDuplicates()
        val driven = expected.map { widget ->
            (Class.forName(widget.receiver).getDeclaredConstructor().newInstance() as GlanceAppWidgetReceiver).glanceAppWidget::class.java
        }
        // Every widget the refresh knows is placed through at least one provider, and every provider drives a widget the refresh knows.
        assertThat(driven.toSet()).containsExactlyElementsIn(widgetClasses)
        // Next up is the one widget placed through two providers (2x2 and 4x2).
        assertThat(driven.count { it == NextUpWidget::class.java }).isEqualTo(2)
        assertThat(TabletWidgets.all().map { it::class.java }).containsExactly(TrainingBlockWidget::class.java)
    }

    private companion object {
        const val ANDROID = "http://schemas.android.com/apk/res/android"
        const val HOME_SCREEN = 1
        const val KEYGUARD = 2
        const val RESIZE_HORIZONTAL = 1
        const val RESIZE_VERTICAL = 2
    }
}
