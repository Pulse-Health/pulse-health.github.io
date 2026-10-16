package health.pulse.strength.wear

import android.Manifest
import android.app.Application
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.NoDataComplicationData
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.widgets.WearProtocol
import health.pulse.strength.wear.complications.ComplicationFactory
import health.pulse.strength.wear.complications.ComplicationPreview
import health.pulse.strength.wear.complications.DaysSinceComplicationService
import health.pulse.strength.wear.complications.NextUpComplicationService
import health.pulse.strength.wear.complications.PulseComplicationService
import health.pulse.strength.wear.complications.RestComplicationService
import health.pulse.strength.wear.complications.StartComplicationService
import health.pulse.strength.wear.complications.StreakComplicationService
import health.pulse.strength.wear.complications.WeeklyGoalComplicationService
import health.pulse.strength.wear.complications.WeeklySetsComplicationService
import health.pulse.strength.wear.sync.TileComplicationUpdater
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner

/** The watch app's manifest: what the system binds, with which permission, and that every service is also refreshed when data arrives. */
@RunWith(RobolectricTestRunner::class)
class ManifestTest {
    private val app = ApplicationProvider.getApplicationContext<Application>()
    private val packageManager = app.packageManager

    private fun services(): List<ServiceInfo> =
        packageManager.getPackageInfo(app.packageName, PackageManager.GET_SERVICES or PackageManager.GET_META_DATA).services.orEmpty().toList()

    private fun withPermission(permission: String) = services().filter { it.permission == permission }

    private fun info(service: Class<*>): ServiceInfo =
        packageManager.getServiceInfo(ComponentName(app, service), PackageManager.GET_META_DATA)

    @Test
    fun everyTileServiceOfTheManifestIsRefreshedWhenDataArrives() {
        val declared = withPermission("com.google.android.wearable.permission.BIND_TILE_PROVIDER").map { it.name }

        assertThat(declared).containsExactlyElementsIn(TileComplicationUpdater.tiles.map { it.name })
        assertThat(declared).hasSize(5)
    }

    @Test
    fun everyComplicationServiceOfTheManifestIsRefreshedWhenDataArrives() {
        val declared = withPermission("com.google.android.wearable.permission.BIND_COMPLICATION_PROVIDER").map { it.name }

        assertThat(declared).containsExactlyElementsIn(TileComplicationUpdater.complications.map { it.name })
        assertThat(declared).hasSize(7)
    }

    @Test
    fun tilesAndComplicationsAreExportedWithALabelAndAnIcon() {
        (TileComplicationUpdater.tiles + TileComplicationUpdater.complications).forEach { service ->
            val info = info(service)
            assertThat(info.exported).isTrue()
            assertThat(info.labelRes).isNotEqualTo(0)
            assertThat(info.icon).isNotEqualTo(0)
        }
    }

    @Test
    fun theTileBindActionFindsEveryTileOfTheApp() {
        val intent = Intent("androidx.wear.tiles.action.BIND_TILE_PROVIDER").setPackage(app.packageName)

        val found = packageManager.queryIntentServices(intent, 0).map { it.serviceInfo.name }

        assertThat(found).containsExactlyElementsIn(TileComplicationUpdater.tiles.map { it.name })
    }

    @Test
    fun theComplicationUpdateActionFindsEveryComplicationOfTheApp() {
        val intent = Intent("android.support.wearable.complications.ACTION_COMPLICATION_UPDATE_REQUEST").setPackage(app.packageName)

        val found = packageManager.queryIntentServices(intent, 0).map { it.serviceInfo.name }

        assertThat(found).containsExactlyElementsIn(TileComplicationUpdater.complications.map { it.name })
    }

    @Test
    fun everyComplicationIsPushedNotPolled() {
        TileComplicationUpdater.complications.forEach { source ->
            assertThat(info(source).metaData.get("android.support.wearable.complications.UPDATE_PERIOD_SECONDS")).isEqualTo(0)
        }
    }

