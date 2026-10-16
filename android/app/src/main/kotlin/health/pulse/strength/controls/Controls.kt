package health.pulse.strength.controls

import android.content.ComponentName
import android.content.Context
import android.service.quicksettings.TileService

/**
 * CT-01 ... CT-08 Quick Settings tiles and the Action-button analogue (CT-10). Refreshes every surface of this group after the snapshot
 * changed (see Surfaces): each tile that the user added is asked to listen for a moment, which redraws it from the new snapshot.
 */
object Controls {
    private val tileServices: List<Class<out TileService>> = listOf(
        StartNextTileService::class.java,
        LogSetTileService::class.java,
        RestTileService::class.java,
        AddRestTileService::class.java,
        PlatesTileService::class.java,
        PauseTileService::class.java,
        FinishTileService::class.java,
        NextUpTileService::class.java,
    )

    suspend fun refresh(context: Context) {
        val app = context.applicationContext
        tileServices.forEach { TileService.requestListeningState(app, ComponentName(app, it)) }
    }
}
