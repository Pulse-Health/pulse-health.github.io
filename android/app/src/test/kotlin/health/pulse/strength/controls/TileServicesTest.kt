package health.pulse.strength.controls

import android.os.Looper
import android.service.quicksettings.Tile
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.live.loggingSnapshot
import health.pulse.strength.live.pausedSnapshot
import health.pulse.strength.live.previewWith
import health.pulse.strength.live.restingSnapshot
import health.pulse.strength.runtime.PreviewRuntime
import health.pulse.strength.runtime.StrengthRuntime
import java.time.Instant
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * The tile services as the system drives them: a tile draws what [TileModels] says while the panel listens, follows the snapshots
 * only then, and a click reaches the engine through `StrengthRuntime.commands`. The tile services read the real clock, so the
 * resting workout here is built from it.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class TileServicesTest {
    private lateinit var runtime: PreviewRuntime

    @Before
    fun install() {
        runtime = PreviewRuntime()
        StrengthRuntime.installForTest(runtime)
    }

    @After
    fun restore() {
        StrengthRuntime.installForTest(PreviewRuntime())
    }

    /** The resting workout of the fixtures, moved so that [remaining] seconds of the rest are left at the real now. */
    private fun restingFromNow(remaining: Long = 84): WorkoutSnapshot {
        val now = Instant.now()
        return restingSnapshot().copy(restStartedAt = now.plusSeconds(remaining - 120), restEndsAt = now.plusSeconds(remaining))
    }

    private inline fun <reified T : PulseTileService> serviceFor(active: WorkoutSnapshot?): T {
        runtime.publish(previewWith(active))
        return Robolectric.setupService(T::class.java)
    }

    /** Clicks the tile and returns the commands the engine saw; the command runs on the app scope, so this waits a moment for it. */
    private inline fun <reified T : PulseTileService> click(active: WorkoutSnapshot?): List<String> {
        serviceFor<T>(active).onClick()
        repeat(100) {
            if (runtime.received.isNotEmpty()) return runtime.received.toList()
            Thread.sleep(10)
        }
        return runtime.received.toList()
    }

    private inline fun <reified T : PulseTileService> clickWithoutEffect(active: WorkoutSnapshot?): List<String> {
        serviceFor<T>(active).onClick()
        Thread.sleep(100)
        return runtime.received.toList()
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    // region Click

    @Test
    fun logSetLogsTheNextSet() {
        assertThat(click<LogSetTileService>(loggingSnapshot())).containsExactly("logNextSet")
    }

    @Test
    fun addRestAddsThirtySecondsToTheRunningRest() {
        assertThat(click<AddRestTileService>(restingFromNow())).containsExactly("adjustRest:30")
    }

    @Test
    fun pauseTogglesBetweenPauseAndResume() {
        assertThat(click<PauseTileService>(loggingSnapshot())).containsExactly("pause")
        runtime.received.clear()
        assertThat(click<PauseTileService>(pausedSnapshot())).containsExactly("resume")
    }

    @Test
    fun aTileThatIsUnavailableDoesNothing() {
        assertThat(clickWithoutEffect<LogSetTileService>(null)).isEmpty()
        assertThat(clickWithoutEffect<AddRestTileService>(loggingSnapshot())).isEmpty()
        assertThat(clickWithoutEffect<PauseTileService>(null)).isEmpty()
    }

    // endregion

    // region Drawing

    @Test
    fun theRestTileShowsTheRemainingTimeAsItsValue() {
        val service = serviceFor<RestTileService>(restingFromNow(remaining = 84))
        service.onStartListening()
        val tile = service.qsTile
        assertThat(tile.state).isEqualTo(Tile.STATE_ACTIVE)
        assertThat(tile.label.toString()).isEqualTo("Rest")
        // The clock may have ticked between building the workout and drawing the tile.
        assertThat(tile.subtitle.toString()).isIn(listOf("1:24", "1:23"))
        assertThat(tile.contentDescription.toString()).startsWith("Rest, 1:2")
        service.onStopListening()
    }

    @Test
    fun aTileWithNothingToDoIsGreyedOutAndSaysWhy() {
        val service = serviceFor<LogSetTileService>(null)
        service.onStartListening()
        assertThat(service.qsTile.state).isEqualTo(Tile.STATE_UNAVAILABLE)
        assertThat(service.qsTile.subtitle.toString()).isEqualTo("No workout")
        service.onStopListening()
    }

    @Test
    fun thePauseTileIsOnWhileTheWorkoutIsPausedAndSaysSo() {
        val service = serviceFor<PauseTileService>(pausedSnapshot())
        service.onStartListening()
        val tile = service.qsTile
        assertThat(tile.state).isEqualTo(Tile.STATE_ACTIVE)
        assertThat(tile.label.toString()).isEqualTo("Resume workout")
        assertThat(tile.stateDescription.toString()).isEqualTo("Paused")
        service.onStopListening()
    }

    @Test
    fun aTileFollowsTheSnapshotsOnlyWhileItListens() {
        val service = serviceFor<LogSetTileService>(loggingSnapshot())
        service.onStartListening()
        assertThat(service.qsTile.state).isEqualTo(Tile.STATE_ACTIVE)

        runtime.publish(previewWith(null))
        idle()
        assertThat(service.qsTile.state).isEqualTo(Tile.STATE_UNAVAILABLE)

        service.onStopListening()
        runtime.publish(previewWith(loggingSnapshot()))
        idle()
        assertThat(service.qsTile.state).isEqualTo(Tile.STATE_UNAVAILABLE)

        service.onStartListening()
        assertThat(service.qsTile.state).isEqualTo(Tile.STATE_ACTIVE)
        service.onStopListening()
    }

    // endregion
}