    @Test
    fun theDeclaredTypesAreExactlyTheTypesEachComplicationAnswers() {
        val view = ComplicationPreview.view
        val factory = ComplicationFactory(app)
        val answering = mapOf<Class<*>, (ComplicationType) -> Boolean>(
            WeeklyGoalComplicationService::class.java to { type -> factory.weeklyGoal(type, view) !is NoDataComplicationData },
            DaysSinceComplicationService::class.java to { type -> factory.daysSince(type, view) !is NoDataComplicationData },
            NextUpComplicationService::class.java to { type -> factory.nextUp(type, view) !is NoDataComplicationData },
            StartComplicationService::class.java to { type -> factory.start(type, view) !is NoDataComplicationData },
            StreakComplicationService::class.java to { type -> factory.streak(type, view) !is NoDataComplicationData },
            WeeklySetsComplicationService::class.java to { type -> factory.weeklySets(type, view) !is NoDataComplicationData },
            RestComplicationService::class.java to { type -> factory.rest(type, view, WearFixtures.now) != null },
        )
        val testable = listOf(
            ComplicationType.SHORT_TEXT,
            ComplicationType.LONG_TEXT,
            ComplicationType.RANGED_VALUE,
            ComplicationType.MONOCHROMATIC_IMAGE,
            ComplicationType.SMALL_IMAGE,
        )

        assertThat(answering.keys).containsExactlyElementsIn(TileComplicationUpdater.complications)
        answering.forEach { (service, answers) ->
            val declared = info(service).metaData.getString("android.support.wearable.complications.SUPPORTED_TYPES")!!
                .split(",")
                .map { ComplicationType.valueOf(it) }
            assertThat(testable.filter(answers)).containsExactlyElementsIn(declared)
        }
    }

    @Test
    fun everyComplicationOffersPreviewDataForItsDeclaredTypesOnly() {
        TileComplicationUpdater.complications.forEach { source ->
            val declared = info(source).metaData.getString("android.support.wearable.complications.SUPPORTED_TYPES")!!
                .split(",")
                .map { ComplicationType.valueOf(it) }
            val service = Robolectric.buildService(source).create().get()
            val previewOf: (ComplicationType) -> Any? = when (service) {
                is PulseComplicationService -> { type -> service.getPreviewData(type) }
                is RestComplicationService -> { type -> service.getPreviewData(type) }
                else -> error("${source.simpleName} is not a complication service of this app")
            }
            declared.forEach { type -> assertThat(previewOf(type)).isNotNull() }
            (ComplicationType.entries - declared.toSet() - setOf(ComplicationType.NO_DATA, ComplicationType.EMPTY, ComplicationType.NOT_CONFIGURED))
                .forEach { type -> assertThat(previewOf(type)).isNull() }
        }
    }

    @Test
    fun theDataLayerListenerHearsChangesOfTheSnapshotPathFromAnyNode() {
        val intent = Intent("com.google.android.gms.wearable.DATA_CHANGED")
            .setData(Uri.parse("wear://some-phone-node" + WearProtocol.SNAPSHOT_PATH))

        val matches = packageManager.queryIntentServices(intent, 0)

        assertThat(matches.map { it.serviceInfo.name }).containsExactly("health.pulse.strength.wear.sync.WearSnapshotListenerService")
        assertThat(matches.single().serviceInfo.exported).isTrue()
    }

    @Test
    fun theDataLayerListenerDoesNotHearOtherPaths() {
        val intent = Intent("com.google.android.gms.wearable.DATA_CHANGED").setData(Uri.parse("wear://some-phone-node/other/path"))

        assertThat(packageManager.queryIntentServices(intent, 0)).isEmpty()
    }

    @Test
    fun theActivityIsTheLauncherAndAcceptsLaunchActionsOfTilesAndComplications() {
        val info = packageManager.getActivityInfo(ComponentName(app, WearMainActivity::class.java), 0)

        assertThat(info.exported).isTrue()
        assertThat(info.launchMode).isEqualTo(android.content.pm.ActivityInfo.LAUNCH_SINGLE_TOP)
    }

    @Test
    fun theWatchAppAsksForNotificationsOnlyAndHasNoNetworkAccess() {
        val requested = packageManager.getPackageInfo(app.packageName, PackageManager.GET_PERMISSIONS).requestedPermissions.orEmpty().toList()

        assertThat(requested).contains(Manifest.permission.POST_NOTIFICATIONS)
        assertThat(requested).containsNoneOf(Manifest.permission.INTERNET, Manifest.permission.ACCESS_NETWORK_STATE)
    }
}
