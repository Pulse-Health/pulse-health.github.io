package health.pulse.strength.wear.tiles

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import androidx.wear.protolayout.DeviceParametersBuilders
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.wear.WearFixtures
import health.pulse.strength.wear.WearFixtures.now
import health.pulse.strength.wear.data.FakePhoneLink
import health.pulse.strength.wear.data.WearRuntime
import health.pulse.strength.wear.data.WearView
import health.pulse.strength.wear.sync.SnapshotIngest
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner

/**
 * Every tile in every state at three screen sizes and with big fonts: the Material layouts throw when a component is built without
 * what it needs (a chip without a label, a layout without content), so building them all is a real check.
 */
@RunWith(RobolectricTestRunner::class)
class TileSmokeTest {
    private val context = ApplicationProvider.getApplicationContext<Application>()

    @Before
    fun setUp() {
        SnapshotIngest.resetForTest()
        WearRuntime.installForTest(null, FakePhoneLink())
    }

    @After
    fun tearDown() {
        WearRuntime.resetForTest()
        SnapshotIngest.resetForTest()
    }

    private val empty = WearFixtures.preview.copy(
        nextUp = null,
        latestPR = null,
        lifts = emptyList(),
        lastSession = null,
        templates = emptyList(),
    )

    private val longNames = WearFixtures.workout(
        exerciseName = "Single-Arm Cable Crossover with Rotational Finish",
        workoutName = "Upper Body Hypertrophy Block with Extra Accessories",
    )

    private fun views(): Map<String, WearView> = mapOf(
        "waiting" to WearFixtures.view(isPlaceholder = true),
        "preview" to WearFixtures.view(),
        "empty" to WearFixtures.view(empty),
        "logging" to WearFixtures.view(WearFixtures.withWorkout(WearFixtures.workout())),
        "bodyweight" to WearFixtures.view(WearFixtures.withWorkout(WearFixtures.workout(tracking = TrackingKind.REPS_ONLY, showsWeight = false))),
        "resting" to WearFixtures.view(WearFixtures.withWorkout(WearFixtures.resting())),
        "restOver" to WearFixtures.view(WearFixtures.withWorkout(WearFixtures.workout(phase = SnapshotPhase.REST_OVER))),
        "paused" to WearFixtures.view(WearFixtures.withWorkout(WearFixtures.workout(isPaused = true))),
        "complete" to WearFixtures.view(WearFixtures.withWorkout(WearFixtures.workout(phase = SnapshotPhase.COMPLETE))),
        "longNames" to WearFixtures.view(WearFixtures.withWorkout(longNames)),
    )

    private fun allTiles() = listOf(NextUpTile(), WorkoutTile(), RecordTile(), LiftTrendTile(), HeartRateTile())

    private fun device(size: Int, fontScale: Float): DeviceParametersBuilders.DeviceParameters = DeviceParametersBuilders.DeviceParameters.Builder()
        .setScreenWidthDp(size)
        .setScreenHeightDp(size)
        .setScreenDensity(2f)
        .setFontScale(fontScale)
        .setScreenShape(DeviceParametersBuilders.SCREEN_SHAPE_ROUND)
        .setDevicePlatform(DeviceParametersBuilders.DEVICE_PLATFORM_WEAR_OS)
        .build()

    @Test
    fun everyTileBuildsInEveryStateOnEverySizeAndWithBigFonts() {
        for (tile in allTiles()) {
            for ((_, view) in views()) {
                for ((size, fontScale) in listOf(192 to 1f, 227 to 1f, 250 to 1f, 192 to 1.3f)) {
                    val plan = tile.plan(TileUi(context, device(size, fontScale)), view, now)

                    assertThat(plan.timeline.timelineEntries).isNotEmpty()
                    plan.entries().forEach { (_, layout) -> assertThat(layout.inspect().textValues).isNotEmpty() }
                    assertThat(plan.freshnessMillis).isGreaterThan(0L)
                    assertThat(plan.resourcesVersion).isNotEmpty()
                }
            }
        }
    }

    @Test
    fun everyTileAnswersARequestWithItsTimelineAndResources() = runTest {
        val services = listOf(
            Robolectric.setupService(NextUpTile::class.java),
            Robolectric.setupService(WorkoutTile::class.java),
            Robolectric.setupService(RecordTile::class.java),
            Robolectric.setupService(LiftTrendTile::class.java),
            Robolectric.setupService(HeartRateTile::class.java),
        )

        for (service in services) {
            val tile = service.respond(deviceParameters(), "")

            assertThat(tile.timelineEntries()).isNotEmpty()
            val resources = service.resources(tile.resourcesVersion, deviceParameters(), WearRuntime.view())
            assertThat(resources.version).isEqualTo(tile.resourcesVersion)
            assertThat(resources.idToImageMapping.keys)
                .containsAtLeast(TileIcons.PLAY, TileIcons.HAND, TileIcons.TROPHY, TileIcons.HEART, TileIcons.DUMBBELL)
        }
    }
}
