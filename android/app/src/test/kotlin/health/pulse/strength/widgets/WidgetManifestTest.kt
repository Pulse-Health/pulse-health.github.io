package health.pulse.strength.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.XmlResourceParser
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.extras.BodyMapReceiver
import health.pulse.strength.widgets.extras.FormCueReceiver
import health.pulse.strength.widgets.extras.LoadedBarReceiver
import health.pulse.strength.widgets.extras.LogSetReceiver
import health.pulse.strength.widgets.extras.PartnerReceiver
import health.pulse.strength.widgets.extras.PlateauReceiver
import health.pulse.strength.widgets.extras.ReadinessReceiver
import health.pulse.strength.widgets.extras.RestDayReceiver
import health.pulse.strength.widgets.extras.SessionTimelineReceiver
import health.pulse.strength.widgets.extras.StrengthRatioReceiver
import health.pulse.strength.widgets.extras.YearInIronReceiver
import health.pulse.strength.widgets.lock.DaysSinceReceiver
import health.pulse.strength.widgets.lock.InlineStatusRestReceiver
import health.pulse.strength.widgets.lock.InlineStatusSplitReceiver
import health.pulse.strength.widgets.lock.InlineStatusWeekReceiver
import health.pulse.strength.widgets.lock.NextUpCompactReceiver
import health.pulse.strength.widgets.lock.OverloadCompactReceiver
import health.pulse.strength.widgets.lock.PrCompactReceiver
import health.pulse.strength.widgets.lock.QuickStartReceiver
import health.pulse.strength.widgets.lock.StreakReceiver
import health.pulse.strength.widgets.lock.WeeklyGoalCompactReceiver
import health.pulse.strength.widgets.lock.WeeklySetsCompactReceiver
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.xmlpull.v1.XmlPullParser

/**
 * The manifest side of the lock screen and extras widgets: every receiver is declared, exported and labelled, and its provider info
 * has the cell size of its catalogue entry (widgets/SPEC.md: LS-01 ... LS-11 and WI-01 ... WI-11), the right categories and no timer.
 */
