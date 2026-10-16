package health.pulse.strength.live

import android.Manifest
import android.app.Application
import android.content.ComponentName
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.service.quicksettings.TileService
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.R
import health.pulse.strength.controls.Controls
import health.pulse.strength.controls.LogSetTileService
import health.pulse.strength.controls.PrimaryActionActivity
import health.pulse.strength.core.widgets.DeepLinks
import kotlinx.coroutines.runBlocking
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.xmlpull.v1.XmlPullParser

/** The manifest region, the launcher shortcuts and the strings of this package, read the way the system reads them. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SystemWiringTest {
    private lateinit var app: Application
    private val androidNs = "http://schemas.android.com/apk/res/android"

    @Before
    fun setUp() {
        app = ApplicationProvider.getApplicationContext()
    }

    private val tileClasses = listOf(
        "StartNextTileService", "LogSetTileService", "RestTileService", "AddRestTileService",
        "PlatesTileService", "PauseTileService", "FinishTileService", "NextUpTileService",
    ).map { "health.pulse.strength.controls.$it" }

    // region Manifest

    @Test
    fun everyTileIsABoundActiveTileWithAnIconAndALabel() {
        val services = app.packageManager.getPackageInfo(app.packageName, PackageManager.GET_SERVICES or PackageManager.GET_META_DATA).services!!
        val tiles = services.filter { it.permission == Manifest.permission.BIND_QUICK_SETTINGS_TILE }
        assertThat(tiles.map { it.name }).containsExactlyElementsIn(tileClasses)
        tiles.forEach {
            assertThat(it.exported).isTrue()
            assertThat(it.icon).isNotEqualTo(0)
            assertThat(it.labelRes).isNotEqualTo(0)
            assertThat(it.metaData.getBoolean(TileService.META_DATA_ACTIVE_TILE)).isTrue()
        }
        val toggles = tiles.filter { it.metaData.getBoolean(TileService.META_DATA_TOGGLEABLE_TILE) }
        assertThat(toggles.map { it.name }).containsExactly("health.pulse.strength.controls.PauseTileService")
    }

    @Test
    fun theSystemFindsAllTilesByTheirAction() {
        val found = app.packageManager.queryIntentServices(Intent(TileService.ACTION_QS_TILE).setPackage(app.packageName), 0)
        assertThat(found.map { it.serviceInfo.name }).containsExactlyElementsIn(tileClasses)
    }

    @Test
    fun theActionButtonActivityIsPrivateAndInvisible() {
        val info = app.packageManager.getActivityInfo(ComponentName(app, PrimaryActionActivity::class.java), 0)
        assertThat(info.exported).isFalse()
        assertThat(info.flags and ActivityInfo.FLAG_EXCLUDE_FROM_RECENTS).isNotEqualTo(0)
        assertThat(info.flags and ActivityInfo.FLAG_NO_HISTORY).isNotEqualTo(0)
        assertThat(info.theme).isEqualTo(R.style.Theme_PulseTransparent)
    }

    @Test
    fun benchModeIsPrivateAndDark() {
        val info = app.packageManager.getActivityInfo(ComponentName(app, BenchModeActivity::class.java), 0)
        assertThat(info.exported).isFalse()
        assertThat(info.theme).isEqualTo(R.style.Theme_PulseBench)
        assertThat(BenchMode.intent(app).component?.className).isEqualTo(BenchModeActivity::class.java.name)
    }

    @Test
    fun theLauncherActivityCarriesTheShortcutsAndThereIsOnlyOneLauncherEntry() {
        val main = app.packageManager.getActivityInfo(ComponentName(app, "health.pulse.strength.MainActivity"), PackageManager.GET_META_DATA)
        assertThat(main.exported).isTrue()
        assertThat(main.metaData.getInt("android.app.shortcuts")).isEqualTo(R.xml.shortcuts)
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setPackage(app.packageName)
        assertThat(app.packageManager.queryIntentActivities(launcher, 0).map { it.activityInfo.name })
            .containsExactly("health.pulse.strength.MainActivity")
    }

    @Test
    fun theReceiversAreNotExportedAndTheBootReceiverIsRegistered() {
        val receivers = app.packageManager.getPackageInfo(app.packageName, PackageManager.GET_RECEIVERS).receivers!!.associateBy { it.name }
        listOf(WorkoutActionReceiver::class.java, LiveAlarmReceiver::class.java, PlannedSessionReceiver::class.java).forEach {
            assertThat(receivers.getValue(it.name).exported).isFalse()
        }
        val boot = app.packageManager.queryBroadcastReceivers(Intent(Intent.ACTION_BOOT_COMPLETED), 0)
        assertThat(boot.map { it.activityInfo.name }).contains(PlannedSessionReceiver::class.java.name)
    }

    @Test
    fun theOnlyPermissionThisPackageAddsIsTheBootReceiver() {
        val permissions = app.packageManager.getPackageInfo(app.packageName, PackageManager.GET_PERMISSIONS).requestedPermissions!!.toList()
        assertThat(permissions).contains(Manifest.permission.RECEIVE_BOOT_COMPLETED)
        assertThat(permissions).containsNoneOf(
            Manifest.permission.SCHEDULE_EXACT_ALARM,
            Manifest.permission.USE_EXACT_ALARM,
            Manifest.permission.VIBRATE,
            Manifest.permission.INTERNET,
            Manifest.permission.ACCESS_NETWORK_STATE,
        )
    }

    // endregion

    // region Shortcuts

    private class Shortcut(val id: String, val shortLabel: Int, val longLabel: Int, val icon: Int, val targetClass: String?, val data: String?)

    private fun parseShortcuts(): Pair<List<Shortcut>, Map<String, String?>> {
        val shortcuts = mutableListOf<Shortcut>()
        val capabilities = mutableMapOf<String, String?>()
        val parser = app.resources.getXml(R.xml.shortcuts)
        var capability: String? = null
        var current: MutableMap<String, String?>? = null
        var event = parser.eventType
        while (event != XmlPullParser.END_DOCUMENT) {
            if (event == XmlPullParser.START_TAG) {
                when (parser.name) {
                    "capability" -> {
                        capability = parser.getAttributeValue(androidNs, "name")
                        capabilities[capability!!] = null
                    }
                    "url-template" -> capabilities[capability!!] = parser.getAttributeValue(androidNs, "value")
                    "shortcut" -> current = mutableMapOf(
                        "id" to parser.getAttributeValue(androidNs, "shortcutId"),
                        "short" to parser.getAttributeResourceValue(androidNs, "shortcutShortLabel", 0).toString(),
                        "long" to parser.getAttributeResourceValue(androidNs, "shortcutLongLabel", 0).toString(),
                        "icon" to parser.getAttributeResourceValue(androidNs, "icon", 0).toString(),
                    )
                    "intent" -> if (current != null) {
                        current["class"] = parser.getAttributeValue(androidNs, "targetClass")
                        current["data"] = parser.getAttributeValue(androidNs, "data")
                    }
                }
            } else if (event == XmlPullParser.END_TAG && parser.name == "shortcut") {
                val c = current!!
                shortcuts += Shortcut(c.getValue("id")!!, c.getValue("short")!!.toInt(), c.getValue("long")!!.toInt(), c.getValue("icon")!!.toInt(), c["class"], c["data"])
                current = null
            }
            event = parser.next()
        }
        return shortcuts to capabilities
    }

    @Test
    fun theStaticShortcutsAreThePrimaryActionStartAndPlates() {
        val (shortcuts, _) = parseShortcuts()
        assertThat(shortcuts.map { it.id }).containsExactly("primary_action", "start_workout", "plates").inOrder()
        val byId = shortcuts.associateBy { it.id }
        assertThat(byId.getValue("primary_action").targetClass).isEqualTo(PrimaryActionActivity::class.java.name)
        assertThat(byId.getValue("start_workout").data).isEqualTo(DeepLinks.startNext)
        assertThat(byId.getValue("start_workout").targetClass).isEqualTo("health.pulse.strength.MainActivity")
        assertThat(byId.getValue("plates").data).isEqualTo(DeepLinks.plates)
        shortcuts.forEach {
            assertThat(it.icon).isNotEqualTo(0)
            assertThat(app.getString(it.shortLabel)).isNotEmpty()
            assertThat(app.getString(it.longLabel)).isNotEmpty()
        }
        assertThat(app.getString(byId.getValue("primary_action").shortLabel)).isEqualTo("Primary action")
        assertThat(app.getString(byId.getValue("start_workout").shortLabel)).isEqualTo("Start workout")
        assertThat(app.getString(byId.getValue("plates").shortLabel)).isEqualTo("Plates")
    }

    @Test
    fun theStartExerciseCapabilityStartsTheNextWorkout() {
        val (_, capabilities) = parseShortcuts()
        assertThat(capabilities).containsExactly("actions.intent.START_EXERCISE", DeepLinks.startNext)
    }

    @Test
    fun everyShortcutTargetIsARealClass() {
        val (shortcuts, _) = parseShortcuts()
        shortcuts.mapNotNull { it.targetClass }.forEach { assertThat(Class.forName(it)).isNotNull() }
    }

    // endregion

    // region Strings

    @Test
    fun theManifestLabelsOfTheTilesAreTheNamesTheTilesShow() {
        assertThat(app.getString(R.string.tile_start_next_label)).isEqualTo("Start workout")
        assertThat(app.getString(R.string.tile_log_set_label)).isEqualTo("Log set")
        assertThat(app.getString(R.string.tile_rest_label)).isEqualTo("Rest")
        assertThat(app.getString(R.string.tile_add_rest_label)).isEqualTo("+30 s rest")
        assertThat(app.getString(R.string.tile_plates_label)).isEqualTo("Plates")
        assertThat(app.getString(R.string.tile_pause_label)).isEqualTo("Pause workout")
        assertThat(app.getString(R.string.tile_finish_label)).isEqualTo("Finish workout")
        assertThat(app.getString(R.string.tile_next_up_label)).isEqualTo("Next up")
    }

    // endregion

    @Test
    fun refreshingTheTilesNeedsNoUserAndDoesNotFail() {
        runBlocking { Controls.refresh(app) }
        assertThat(LogSetTileService::class.java.superclass).isNotNull()
    }
}
