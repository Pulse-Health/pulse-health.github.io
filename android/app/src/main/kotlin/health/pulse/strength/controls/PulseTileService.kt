package health.pulse.strength.controls

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import health.pulse.strength.R
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.live.BenchMode
import health.pulse.strength.live.SystemScope
import health.pulse.strength.live.displayPhase
import health.pulse.strength.runtime.StrengthRuntime
import health.pulse.strength.surfaces.Surfaces
import health.pulse.strength.widgets.common.PulseActions
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/**
 * Base of the eight Quick Settings tiles. The tiles are "active" tiles: the system binds a tile only when the user opens the panel or
 * when the app asks through [Controls.refresh]. While it listens, a tile follows `StrengthRuntime.snapshots`; the Rest tile also
 * redraws every second so its subtitle counts down. What a tile shows and does is decided by [TileModels].
 */
abstract class PulseTileService(private val control: Control) : TileService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var listening: Job? = null

    override fun onStartListening() {
        super.onStartListening()
        listening?.cancel()
        listening = scope.launch {
            StrengthRuntime.snapshots.snapshot.collectLatest { snapshot ->
                var now = Instant.now()
                render(snapshot, now)
                while (control == Control.REST && countsDown(snapshot, now)) {
                    delay(MILLIS_PER_SECOND - now.toEpochMilli() % MILLIS_PER_SECOND)
                    now = Instant.now()
                    render(snapshot, now)
                }
            }
        }
    }

    override fun onStopListening() {
        listening?.cancel()
        listening = null
        super.onStopListening()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    override fun onClick() {
        super.onClick()
        when (val action = TileModels.of(control, StrengthRuntime.snapshots.current(), Instant.now()).action) {
            TileAction.None -> Unit
            is TileAction.Command -> {
                val app = applicationContext
                SystemScope.launch {
                    StrengthRuntime.commands.execute(action.command)
                    Surfaces.refreshAll(app)
                }
            }
            is TileAction.Link -> open(PulseActions.linkIntent(action.url))
            TileAction.OpenBench -> open(BenchMode.intent(this))
        }
    }

    private fun render(snapshot: WidgetSnapshot, now: Instant) {
        val tile = qsTile ?: return
        val model = TileModels.of(control, snapshot, now)
        tile.state = when (model.status) {
            TileStatus.ACTIVE -> Tile.STATE_ACTIVE
            TileStatus.INACTIVE -> Tile.STATE_INACTIVE
            TileStatus.UNAVAILABLE -> Tile.STATE_UNAVAILABLE
        }
        tile.label = model.label
        tile.icon = Icon.createWithResource(this, iconOf(model.icon))
        tile.contentDescription = model.contentDescription
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) tile.subtitle = model.subtitle
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) tile.stateDescription = model.stateDescription
        tile.updateTile()
    }

    /** Collapses the panel and opens [intent]; on a locked device the user unlocks first. */
    private fun open(intent: Intent) {
        if (isLocked) unlockAndRun { launch(intent) } else launch(intent)
    }

    // Lint cannot see the version check: the Intent variant is only called below Android 14, where the PendingIntent one does not exist.
    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun launch(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // From Android 14 an app must hand the system a pending intent; the Intent variant throws.
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun countsDown(snapshot: WidgetSnapshot, now: Instant): Boolean {
        val active = snapshot.active ?: return false
        return !active.isPaused && active.displayPhase(now) == SnapshotPhase.RESTING
    }

    private fun iconOf(icon: TileIcon): Int = when (icon) {
        TileIcon.START -> R.drawable.ic_tile_start
        TileIcon.LOG -> R.drawable.ic_tile_log
        TileIcon.REST -> R.drawable.ic_tile_rest
        TileIcon.ADD_REST -> R.drawable.ic_tile_add_rest
        TileIcon.PLATES -> R.drawable.ic_tile_plates
        TileIcon.PAUSE -> R.drawable.ic_tile_pause
        TileIcon.RESUME -> R.drawable.ic_tile_resume
        TileIcon.FINISH -> R.drawable.ic_tile_finish
        TileIcon.NEXT_UP -> R.drawable.ic_tile_next_up
    }

    private companion object {
        const val MILLIS_PER_SECOND = 1_000L
    }
}

/** CT-01 Start next workout. */
class StartNextTileService : PulseTileService(Control.START_NEXT)

/** CT-02 Log set. */
class LogSetTileService : PulseTileService(Control.LOG_SET)

/** CT-03 Rest: the subtitle is the remaining time. */
class RestTileService : PulseTileService(Control.REST)

/** CT-04 +30 s rest. */
class AddRestTileService : PulseTileService(Control.ADD_REST)

/** CT-05 Plate calculator. */
class PlatesTileService : PulseTileService(Control.PLATES)

/** CT-06 Pause / resume: a toggle that is on while the workout is paused. */
class PauseTileService : PulseTileService(Control.PAUSE)

/** CT-07 Finish workout (the app asks for the confirmation). */
class FinishTileService : PulseTileService(Control.FINISH)

/** CT-08 Next up: the label is the split. */
class NextUpTileService : PulseTileService(Control.NEXT_UP)