@RunWith(RobolectricTestRunner::class)
class WidgetManifestTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private class Declared(val receiver: Class<out GlanceAppWidgetReceiver>, val cellsWide: Int, val cellsHigh: Int, val onLockScreen: Boolean)

    private val declared = listOf(
        Declared(WeeklyGoalCompactReceiver::class.java, 1, 1, onLockScreen = true),
        Declared(DaysSinceReceiver::class.java, 1, 1, onLockScreen = true),
        Declared(StreakReceiver::class.java, 1, 1, onLockScreen = true),
        Declared(QuickStartReceiver::class.java, 1, 1, onLockScreen = true),
        Declared(NextUpCompactReceiver::class.java, 3, 1, onLockScreen = true),
        Declared(WeeklySetsCompactReceiver::class.java, 3, 1, onLockScreen = true),
        Declared(PrCompactReceiver::class.java, 3, 1, onLockScreen = true),
        Declared(OverloadCompactReceiver::class.java, 3, 1, onLockScreen = true),
        Declared(InlineStatusWeekReceiver::class.java, 4, 1, onLockScreen = true),
        Declared(InlineStatusSplitReceiver::class.java, 4, 1, onLockScreen = true),
        Declared(InlineStatusRestReceiver::class.java, 4, 1, onLockScreen = true),
        Declared(BodyMapReceiver::class.java, 4, 2, onLockScreen = false),
        Declared(LogSetReceiver::class.java, 4, 2, onLockScreen = false),
        Declared(PartnerReceiver::class.java, 4, 2, onLockScreen = false),
        Declared(FormCueReceiver::class.java, 2, 2, onLockScreen = false),
        Declared(LoadedBarReceiver::class.java, 2, 2, onLockScreen = false),
        Declared(RestDayReceiver::class.java, 2, 2, onLockScreen = false),
        Declared(StrengthRatioReceiver::class.java, 2, 2, onLockScreen = false),
        Declared(YearInIronReceiver::class.java, 2, 2, onLockScreen = false),
        Declared(ReadinessReceiver::class.java, 4, 2, onLockScreen = false),
        Declared(PlateauReceiver::class.java, 4, 2, onLockScreen = false),
        Declared(SessionTimelineReceiver::class.java, 4, 2, onLockScreen = false),
    )

    private fun providerInfo(receiver: Class<*>): XmlResourceParser {
        val info = context.packageManager.getReceiverInfo(ComponentName(context, receiver), PackageManager.GET_META_DATA)
        val resource = info.metaData.getInt(AppWidgetManager.META_DATA_APPWIDGET_PROVIDER)
        assertThat(resource).isNotEqualTo(0)
        val parser = context.resources.getXml(resource)
        while (parser.eventType != XmlPullParser.START_TAG) parser.next()
        return parser
    }

    @Test
    fun everyReceiverIsDeclaredExportedAndLabelled() {
        for (entry in declared) {
            val info = context.packageManager.getReceiverInfo(ComponentName(context, entry.receiver), PackageManager.GET_META_DATA)
            assertThat(info.exported).isTrue()
            assertThat(info.loadLabel(context.packageManager).toString()).isNotEmpty()
        }
    }

    @Test
    fun everyReceiverIsFoundBySystemAsAnAppWidgetProvider() {
        val providers = context.packageManager.queryBroadcastReceivers(Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE), 0)
            .map { it.activityInfo.name }
        assertThat(providers).containsAtLeastElementsIn(declared.map { it.receiver.name })
    }

    @Test
    fun everyProviderInfoHasTheCellSizeOfItsCatalogueEntry() {
        val android = "http://schemas.android.com/apk/res/android"
        for (entry in declared) {
            val parser = providerInfo(entry.receiver)
            assertThat(parser.getAttributeIntValue(android, "targetCellWidth", 0)).isEqualTo(entry.cellsWide)
            assertThat(parser.getAttributeIntValue(android, "targetCellHeight", 0)).isEqualTo(entry.cellsHigh)
        }
    }

    @Test
    fun everyProviderInfoHasNoTimerADescriptionAndALoadingLayout() {
        val android = "http://schemas.android.com/apk/res/android"
        for (entry in declared) {
            val parser = providerInfo(entry.receiver)
            assertThat(parser.getAttributeIntValue(android, "updatePeriodMillis", -1)).isEqualTo(0)
            assertThat(parser.getAttributeResourceValue(android, "description", 0)).isNotEqualTo(0)
            assertThat(parser.getAttributeResourceValue(android, "initialLayout", 0)).isNotEqualTo(0)
            assertThat(parser.getAttributeIntValue(android, "resizeMode", 0)).isNotEqualTo(0)
            assertThat(context.getString(parser.getAttributeResourceValue(android, "description", 0))).isNotEmpty()
        }
    }

    @Test
    fun lockScreenWidgetsAreAlsoForTheKeyguardAndTheOthersOnlyForTheHomeScreen() {
        val android = "http://schemas.android.com/apk/res/android"
        for (entry in declared) {
            val category = providerInfo(entry.receiver).getAttributeIntValue(android, "widgetCategory", 0)
            val expected = if (entry.onLockScreen) {
                AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN or AppWidgetProviderInfo.WIDGET_CATEGORY_KEYGUARD
            } else {
                AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN
            }
            assertThat(category).isEqualTo(expected)
        }
    }

    @Test
    fun everyReceiverDrawsAPulseWidgetAndEachHasItsOwnPickerLabel() {
        val labels = declared.map { entry ->
            assertThat(entry.receiver.getDeclaredConstructor().newInstance().glanceAppWidget).isInstanceOf(PulseWidget::class.java)
            context.packageManager.getReceiverInfo(ComponentName(context, entry.receiver), 0).loadLabel(context.packageManager).toString()
        }
        assertThat(labels).containsNoDuplicates()
        assertThat(labels).hasSize(22)
    }
}
